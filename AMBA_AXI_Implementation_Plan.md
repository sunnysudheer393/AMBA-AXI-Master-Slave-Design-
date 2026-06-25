# AMBA AXI4 Protocol — Master / Slave Design Plan

## 1. Context

You want an AMBA AXI4 master + slave written in SystemVerilog that supports **variable-length bursts** and **out-of-order (multi-ID) completion**. The slave must be able to reorder responses and tag them with the correct `RID` / `BID` so the master can match them — exactly as defined in Chapter A5 and Chapter A6 of `AXI4_specification.pdf`.

The session decisions captured in `memory/amba-axi-design-decisions.md` are:

- **Scope:** RTL design only. No testbench this session. Verification (UVM or SV) is a follow-up.
- **AXI version:** AXI4. No `WID`, no write interleaving, no locked transactions. `INCR` bursts up to 256 beats.
- **OoO style:** Multi-ID. Master issues transactions with multiple `AWID` / `ARID` values; slave reorders responses and returns them tagged with `RID` / `BID`.
- **Top-level style:** SystemVerilog interface + module top, matching the user's existing `AHB_to_APB` project style (`*.svh` interface, `*.sv` module).
- **Variable-length:** parameterized data width and burst length.

The intended outcome: a clean, parameterized RTL set that you can simulate, read at the waveform, and later wrap in a UVM environment. The plan below is structured so each step produces a self-contained, verifiable artifact — once you finish, you have a working AXI4 fabric (master + slave + top) that exercises both transfers, all three burst types, and OoO.

---

## 2. Alternative implementation styles (and why this one is chosen)

Knowing the alternatives lets you push back if you want a different flavor:

| # | Style | Pros | Cons | Used here? |
|---|-------|------|------|-----------|
| 1 | **Single-state FSM per channel** (chosen) | Most readable; mirrors ARM/Xilinx reference IP; every VALID/READY rule from §A3.2.2 is expressed directly; OoO added by tagging in-flight bursts with their ID | Slightly more code than #2 | ✅ |
| 2 | One big master/slave FSM | Compact | Becomes unreadable once OoO + bursts are added | ❌ |
| 3 | Channel-handshake modules + thin wrappers | Good for IP reuse; each channel is a reusable `axi_*_chan.sv` with VALID/READY-only handshake | Overkill for a learning RTL | ❌ |
| 4 | Transaction-queue based (FIFOs per ID + arbiters) | How real high-performance interconnects are written | Adds significant infrastructure (arbiters, schedulers) not needed for correctness focus | ❌ |
| 5 | Register-slice pipelined (AXI4-Lite / RegSlice) | Useful in synthesis for timing closure | Not useful as a learning baseline | ❌ |

**Why #1 is right for this project:** the spec is explicit that every channel has its own handshake pair (§A3.2.2 Table A3-1), and OoO is achieved by ID-tagging — not by introducing an arbiter. Writing each channel as its own FSM maps 1-to-1 onto the spec, so the RTL reads like the documentation.

---

## 3. Architecture overview

```
                     AXI4 interface (axi_if.svh)
              ┌────────────────────────────────────────────┐
              │  AW*, W*,  B*   (master → slave, slave ack) │
              │  AR*, R*       (master → slave, slave data) │
              └────────┬──────────────────────────┬────────┘
                       │                          │
              ┌────────▼─────────┐       ┌────────▼─────────┐
              │  axi_master.sv   │       │  axi_slave.sv    │
              │  AW FSM          │       │  AW FSM          │
              │  W  FSM (beat    │       │  W  FSM (writes  │
              │   counter, WLAST)│       │   into RAM)      │
              │  AR FSM          │       │  AR FSM          │
              │  R  FSM          │       │  R  FSM (reads   │
              │  B  FSM          │       │   from RAM, OoO) │
              │  ID pool         │       │  ID reorder buf  │
              └──────────────────┘       └──────────────────┘
                       │                          │
                       └──────┬───────────────────┘
                              ▼
                       axi_top.sv
                       (instantiates master + slave, hooks
                        5 channels, internal memory model)
```

The slave is a **memory-mapped RAM model** with configurable depth, so `axi_top` is a self-contained system you can drop into a TB later without external memory.

---

## 4. Parameters (all in `axi_pkg.sv`)

