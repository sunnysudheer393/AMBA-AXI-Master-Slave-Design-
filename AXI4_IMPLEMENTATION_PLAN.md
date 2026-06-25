# AXI4 SystemVerilog Implementation Plan

## 1. Design Goal

Build a reusable AMBA AXI4 memory-mapped master/slave design in SystemVerilog.
The design must model the five AXI4 channels:

- Write address channel: `AW`
- Write data channel: `W`
- Write response channel: `B`
- Read address channel: `AR`
- Read data channel: `R`

This project targets AXI4 memory-mapped transfers. It is not AXI4-Lite and not
AXI-Stream. The first RTL version should be understandable, synthesizable where
practical, and structured so it can later be verified using either plain
SystemVerilog or UVM.

Reference material:

- Local spec: `AXI4_specification.pdf`
- Arm AMBA specifications page:
  https://www.arm.com/products/silicon-ip-system/embedded-system-design/amba-specifications

## 2. Recommended Implementation Style

Use a reusable RTL structure with a package, interface, master, memory slave,
top wrapper, and basic smoke test:

```text
rtl/
  axi_pkg.sv
  axi_if.sv
  axi_master.sv
  axi_slave_mem.sv
  axi_top.sv

sim/
  tb_axi_basic.sv
```

This is better than one large master/slave FSM because AXI channels are
independent. Keeping the logic separated by channel makes it easier to debug
waveforms and easier to wrap with UVM agents later.

## 3. Core Parameters

Use these parameters consistently across all RTL modules:

| Parameter | Default | Purpose |
| --- | ---: | --- |
| `ADDR_WIDTH` | `32` | Address width in bits |
| `DATA_WIDTH` | `32` | Data width in bits; must be divisible by 8 |
| `STRB_WIDTH` | `DATA_WIDTH/8` | Number of byte lanes |
| `ID_WIDTH` | `4` | AXI transaction ID width |
| `LEN_WIDTH` | `8` | AXI4 burst length field width |
| `SIZE_WIDTH` | `3` | AXI burst size field width |
| `BURST_WIDTH` | `2` | AXI burst type field width |
| `RESP_WIDTH` | `2` | AXI response field width |
| `MEM_DEPTH` | `1024` | Slave memory depth in data words |
| `MAX_BURST_LEN` | `16` | Bring-up limit; later expand to 256 |
| `OUTSTANDING_DEPTH` | `4` | Max outstanding transactions per direction |
| `SUPPORT_OOO` | `1` | Enable out-of-order completion across IDs |

Rules:

- `DATA_WIDTH % 8` must be zero.
- `STRB_WIDTH` must always be derived from `DATA_WIDTH`.
- `MAX_BURST_LEN` is a design limit, not the AXI field width. AXI4 can encode up
  to 256 beats using `AxLEN = beats - 1`.
- Start with `MAX_BURST_LEN = 16` to simplify debug, then raise it after the
  base design works.

## 4. AXI4 Signal Set For Version 1

Implement the required memory-mapped AXI4 signals below. Defer optional sideband
signals until the core protocol is stable.

### Write Address Channel

Master drives:

- `AWID[ID_WIDTH-1:0]`
- `AWADDR[ADDR_WIDTH-1:0]`
- `AWLEN[7:0]`
- `AWSIZE[2:0]`
- `AWBURST[1:0]`
- `AWVALID`

Slave drives:

- `AWREADY`

### Write Data Channel

Master drives:

- `WDATA[DATA_WIDTH-1:0]`
- `WSTRB[STRB_WIDTH-1:0]`
- `WLAST`
- `WVALID`

Slave drives:

- `WREADY`

AXI4 does not have `WID`. This means write data is not tagged by ID on the write
data channel. Do not implement AXI3-style write-data interleaving in an AXI4
design.

### Write Response Channel

Slave drives:

- `BID[ID_WIDTH-1:0]`
- `BRESP[1:0]`
- `BVALID`

Master drives:

- `BREADY`

### Read Address Channel

Master drives:

- `ARID[ID_WIDTH-1:0]`
- `ARADDR[ADDR_WIDTH-1:0]`
- `ARLEN[7:0]`
- `ARSIZE[2:0]`
- `ARBURST[1:0]`
- `ARVALID`

Slave drives:

- `ARREADY`

### Read Data Channel

Slave drives:

- `RID[ID_WIDTH-1:0]`
- `RDATA[DATA_WIDTH-1:0]`
- `RRESP[1:0]`
- `RLAST`
- `RVALID`

Master drives:

- `RREADY`

### Deferred Optional Signals

Leave these out of version 1 unless a later requirement needs them:

- `AxPROT`
- `AxCACHE`
- `AxLOCK`
- `AxQOS`
- `AxREGION`
- `AxUSER`
- `WUSER`
- `BUSER`
- `RUSER`

## 5. `rtl/axi_pkg.sv`

Create a shared package for protocol constants, enums, structs, and helper
functions.

### Enums

Define AXI response values:

```systemverilog
typedef enum logic [1:0] {
  AXI_RESP_OKAY   = 2'b00,
  AXI_RESP_EXOKAY = 2'b01,
  AXI_RESP_SLVERR = 2'b10,
  AXI_RESP_DECERR = 2'b11
} axi_resp_e;
```

Define AXI burst values:

```systemverilog
typedef enum logic [1:0] {
  AXI_BURST_FIXED = 2'b00,
  AXI_BURST_INCR  = 2'b01,
  AXI_BURST_WRAP  = 2'b10
} axi_burst_e;
```

### Helper Functions

Implement these helpers:

- `bytes_per_beat(axsize)`: returns `1 << axsize`.
- `burst_beats(axlen)`: returns `axlen + 1`.
- `aligned_addr(addr, bytes)`: returns address aligned down to beat size.
- `next_burst_addr(addr, axsize, axburst, axlen, beat_index)`: calculates the
  next address for `FIXED`, `INCR`, and later `WRAP` bursts.
- `addr_in_range(addr, bytes, mem_bytes)`: checks whether a beat is inside the
  slave memory range.

For version 1, implement `INCR` fully. Include enum definitions for `FIXED` and
`WRAP`, but it is acceptable to return `SLVERR` for unsupported burst modes
until they are implemented.

### Internal Transaction Structs

Use structs internally to keep queue entries clean:

```systemverilog
typedef struct packed {
  logic [ID_WIDTH-1:0]   id;
  logic [ADDR_WIDTH-1:0] addr;
  logic [7:0]            len;
  logic [2:0]            size;
  axi_burst_e            burst;
} axi_addr_cmd_t;
```

Because SystemVerilog packages cannot directly see module parameters unless
they are package parameters, either:

- make the package parameterized using fixed project defaults, or
- define generic structs locally inside modules after parameters are known.

Recommended for beginner clarity: keep enums and pure helper functions in the
package, then define width-dependent structs inside each module.

## 6. `rtl/axi_if.sv`

Create one SystemVerilog interface containing all five AXI4 channels.

Recommended style:

```systemverilog
interface axi_if #(
  parameter int ADDR_WIDTH = 32,
  parameter int DATA_WIDTH = 32,
  parameter int ID_WIDTH   = 4
) (
  input logic ACLK,
  input logic ARESETn
);
```

Inside the interface:

- derive `localparam int STRB_WIDTH = DATA_WIDTH / 8;`
- declare all AXI signals
- add a `master` modport
- add a `slave` modport

The master modport should output `AW`, `W`, and `AR` request signals, input
`AWREADY`, `WREADY`, `B`, `ARREADY`, and `R` response signals, and output
`BREADY`/`RREADY`.

The slave modport should be the inverse.

Be consistent with signal names. Use standard uppercase AXI names in the
interface and refer to them as `axi.AWVALID`, `axi.WDATA`, and so on inside
modules.

## 7. `rtl/axi_master.sv`

The master should be command-driven. It should not hard-code one transaction
sequence forever.

### External Command Interface

For version 1, expose simple command/data ports instead of a full processor
front end:

Write command input:

- `wr_cmd_valid`
- `wr_cmd_ready`
- `wr_cmd_id`
- `wr_cmd_addr`
- `wr_cmd_len`
- `wr_cmd_size`
- `wr_cmd_burst`

Write data input:

- `wr_data_valid`
- `wr_data_ready`
- `wr_data`
- `wr_strb`
- `wr_last`

Write response output:

- `wr_rsp_valid`
- `wr_rsp_ready`
- `wr_rsp_id`
- `wr_rsp_resp`

Read command input:

- `rd_cmd_valid`
- `rd_cmd_ready`
- `rd_cmd_id`
- `rd_cmd_addr`
- `rd_cmd_len`
- `rd_cmd_size`
- `rd_cmd_burst`

Read data output:

- `rd_data_valid`
- `rd_data_ready`
- `rd_data_id`
- `rd_data`
- `rd_data_resp`
- `rd_data_last`

This interface makes the master reusable. A testbench can drive commands, and a
future DMA or CPU-side controller can also drive the same master.

### Master Write Path

Implement the write path as three cooperating pieces:

- AW issue logic
- W beat issue logic
- B response tracking logic

AW behavior:

- accept a write command when there is a free outstanding slot
- capture ID, address, length, size, and burst
- assert `AWVALID`
- hold all `AW*` payload stable until `AWVALID && AWREADY`
- mark the transaction as address-issued after handshake

W behavior:

- send `AWLEN + 1` data beats
- assert `WLAST` on the final beat only
- hold `WDATA`, `WSTRB`, and `WLAST` stable while `WVALID && !WREADY`
- do not send more beats than the command length

B behavior:

- keep `BREADY` asserted when the master can accept a response
- on `BVALID && BREADY`, match `BID` against an outstanding write slot
- report `BRESP` on the command-side response port
- free the outstanding slot only after the response has been accepted

Important AXI4 detail:

- AXI4 has no `WID`, so write data ordering follows the accepted write address
  stream. The master must not interleave write data beats from different write
  bursts.

### Master Read Path

Implement the read path as two cooperating pieces:

- AR issue logic
- R data collection/response logic

AR behavior:

- accept a read command when there is a free outstanding slot
- assert `ARVALID`
- hold `AR*` payload stable until `ARVALID && ARREADY`
- store expected beat count for the ID/slot

R behavior:

- keep `RREADY` asserted when the command-side read-data port can accept data
- on `RVALID && RREADY`, match `RID` against an outstanding read slot
- forward `RID`, `RDATA`, `RRESP`, and `RLAST`
- count beats per transaction
- free the slot only after `RLAST` is accepted

If `SUPPORT_OOO = 1`, `R` beats for different IDs may arrive in a different
order from the `AR` requests. However, all beats for one burst must remain in
order, and transactions with the same ID must remain ordered.

## 8. `rtl/axi_slave_mem.sv`

The slave is a memory-backed AXI target. It should be simple enough to debug but
real enough to exercise protocol behavior.

### Memory Model

Use byte-addressable storage:

```systemverilog
logic [7:0] mem [0:MEM_BYTES-1];
```

Where:

```systemverilog
localparam int STRB_WIDTH = DATA_WIDTH / 8;
localparam int MEM_BYTES  = MEM_DEPTH * STRB_WIDTH;
```

Byte-addressable memory makes `WSTRB` behavior straightforward and avoids
awkward read-modify-write logic.

### Write Address Handling

The slave must accept write addresses on `AW`.

Recommended first version:

- maintain an AW metadata FIFO
- push one entry on `AWVALID && AWREADY`
- entry contains ID, address, length, size, burst type, and beat counter
- deassert `AWREADY` when the FIFO is full

### Write Data Handling

The slave must consume write data beats on `W`.

Recommended first version:

- pop or reference the oldest AW entry when writing data
- accept W beats only when there is at least one AW entry available
- write each byte lane only when the corresponding `WSTRB` bit is `1`
- increment the burst address after each accepted beat
- require `WLAST` to match the final expected beat
- generate `SLVERR` if `WLAST` is early or late

Because AXI4 removed `WID`, do not attempt to match W data by ID. W data belongs
to the next write transaction in the accepted AW ordering.

### Write Response Handling

After the final W beat of a write burst:

- enqueue a B response containing the original `AWID`
- set `BRESP` to `OKAY` for successful writes
- set `BRESP` to `SLVERR` or `DECERR` for invalid access
- drive `BVALID` until `BVALID && BREADY`

Out-of-order write responses:

- AXI permits write responses for different IDs to be reordered.
- Same-ID write responses must stay ordered.
- Since W data is not interleaved in AXI4, start with in-order B responses.
- Add optional out-of-order B scheduling only after the in-order path works.

### Read Address Handling

The slave must accept read addresses on `AR`.

Recommended first version:

- maintain an AR metadata FIFO or pending read table
- push one entry on `ARVALID && ARREADY`
- entry contains ID, address, length, size, burst type, beat counter, and error
  status
- deassert `ARREADY` when no pending read slot is available

### Read Data Handling

For each pending read:

- drive `RID` from the stored `ARID`
- drive `RDATA` from memory
- drive `RRESP` according to access status
- drive `RLAST` only on the final beat
- hold all R payload stable while `RVALID && !RREADY`
- increment the stored beat counter only after `RVALID && RREADY`

Out-of-order read responses:

- if `SUPPORT_OOO = 0`, always service pending reads in acceptance order
- if `SUPPORT_OOO = 1`, the scheduler may choose any pending read whose ID does
  not violate same-ID ordering
- never reorder transactions with the same `ARID`

## 9. Out-of-Order Design

AXI4 supports multiple outstanding transactions using IDs. Out-of-order support
means responses for different IDs can complete in a different order from request
acceptance.

Important distinction:

- Read data has `RID`, so read responses can naturally be associated with IDs.
- Write responses have `BID`, but write data has no `WID` in AXI4.
- Same-ID ordering must always be preserved.
- Different-ID ordering may be relaxed.

### Recommended Staged Implementation

Implement out-of-order support in stages:

1. Single outstanding:
   - one active write
   - one active read
   - no reordering

2. Multiple outstanding, in-order completion:
   - command queues support several transactions
   - responses complete in acceptance order
   - IDs are still returned correctly

3. Read out-of-order across IDs:
   - pending read table has multiple entries
   - scheduler chooses a ready entry with no same-ID ordering violation
   - `RID` identifies the returned transaction

4. Optional write response out-of-order:
   - B response queue can schedule different IDs out of order
   - same-ID B ordering is preserved
   - keep W data consumption in AW acceptance order

### Same-ID Ordering Rule

Use one of these implementation methods:

- Per-ID queues: keep pending transactions in separate queues by ID.
- Global table plus age check: each pending entry stores an acceptance sequence
  number, and the scheduler only selects the oldest entry for each ID.

Recommended for clarity: use the global table plus age check.

## 10. Handshake Rules To Follow Everywhere

These rules are the most important part of the design:

- A source must not wait for `READY` before asserting `VALID`.
- Once `VALID` is asserted, keep it asserted until a handshake occurs.
- Payload must remain stable while `VALID = 1` and `READY = 0`.
- A transfer occurs only when `VALID && READY` is true on a clock edge.
- Do not create a combinational dependency from input `READY` to output `VALID`.
- It is acceptable for a destination to wait for `VALID` before asserting
  `READY`, but avoid unnecessary throughput loss.

Apply this to all channels:

- `AWVALID/AWREADY`
- `WVALID/WREADY`
- `BVALID/BREADY`
- `ARVALID/ARREADY`
- `RVALID/RREADY`

## 11. Burst Handling

AXI burst fields:

- `AxLEN` is beats minus one.
- total beats = `AxLEN + 1`.
- `AxSIZE` is bytes per beat encoded as `2 ** AxSIZE`.
- `AxBURST` selects address behavior.

Version 1 burst support:

- fully support `INCR`
- optionally accept `FIXED`
- return `SLVERR` for `WRAP` until implemented

For `INCR` bursts:

```text
beat_addr[N+1] = beat_addr[N] + bytes_per_beat
```

For `FIXED` bursts:

```text
beat_addr[N+1] = beat_addr[N]
```

For `WRAP` bursts:

```text
wrap_size     = bytes_per_beat * burst_beats
wrap_boundary = floor(start_addr / wrap_size) * wrap_size
next_addr     = start_addr + bytes_per_beat
if next_addr crosses wrap_boundary + wrap_size:
  next_addr = wrap_boundary
```

Add `WRAP` only after `INCR` is passing tests.

## 12. Error Handling

Return useful responses instead of silently doing the wrong thing.

Use `OKAY` when:

- burst type is supported
- address range is valid
- size is supported
- `WLAST`/`RLAST` behavior is correct

Use `SLVERR` when:

- burst type is recognized but unsupported in this slave version
- `WLAST` is early or late
- access size is unsupported
- transaction violates a slave-local rule

Use `DECERR` when:

- address is outside the implemented memory map

For invalid writes:

- consume all W beats to keep the bus from hanging
- return an error response on B
- do not modify memory for invalid byte lanes or invalid addresses

For invalid reads:

- return all requested beats
- drive `RRESP` with the error response
- drive deterministic data, such as zero, for invalid addresses
- still assert `RLAST` on the final beat

## 13. Reset Behavior

Use active-low reset `ARESETn`.

On reset:

- clear every `VALID` output
- clear all FIFOs, pending tables, counters, and response queues
- clear outstanding slot valid bits
- drive ready outputs to a known value
- do not rely on memory contents unless the testbench initializes them

After reset:

- no stale response may appear
- no old transaction may remain pending
- first accepted transaction must behave normally

## 14. Basic Smoke Test

Create `sim/tb_axi_basic.sv` after the RTL skeleton exists.

The smoke test should:

- instantiate `axi_if`
- instantiate `axi_master`
- instantiate `axi_slave_mem`
- generate clock and reset
- drive the master's command-side ports
- compare read data against expected memory contents

Minimum scenarios:

1. Single-beat write.
2. Single-beat readback.
3. Four-beat `INCR` burst write and readback.
4. Partial byte write using `WSTRB`.
5. Backpressure on `AWREADY`, `WREADY`, `BREADY`, `ARREADY`, and `RREADY`.
6. Two outstanding reads with different IDs.
7. Same-ID reads complete in order.
8. Different-ID reads may complete out of order when `SUPPORT_OOO = 1`.
9. Invalid address read returns `DECERR`.
10. Reset during idle.
11. Reset during active transfer.

## 15. Suggested Build Order

Use this order to avoid debugging too many moving parts at once:

1. Write `axi_pkg.sv`.
2. Write `axi_if.sv`.
3. Write a slave that accepts one write and one read at a time.
4. Write a simple master that sends one write and one read at a time.
5. Add `axi_top.sv`.
6. Add a smoke test for single-beat write/readback.
7. Add `INCR` burst support.
8. Add `WSTRB` partial writes.
9. Add multiple outstanding read/write tracking.
10. Add read out-of-order support across different IDs.
11. Add optional write response reordering.
12. Add error responses and reset-during-transfer tests.

Do not start with full out-of-order behavior. First make one clean transaction
work, then scale it.

## 16. Common Mistakes To Avoid

- Treating `AxLEN` as the number of beats instead of beats minus one.
- Forgetting that `AxSIZE` is an encoded value.
- Asserting `WLAST` or `RLAST` one beat early or late.
- Letting payload change while `VALID` is high and `READY` is low.
- Creating combinational `READY` to `VALID` loops.
- Assuming `AW` and `W` always handshake in the same cycle.
- Assuming read and write channels block each other.
- Implementing `WID`; AXI4 does not use it.
- Reordering transactions with the same ID.
- Ignoring `WSTRB` and overwriting all bytes.
- Dropping error transactions instead of completing them with an error response.
- Forgetting to free outstanding slots after `B` or final `R` handshakes.
- Forgetting that `B` has one response per write burst, not one response per
  write data beat.
- Forgetting that `R` has one response per read beat.

## 17. Acceptance Criteria For Version 1

The implementation is complete enough for the first design milestone when:

- all five AXI channels are present
- read and write single-beat transfers work
- `INCR` burst read and write transfers work
- `WSTRB` partial writes work
- `BID` and `RID` match the original transaction IDs
- `WLAST` and `RLAST` are correct
- multiple outstanding transactions can be tracked
- same-ID ordering is preserved
- different-ID read responses can complete out of order when enabled
- invalid addresses return an error response
- reset clears all active protocol state
- the basic smoke test passes without deadlock

## 18. What To Defer Until Later

These features are useful but should not be in the first implementation unless
the basic design is already stable:

- UVM verification environment
- AXI4-Lite adapter
- AXI-Stream support
- ACE or coherency signals
- full `AxCACHE`, `AxPROT`, `AxQOS`, `AxREGION`, and user signal support
- interconnect with multiple masters or slaves
- clock domain crossing
- register slices
- formal property suite
- performance optimization

## 19. Final Design Reminder

AXI4 is not difficult because any one channel is complicated. It is difficult
because all five channels are independent and the ordering rules must still be
preserved. Build the RTL so every channel handshake is obvious in the waveform,
then add burst length, IDs, and out-of-order behavior one layer at a time.
