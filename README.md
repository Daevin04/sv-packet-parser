# Line-rate stream filter (SystemVerilog)

[![lint and simulate](https://github.com/Daevin04/sv-packet-parser/actions/workflows/ci.yml/badge.svg)](https://github.com/Daevin04/sv-packet-parser/actions/workflows/ci.yml)

A cut-through Ethernet/IPv4/UDP filter that inspects a packet **as it arrives**,
commits to a keep-or-drop decision at a fixed, configurable byte, and never
buffers the frame.

Traffic that doesn't match is discarded in the fabric. It never reaches the
host — no DMA, no interrupt, no cache pollution, and so no jitter injected into
whatever is downstream.

```
      byte 0                    byte 45                        byte 63
        |                          |                              |
  ------+--------------------------+------------------------------+---->
        SOF                     decision                        EOF
                                   |
                                   +--> response SOF at cycle 46
```

The decision at byte 45 happens while bytes 46–63 of a 64-byte minimum frame are
still arriving on the wire. It is identical for a 1518-byte frame, because
nothing past the decision byte is consulted — and there is a regression test that
fails if that ever stops being true.

## Measured

| Metric | Value |
|---|---|
| Decision latency (market config) | 46 cycles, SOF → response SOF |
| At 125 MHz GMII byte clock | 368 ns |
| Frame-length dependence | none — asserted by test |
| Frame buffering | none — no packet memory in the design |

Read from a hardware counter in `parser_top`, not estimated from a waveform.
Synthesis and board results: [`docs/latency.md`](docs/latency.md).

## One engine, many protocols

The Ethernet/IPv4/UDP checks are fixed, because those headers are fixed. What
the payload *means* is not — so the match fields are parameters. Two example
configurations ship in `rtl/examples/`, differing only in parameterisation:

| Config | Port | Match fields | Decides at | Latency |
|---|---|---|---|---|
| `market_filter_top` | 5000 | message type @42, symbol @44 | byte 45 | 46 cycles |
| `telemetry_filter_top` | 6000 | sensor id @42, channel @46 | byte 47 | 48 cycles |

**The decision byte is elaborated, not hard-coded.** `decision_offset()` computes
it from the configured field offsets, so moving a match field moves the decision
automatically. `test_decision_offset_tracks_configuration` asserts the telemetry
instance is exactly two cycles slower than the market one — which is what proves
the parameters drive the hardware rather than decorating it.

That generality is the point: the same primitive is what exchange feed
pre-filters, SmartNIC packet classifiers, and physics-experiment triggers all
are. The LHC Level-1 trigger runs this pattern at 40 MHz inside a 4 µs budget,
rejecting 99.7% of events, because storing everything is impossible.

## Design

| File | Role |
|---|---|
| `rtl/pkt_pkg.sv` | Fixed frame geometry; `decision_offset()` |
| `rtl/frame_parse.sv` | Streaming parser: offset tracking, field capture, match |
| `rtl/resp_gen.sv` | Fixed response emission with overrun detection |
| `rtl/parser_top.sv` | Integration plus the hardware latency counter |
| `rtl/examples/*.sv` | Two configurations of the same engine |

Three decisions drive the latency:

**No frame buffering.** Bytes are parsed as they arrive. No packet RAM, so
latency is independent of frame length and there is no memory to size.

**Verdicts accumulate incrementally.** Each header field is compared the cycle
its last byte lands, and the result is registered. At the decision byte the
combinational cone is one 16-bit comparator ANDed with already-registered bits —
not a five-field comparison that would set the critical path.

**A constant response.** The reply is a compile-time ROM: no lookup, no
arithmetic, no arbitration on the emit path. A match arriving while a response is
in flight is counted as an overrun rather than buffered — a queue would add its
latency to the one path this design exists to keep short.

## Verification

cocotb driving Verilator, 11 tests across both configurations.

| Test | Proves |
|---|---|
| `test_matching_frame` | Happy path, exact expected latency |
| `test_latency_is_independent_of_frame_length` | Cut-through actually holds, 64 vs 1500 bytes |
| `test_rejects_non_matching_frames` | Each of five conditions rejects independently |
| `test_back_to_back_frames` | No state leaks between frames |
| `test_decision_offset_tracks_configuration` | Parameters really drive the decision point |
| `test_rejects_a_market_data_frame` | Configurations stay in their lanes |
| `test_capture_field` | Observability path reads the right offset |
| `test_constrained_random` | 200 random frames vs. an independent model, coverage closure |

The reference model is written from the specification, not the RTL, so agreement
between them means something. Coverage bins are asserted non-empty — a run that
never exercised a reject path fails rather than reporting a misleading pass.

Lint runs `-Wall` with warnings as errors, per configuration, since parameters
change what elaborates.

## Running it

```bash
bash scripts/run_tests.sh                # everything, exactly as CI runs it

make -C tb CONFIG=market                 # one configuration
make -C tb CONFIG=telemetry
make -C tb waves CONFIG=market && gtkwave tb/dump.vcd
```

Requires Verilator 5.x, `make`, `g++`, `cocotb>=1.9,<2.0`. No toolchain locally?

```bash
docker run --rm -v "$PWD":/work -w /work python:3.12-slim \
    bash /work/scripts/docker_test.sh
```

## Scope, stated honestly

Verified with cocotb and constrained-random stimulus, **not UVM** — UVM requires
a licensed simulator (VCS, Questa, Xcelium) and cannot run in free CI. The
concepts are the same: independent reference model, randomised stimulus,
coverage bins, closure as a pass condition. The methodology is not.

The design assumes IHL=5 (no IPv4 options) and two 16-bit match fields per
configuration. Both assumptions are stated in the RTL and both are what keep
every payload offset a compile-time constant.

Source IP is not checked, so this enforces feed provenance by port and payload
only — it is not a defence against a determined spoofer, and shouldn't be
described as one.

## Next

- [ ] Synthesise for Nexys 4 DDR / Arty A7; record timing closure and utilisation
- [ ] Bring up against a real PHY and measure wire-to-wire latency with a scope
- [ ] Widen the datapath to 64-bit for 10G line rate
- [ ] SVA assertions on the streaming interface protocol