| Parameter      | Default | Meaning |
|----------------|---------|---------|
| `ADDR_W`       | 32      | Address bus width |
| `DATA_W`       | 64      | Data bus width (8 / 16 / 32 / 64 / 128 / 256 / 512 / 1024 per §A2.3) |
| `ID_W`         | 4       | AXI ID width (master-side, 1–8 per §A5.4) |
| `LEN_W`        | 8       | Burst length field width (8 bits → up to 256 beats in AXI4) |
| `SIZE_W`       | 3       | Burst size field width |
| `BURST_W`      | 2       | Burst type field width |
| `RESP_W`       | 2       | Response field width |
| `MEM_DEPTH`    | 1024    | Slave RAM depth in `DATA_W`-sized words |
| `OUTSTANDING`  | 8       | Max outstanding transactions per direction the master can hold |

`STRB_W = DATA_W / 8` is derived, not parameterizable.

---

## 5. File layout (mirrors AHB_to_APB style)

```
AMBA_AXI/
├── axi_pkg.sv            # parameters + typedefs + enums (FIXED / INCR / WRAP, OKAY / EXOKAY / SLVERR / DECERR)
├── axi_if.svh            # 5-channel SystemVerilog interface (modports: master view, slave view)
├── axi_master.sv         # master FSM (AW, W, AR, R, B + ID pool + beat counter + transaction generator)
├── axi_slave.sv          # slave FSM + memory model + OoO reorder buffer (RID/BID tagged)
├── axi_top.sv            # instantiates master + slave + ties 5 channels + clock/reset gen
├── README.md             # parameter table + waveform cheat-sheet
└── AMBA_AXI_Implementation_Plan.md   # this file
```

No testbench this session — that comes in a follow-up session for UVM/SV verification.

---

## 6. Detailed step-by-step implementation

### Step 1 — `axi_pkg.sv` (types and constants)

Define the parameter table above. Define the typedefs:

- `typedef logic [ID_W-1:0]   id_t;`
- `typedef logic [ADDR_W-1:0] addr_t;`
- `typedef logic [DATA_W-1:0] data_t;`
- Burst-type enum: `typedef enum logic [1:0] {BURST_FIXED=2'b00, BURST_INCR=2'b01, BURST_WRAP=2'b10} burst_t;`
- Response enum: `typedef enum logic [1:0] {RESP_OKAY=2'b00, RESP_EXOKAY=2'b01, RESP_SLVERR=2'b10, RESP_DECERR=2'b11} resp_t;`

**Why first:** every later file `imports axi_pkg::*`, so types must be locked down before any RTL is written. Changing a width later means touching every file.

### Step 2 — `axi_if.svh` (the five-channel interface)

Mirror the AHB_to_APB style — `interface axi_if(); … endinterface`, with **modports** for `master` and `slave` views. Group signals per §A2 tables:

**Write address channel** (`AW*`) — master drives, slave accepts:
- `AWID[ID_W-1:0]`           — write address ID
- `AWADDR[ADDR_W-1:0]`       — first-transfer address
- `AWLEN[LEN_W-1:0]`         — burst length (AxLEN + 1 beats)
- `AWSIZE[SIZE_W-1:0]`       — bytes per transfer (1, 2, 4 … 128)
- `AWBURST[BURST_W-1:0]`     — burst type (FIXED / INCR / WRAP)
- `AWLOCK`                   — normal / exclusive access (1 bit, AXI4)
- `AWCACHE[3:0]`             — bufferable, modifiable, RA, WA
- `AWPROT[2:0]`              — privilege, security, instr/data
- `AWQOS[3:0]`               — QoS identifier
- `AWVALID`, `AWREADY`      — handshake

**Write data channel** (`W*`) — master drives, slave accepts:
- `WDATA[DATA_W-1:0]`, `WSTRB[STRB_W-1:0]`, `WLAST`, `WVALID`, `WREADY`

**Write response channel** (`B*`) — slave drives, master accepts:
- `BID[ID_W-1:0]`, `BRESP[RESP_W-1:0]`, `BVALID`, `BREADY`

**Read address channel** (`AR*`) — master drives, slave accepts:
- Same set as `AW*` but with `AR*` prefix and same widths.

**Read data channel** (`R*`) — slave drives, master accepts:
- `RID[ID_W-1:0]`, `RDATA[DATA_W-1:0]`, `RRESP[RESP_W-1:0]`, `RLAST`, `RVALID`, `RREADY`

**Global:**
- `ACLK` (rising-edge sampled), `ARESETn` (active-low, async asserted / sync deasserted).

