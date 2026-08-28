# Latency and resource results

Two kinds of number live here. Keep them separate — one is reproducible by
anyone who clones the repo, the other is not.

## Measured in simulation (reproducible)

Produced by `test_matching_frame` and read from the hardware latency counter in
`parser_top`, not estimated from a waveform by hand.

| Metric | Cycles | At 125 MHz |
|---|---|---|
| SOF to response SOF | 46 | 368 ns |
| Decision byte (byte 45) to response SOF | 1 | 8 ns |
| 64-byte frame | 46 | 368 ns |
| 1500-byte frame | 46 | 368 ns |

The last two rows are the cut-through claim. `test_latency_is_independent_of_frame_length`
asserts they are equal, so this table cannot silently go stale.

## Synthesis and timing closure (fill in after a build)

Requires Vivado. Record the real numbers here, including the failures — an Fmax
you did not reach is more informative than one you did.

| Metric | Value | Notes |
|---|---|---|
| Target device | | e.g. xc7a100tcsg324-1 (Nexys 4 DDR) |
| Target clock | 125 MHz | GMII byte clock |
| Worst negative slack (WNS) | | positive means closed |
| Fmax | | derived from WNS |
| LUTs | | |
| Flip-flops | | |
| BRAM | | expected: 0 — the design buffers no frames |
| Critical path | | which comparator, and between which registers |

To generate:

```tcl
read_verilog -sv rtl/pkt_pkg.sv rtl/frame_parse.sv rtl/resp_gen.sv rtl/parser_top.sv
synth_design -top parser_top -part xc7a100tcsg324-1
create_clock -period 8.0 -name clk [get_ports clk]
opt_design; place_design; route_design
report_timing_summary -file docs/timing.rpt
report_utilization  -file docs/utilization.rpt
```

## Wire-level measurement (fill in after board bring-up)

The number that actually counts, and the one nobody else's coursework has.
Measure from the last bit of the incoming frame on the wire to the first bit of
the response, with a scope or hardware timestamping — not from simulation.

| Metric | Value | Method |
|---|---|---|
| Wire-to-wire latency | | |
| PHY contribution | | subtract to isolate the fabric |
| Jitter / determinism | | min / max / spread over N frames |
