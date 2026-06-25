# AMBA AXI4 Protocol Implementation Plan

## 1. Overview
This document outlines the architecture and step-by-step implementation plan for a parameterized AMBA AXI4 Master and Slave in SystemVerilog. The design focuses on high throughput, supporting variable data lengths, and enabling Out-of-Order (OoO) transaction completion.

---

## 2. Key AXI4 Protocol Specifications to Enforce
Based on the ARM AXI4 Specification, the following critical rules must dictate the RTL design:
* **No Write Data Interleaving:** The `WID` signal is removed in AXI4. Write data must be sent in the exact order of the issued `AW` (Write Address) transactions.
* **Out-of-Order (OoO) Scope:** OoO completion is supported *only* for Read Data (`RID`) and Write Responses (`BID`).
* **Burst Lengths:** Support `INCR` bursts up to 256 transfers (AXI4 extension) and `WRAP` bursts up to 16 transfers.
* **4KB Boundary Rule:** A single burst must never cross a 4KB address boundary.
* **Handshake Rules:** A source must *never* wait for `READY` to assert `VALID`. Once `VALID` is high, the payload (`ADDR`, `DATA`, etc.) must remain absolutely stable until `READY` is also high.

---

## 3. Chosen Architecture: Decoupled FIFO Approach
To support AXI's native high-performance capabilities and OoO execution, the **Decoupled FIFO Architecture** is selected over a monolithic FSM. 
* Each of the 5 channels (AW, W, B, AR, R) operates largely independently.
* Transactions are tracked using tag-indexed arrays (Scoreboards/Reorder Buffers).
* FIFOs bridge the gap between bus interfaces and internal memory/logic, preventing head-of-line blocking.

---

## 4. Step-by-Step Implementation Plan

### Step 1: SystemVerilog Interface Definition
Create a unified, parameterized interface to connect the Master and Slave.

* **Parameters:**
  * `ADDR_WIDTH` (e.g., 32, 64)
  * `DATA_WIDTH` (e.g., 32, 64, 128)
  * `ID_WIDTH` (e.g., 4, 8)
* **Signal Grouping:**
  * **AW Channel:** `AWID`, `AWADDR`, `AWLEN`, `AWSIZE`, `AWBURST`, `AWVALID`, `AWREADY` (plus QOS, PROT, REGION)
  * **W Channel:** `WDATA`, `WSTRB`, `WLAST`, `WVALID`, `WREADY`
  * **B Channel:** `BID`, `BRESP`, `BVALID`, `BREADY`
  * **AR Channel:** `ARID`, `ARADDR`, `ARLEN`, `ARSIZE`, `ARBURST`, `ARVALID`, `ARREADY`
  * **R Channel:** `RID`, `RDATA`, `RRESP`, `RLAST`, `RVALID`, `RREADY`
* **Modports:** Define `master` (outputs VALID, inputs READY) and `slave` (inputs VALID, outputs READY).

### Step 2: Master Architecture Design
Divide the Master RTL into concurrent threads:

1. **Write Command Issue:**
   * Accepts internal write requests and pushes them into an `AW` Queue.
   * Drives the `AW` bus signals.
   * Allocates an entry in the **Outstanding Transaction Tracker** using the generated `AWID`.
2. **Write Data Issue:**
   * Sequences data onto the `W` channel. 
   * Ensures `WLAST` is asserted precisely on the final beat of the `AWLEN` count.
3. **Read Command Issue:**
   * Drives the `AR` bus signals.
   * Allocates an entry in the **Outstanding Transaction Tracker** using the generated `ARID`.
4. **Out-of-Order (OoO) Tracker:**
   * Monitors the `B` channel for `BID` and the `R` channel for `RID`.
   * Routes returning data/responses to the correct internal requesting thread based on the ID.
   * Deallocates the tracker entry once `RLAST` or `BVALID` completes the transaction.

### Step 3: Slave Architecture Design
The Slave must quickly absorb requests and decouple the bus timing from internal memory latency.

1. **Address Decoders & Request Queues:**
   * Immediately assert `AWREADY` and `ARREADY` if internal `AW_FIFO` and `AR_FIFO` have space.
   * Do *not* wait for `WVALID` to assert `AWREADY` (prevents circular deadlocks).
2. **Write Data Receiver:**
   * Looks at the head of the `AW_FIFO` to know how much data to expect.
   * Absorbs `WDATA` and writes it sequentially to the backing memory.
   * Upon seeing `WLAST` and completing the memory write, pushes a response token to the `B_FIFO` with the corresponding `AWID` (now `BID`).
3. **Out-of-Order Read Scheduler:**
   * Pops addresses from the `AR_FIFO`.
   * Interfaces with internal memory. If memory latency varies (e.g., simulating cache hits/misses), earlier requests might finish later.
   * Pushes retrieved data into the `R_FIFO` along with the matching `RID`. The independent `R` channel logic pops this FIFO and drives the bus, inherently supporting OoO data return.

### Step 4: Address Burst Calculation Subsystem
Implement a SystemVerilog `function` or internal ALU to compute sequential addresses for bursts.
* **INCR:** `Next_Addr = Current_Addr + Number_of_Bytes_Per_Transfer`
* **WRAP:** Implement modulo wrapping logic based on `AWSIZE` and `AWLEN`.
* **4KB Guard:** Add combinational logic to check if `Start_Addr + (AWLEN * AWSIZE)` crosses a 4096-byte boundary. If it does, generate an error or split the transaction internally.

---

## 5. Next Steps
1. Draft the `axi_if.sv` interface file.
2. Draft the `axi_master.sv` module, starting with the Write/Read issue logic.
3. Draft the `axi_slave.sv` module, instantiating the required FIFOs.
4. Wire them together in a top-level wrapper `axi_top.sv`.