**Critical rule to bake in from day one** — §A3.1.1: *"On master and slave interfaces there must be no combinatorial paths between input and output signals."* Every output must be registered. This is the #1 cause of AXI bugs in student designs, so it's enforced structurally (only `always_ff` blocks write outputs).

### Step 3 — `axi_master.sv` (write path — three FSMs)

#### 3a. AW FSM (write address slot ownership)
- States: `W_IDLE`, `W_ADDR`.
- On entry to `W_ADDR`: pull an ID from the ID pool, latch `AWADDR / AWSIZE / AWLEN / AWBURST / AWCACHE / AWPROT / AWLOCK` into a **write pending slot** keyed by `AWID`, and drive `AWVALID`.
- `W_ADDR → W_IDLE` on `AWVALID && AWREADY`. The ID stays parked in the slot until `BVALID` returns with the matching `BID`.

#### 3b. W FSM (data beats)
- States: `W_IDLE`, `W_DATA`, `W_DATA_LAST`.
- A `beat_counter[LEN_W-1:0]` starts at 0 when a write slot is "active" (its `AWID` matched an accepted `AWREADY`). On every `WVALID && WREADY` beat, increment.
- When `beat_counter == AWLEN` of the active slot, drive `WLAST=1` for that beat; otherwise `WLAST=0`.
- Per-beat address is computed by the master from `AWADDR + beat_counter * (1 << AWSIZE)` (per §A3.4.1 burst-address equations). The slave computes the same — both sides compute; only `WDATA` / `WSTRB` go on the bus.
- `WSTRB` for each beat must reflect only the valid byte lanes for that address — see §A3.4.3 "Narrow transfers" and Figure A3-8.

#### 3c. B FSM (accepts write responses)
- States: `W_IDLE`, `W_RESP`.
- Drive `BREADY=1` whenever the master is not actively doing something else (recommended default per §A3.2.2 "Write response channel").
- On `BVALID && BREADY`: capture `BRESP`, return the ID to the pool, mark the slot complete.

### Step 4 — `axi_master.sv` (read path — two FSMs)

#### 4a. AR FSM (drives `ARVALID`/`ARADDR`/`ARID`/etc.)
- Pulls an ID from the ID pool, marks a **read pending slot**, drives `ARVALID`.
- On `ARVALID && ARREADY`: the slot is parked, waiting for `RVALID` to return its data with `RID == slot.id`.

#### 4b. R FSM (accepts read data, watches `RLAST`)
- On every `RVALID && RREADY` beat: capture `RDATA`, `RRESP`, `RID`, `RLAST`.
- When `RLAST == 1`, return the ID to the pool and mark the slot complete.
- Reads with the same `ARID` *must* arrive in issue order (§A5.3.1 "Read ordering"). The slave enforces this — the master just relies on it. The slave reorders **only across IDs**, never within an ID.

#### 4c. Critical OoO enforcement (master side)
The ID pool must have a configurable size (default `OUTSTANDING=8`) and the master must never issue more than `2**ID_W` transactions with the same ID without waiting for a response (§A5.3 ordering rules). Add an `assert` that `in_flight_per_id[id] <= 1` per ID, so this constraint is checked in simulation.

### Step 5 — `axi_master.sv` (the transaction generator)

A small always block that drives *new* transactions into the FSMs. Configurable patterns via compile-time `\`define`s (not parameters):

| Mode | What it does |
|------|--------------|
| `MODE_FIXED` | Issue 4-beat fixed bursts |
| `MODE_INCR`  | Issue variable-length `INCR` bursts (1 to 256 beats) |
| `MODE_WRAP`  | Issue 4 / 8 / 16-beat wrap bursts |
| `MODE_O3`    | Issue transactions with **different** `ARID` / `AWID` values back-to-back so the slave must reorder |

This generator doesn't need to be sophisticated — it exists so that when you wire up a TB later, the master is already producing traffic. Without a TB, you'll just see the master sitting idle, which is fine for RTL review.

### Step 6 — `axi_slave.sv` (memory model)

A simple synchronous `DATA_W`-wide RAM:

- `logic [DATA_W-1:0] mem [0:MEM_DEPTH-1];`
- Byte-write enable via `WSTRB` so the slave honors narrow transfers (§A3.4.3 "Write strobes"). One `always_ff` per byte lane, gated by `WSTRB[i]`.
- Read port returns the addressed word combinationally into a registered `R_DATA` register (1-cycle latency — this is what makes the slave re-orderable across IDs).

