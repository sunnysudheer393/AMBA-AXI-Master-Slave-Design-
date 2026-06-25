---
name: amba-axi-design-decisions
description: Decisions for the AMBA_AXI design session — scope, version, OoO style, and top-level topology.
metadata:
  type: project
---

AMBA_AXI design session (2026-06-23), decided with the user before laying out the plan:

- **Scope**: Design only — RTL files. No testbench in this session. Verification (UVM or SV) is a later step.
- **AXI version**: AXI4. No WID, no write interleaving, no locked transactions. INCR bursts up to 256 beats.
- **Out-of-order style**: Multi-ID. Master issues multiple AWID/ARID values; slave reorders responses and returns them tagged with RID/BID.
- **Top-level style**: SystemVerilog interface + module top, matching the user's existing `AHB_to_APB` project style (`*.svh` interface, `*.sv` module).
- **Variable-length**: parameterized data width and burst length.

Related: [[user-coding-style]] (when written).

**Why:** Avoid re-asking these four decisions on the next session. The choices drive every file in the design — if any of them change, the file list and the channel payload change with them.

**How to apply:** Re-read this memory at the start of any follow-up session on AMBA_AXI. If the user wants to add a testbench, switch to AXI3, or change OoO model, surface the change and confirm before re-using this plan.
