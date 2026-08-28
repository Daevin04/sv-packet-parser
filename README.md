# Low-latency UDP packet parser (SystemVerilog)

A cut-through Ethernet/IPv4/UDP frame parser that filters a fixed-format
application message and emits a response, with latency measured in hardware.

**It commits to the filter decision at byte 45 of the frame** — the last byte the
decision depends on — rather than waiting for end-of-frame. On an 8-bit datapath
at the 125 MHz GMII byte clock, a 64-byte minimum Ethernet frame takes 64 cycles
to arrive. This design responds at cycle 46, and that number does not change for
a 1518-byte frame. There is a regression test that fails if it ever does.

```
      byte 0                    byte 45                        byte 63
        |                          |                              |
  ------+--------------------------+------------------------------+---->
        SOF                     decision                        EOF
                                   |
                                   +--> response SOF at cycle 46
```

## Measured results

| Metric | Value |
|---|---|
| Decision latency | 46 cycles, SOF to response SOF |
| At 125 MHz (GMII byte clock) | 368 ns |
| Frame-length dependence | none — verified by test |
| Frame buffering | none — no packet memory in the design |

Timing closure and resource utilisation: see [`docs/latency.md`](docs/latency.md).
*(Simulation numbers are measured and reproducible from this repo. Synthesis
numbers require the vendor toolchain and are recorded separately.)*

## Design

Four modules, about 300 lines of SystemVerilog:

| File | Role |
|---|---|
| `rtl/pkt_pkg.sv` | Frame layout constants, sized to the byte counter's width |
| `rtl/frame_parse.sv` | Streaming parser: offset tracking, field capture, match |
| `rtl/resp_gen.sv` | Fixed response emission with overrun detection |
| `rtl/parser_top.sv` | Integration plus the hardware latency counter |

Three decisions drive the latency:

**No frame buffering.** Bytes are parsed as they arrive. There is no packet RAM,
so latency is independent of frame length and the design has no memory to size.

**Header checks accumulate incrementally.** Each header field is compared the
cycle its last byte lands, and the result is registered. At the decision byte the
combinational cone is one 16-bit comparator AND four already-registered bits —
not a four-field comparison that would set the critical path.

**A constant response.** The reply is a compile-time ROM, so the emit path has no
lookup, no arithmetic, and no arbitration. A match arriving while a response is
in flight is counted as an overrun rather than buffered — adding a queue would
add its latency to the one path this design exists to keep short.

## Verification

`tb/test_parser.py`, cocotb driving Verilator:

| Test | What it proves |
|---|---|
| `test_matching_frame` | The happy path matches and latency is exactly 46 cycles |
| `test_latency_is_independent_of_frame_length` | Cut-through: 64-byte and 1500-byte frames respond identically |
| `test_rejects_non_matching_frames` | Each of the five filter conditions can independently reject |
| `test_back_to_back_frames` | No state leaks between frames — the case that breaks parsers that never clear accumulated verdicts |
| `test_price_capture` | Observability path reports the payload field correctly |
| `test_constrained_random` | 200 randomised frames against an independent Python model, with coverage bins and a closure assertion |

The reference model in the random test is written from the specification, not
from the RTL, so agreement between them means something. Coverage bins are
asserted non-empty — a run that never exercised a reject path would fail rather
than report a misleading pass.

Lint runs with `-Wall` and warnings are failures. In RTL, a width mismatch or an
inferred latch is a bug that has not happened yet.

## Running it

```bash
# Everything, exactly as CI runs it
bash scripts/run_tests.sh

# Just the simulation
make -C tb

# With waveforms
make -C tb waves && gtkwave tb/dump.vcd
```

Requires Verilator 5.x, `make`, `g++`, and `cocotb>=1.9,<2.0`.

No toolchain locally? The container CI uses reproduces it:

```bash
docker run --rm -v "$PWD":/work -w /work python:3.12-slim \
    bash /work/scripts/docker_test.sh
```

## Scope, stated honestly

This is verified with cocotb and constrained-random stimulus, **not UVM** —
UVM requires a licensed simulator (VCS, Questa, Xcelium) and cannot run in free
CI. The verification concepts are the same: independent reference model,
randomised stimulus, functional coverage bins, coverage closure as a pass
condition. The methodology is not.

The design assumes IHL=5 (no IPv4 options) and a single fixed message layout.
Both assumptions are stated in `rtl/pkt_pkg.sv` and both are what make every
payload offset a compile-time constant.

## Next

- [ ] Synthesise for a Nexys 4 DDR / Arty A7 and record timing closure and utilisation
- [ ] Bring up against a real PHY and measure end-to-end wire latency
- [ ] Widen the datapath to 64-bit for 10G line rate
- [ ] SVA assertions on the streaming interface protocol