### Step 7 — `axi_slave.sv` (the OoO reorder buffer) — the key design point

This is the heart of the AXI-side design. Per §A5 / §A6:

> Transactions with different ID values have no ordering restrictions. A slave can return them in any order, as long as responses within the same ID are ordered.

Concretely:

1. **Accept phase (per channel).** The slave's `AWREADY` and `ARREADY` default to HIGH so it can ingest bursts at full rate. Each accepted address is stored in a small slot keyed by its `AWID` / `ARID`:
   - `wr_slots[id] = { addr, len, size, burst, beats_remaining, in_flight }`
   - `rd_slots[id] = { addr, len, size, burst, beats_remaining, in_flight }`
2. **Service phase.** The slave's `R` FSM walks `rd_slots[*]` and picks **one** ID whose beats are ready (memory read latency is 1 cycle in this model). Drives `RVALID` with `RID = id`, `RDATA` from RAM at the computed address, `RLAST` on the last beat. **Different IDs can be picked in any order — that's the OoO.**
3. **Same-ID ordering.** Critical: the slave tracks `beats_remaining[id]`. For a given ID, it must not start a *new* burst until the previous burst with that ID has been fully returned (`beats_remaining[id] == 0`). This is what enforces the §A5.3.1 in-order-within-ID rule.
4. **Write response (B channel).** Same pattern: each accepted write ID gets parked in `wr_resp_pending[id]`. The slave's `B` FSM arbitrates between them in any order; the response is `BRESP = OKAY` (we don't model errors in this RTL unless you ask).

This gives you a real OoO slave without an arbiter-heavy design: it's just "track in-flight bursts per ID, return them in any order."

### Step 8 — `axi_top.sv` (instantiation + clock/reset)

```systemverilog
module axi_top
  import axi_pkg::*;
#(parameter int ADDR_W = 32, …)
(
  input  logic aclk,
  input  logic aresetn
);
  axi_if intf();

  axi_master #(.ADDR_W(ADDR_W), …) u_master (.aclk(aclk), .aresetn(aresetn), .s_axi(intf.master));
  axi_slave  #(.ADDR_W(ADDR_W), …) u_slave  (.aclk(aclk), .aresetn(aresetn), .s_axi(intf.slave ));
endmodule
```

Low-power signals (`CSYSREQ` / `CSYSACK` / `CACTIVE`) are optional per §A2.7 and left out for v1. An `initial` block pumps a few stimulus patterns through the master's transaction generator so you can eyeball waveforms without a TB.

### Step 9 — `README.md` (waveform cheat-sheet)

Document the expected waveform for a single 4-beat `INCR` write + 4-beat `INCR` read at default params. This becomes your reference for the verification session later.

### Step 10 — Self-review checklist (do this *before* declaring the design done)

- [ ] All five `VALID/READY` handshakes match §A3.2.2 (the easy one to forget is the write-response dependency on `AWVALID + AWREADY + WVALID + WLAST`).
- [ ] `WLAST` asserted only on the last beat; `RLAST` only on the last beat (§A3.4.1 / §A3.4.3).
- [ ] `BRESP` always `OKAY` for full burst, never per-beat (§A3.4.4).
- [ ] `RRESP` allowed per-beat; we return `OKAY` for every beat.
- [ ] `RID == ARID` of the address that produced this beat (§A5.3.1 "Read ordering").
- [ ] `BID == AWID` of the address that produced this response.
- [ ] Same-ID responses arrive in issue order; different-ID responses can arrive in any order (§A5.3.1 + Chapter A6 ordering model).
- [ ] No combinatorial paths between any input and any output on either interface (§A3.1.1 — register all outputs).
- [ ] During reset, only `AWVALID=0, WVALID=0, ARVALID=0, BVALID=0, RVALID=0` (§A3.1.2).
- [ ] `OUTSTANDING` per ID is ≤ 1 (covered by the assertion in Step 4).
- [ ] Wrapping bursts wrap correctly: address wraps when it reaches `Lower_Wrap_Boundary + (Size × Length)` (§A3.4.1).
- [ ] Narrow transfers: `WSTRB` correctly asserted only for valid byte lanes (§A3.4.3, Figure A3-8).
- [ ] Burst length never crosses a 4 KB boundary (the transaction generator should check this; assert it).
- [ ] `INCR` bursts with `AWLEN > 15` work (AXI4-only feature).

---

## 7. Conventions reused from your existing project

- `*.svh` for interfaces (matches `ahb_interface.svh`).
- `*.sv` for modules (matches `ahb_top.sv`).
- Modports for master/slave views inside one interface, parameterized through `axi_pkg`.
- One parameter block per module. No `defparam`, no global state.

---

## 8. Verification plan

### For this session (RTL compile-only)

Since you chose design-only, the "verification" for this session is that everything compiles cleanly with no warnings under `verilator` or your simulator of choice. Run something like:

```bash
verilator --binary -Wall -Wno-DECLFILENAME \
  --top-module axi_top \
  AMBA_AXI/axi_pkg.sv AMBA_AXI/axi_if.svh \
  AMBA_AXI/axi_master.sv AMBA_AXI/axi_slave.sv AMBA_AXI/axi_top.sv
```

…and fix any lint errors before declaring done. If you don't have `verilator` available, I can use whichever simulator you have — just tell me which.

### For the follow-up session (not in this one)

When you come back to verify:

- **First cut:** write a small SV testbench (like your `apb_tob_tb.svh`) that drives a known-good pattern, compares `axi_slave.mem[]` against expected values, and prints pass/fail. This is the fastest way to shake out the FSM bugs.
- **Then:** UVM. By then you'll have stable interfaces and can build a single `axi_if` virtual interface + an `axi_master_bfm` / `axi_slave_bfm` pair from the existing RTL. The reason to wait: building UVM TBs against an unstable RTL is the most expensive mistake in verification.

---

## 9. Out of scope (call out before adding later)

| Feature | Spec section | Why excluded |
|---------|--------------|--------------|
| AXI3-only: `WID`, write data interleaving, locked transactions | §A5.4, §A5.3.3, §A7.3 | AXI4-only design decision |
| Low-power signals (`CSYSREQ` / `CSYSACK` / `CACTIVE`) | §A2.7 | Optional, leave out for v1 |
| User signals (`AWUSER`, etc.) and region signals (`AWREGION`) | §A8 | Optional, leave out for v1 |
| Exclusive accesses | §A7.2 | v1 RTL only supports `AxLOCK = 0` (normal). Add the monitor for v2 if you want. |
| `DECERR` / `SLVERR` injection | §A3.4.4 | v1 always returns `OKAY`. The decode-error path is more interesting with an interconnect. |
| Interconnect | n/a | Not in this design. Adding one is a separate, larger task and isn't needed for the master/slave design itself. |
| QoS arbitration | §A8.1 | `AWQOS` / `ARQOS` are wired through but the slave doesn't *use* them. A real QoS scheme is an extension. |

---

## 10. Implementation order (recommended)

1. `axi_pkg.sv` — types, parameters, enums.
2. `axi_if.svh` — interface + modports.
3. `axi_master.sv` — start with write path (AW + W + B FSMs), then read path (AR + R FSMs), then ID pool + assertions, then transaction generator.
4. `axi_slave.sv` — RAM model first, then AW/W accept FSMs, then AR/R OoO reorder buffer, then B response FSM.
5. `axi_top.sv` — instantiate both, hook up interface, add clock/reset.
6. `README.md` — waveform cheat-sheet for the verification session.

Each step is small enough to be reviewed on its own before moving to the next.

---

## 11. Key spec references (for grep-ability during coding)

| Concept | Spec section |
|---------|--------------|
| 5 channels, VALID/READY handshakes | §A1.3.1, §A3.2 |
| Per-channel signal lists | §A2.2 – §A2.6 |
| Reset behavior (`*VALID=0`) | §A3.1.2 |
| Channel dependency rules (write response must wait for `AWVALID+AWREADY+WVALID+WLAST`) | §A3.3.1, §A3.3.2 |
| Burst length / size / type encodings | §A3.4.1 |
| Burst address equations (FIXED / INCR / WRAP) | §A3.4.1 |
| Write strobes, narrow transfers | §A3.4.3 |
| Response encoding (OKAY / EXOKAY / SLVERR / DECERR) | §A3.4.4 |
| Transaction ID purpose (OoO) | §A5.1, §A5.2 |
| Read / write ordering rules (same-ID in order, different-ID free) | §A5.3.1 – §A5.3.4 |
| AXI4 ordering model | Chapter A6 |