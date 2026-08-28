"""Sensor telemetry configuration: sensor id at 42, channel at 46, sample at 48.

The engine is identical to the market-data instance. Only the parameters differ,
and the decision byte moves with them - 47 here rather than 45. That is the
whole claim of the parameterisation, so it gets its own test.
"""

import cocotb

from framelib import (build_frame, expected_latency, reset, send_frame,
                      start_clock, u16, u32)

PORT = 6000
SENSOR_ID = 0x00A1
CHANNEL = 7

F0_OFF, F1_OFF, CAP_OFF = 42, 46, 48
LATENCY = expected_latency(F0_OFF, F1_OFF)   # 48

# The market-data instance decides two bytes earlier. Asserting the difference
# is what proves the offsets are actually driving the hardware rather than being
# decorative parameters that the RTL ignores.
MARKET_LATENCY = expected_latency(42, 44)    # 46


def telemetry_frame(dst_port=PORT, sensor_id=SENSOR_ID, channel=CHANNEL,
                    sample=0x11223344, **kwargs):
    return build_frame(dst_port, {
        F0_OFF:  u16(sensor_id),
        F1_OFF:  u16(channel),
        CAP_OFF: u32(sample),
    }, **kwargs)


@cocotb.test()
async def test_matching_frame(dut):
    """The same engine, configured for telemetry, matches a telemetry frame."""
    await start_clock(dut)
    await reset(dut)

    await send_frame(dut, telemetry_frame())

    assert int(dut.match_count.value) == 1
    assert int(dut.latency_cycles.value) == LATENCY, (
        f"latency {int(dut.latency_cycles.value)}, expected {LATENCY}")


@cocotb.test()
async def test_decision_offset_tracks_configuration(dut):
    """The decision byte moved because the match field moved.

    Telemetry's second match field ends at byte 47 rather than 45, so this
    instance must be exactly two cycles slower than the market-data one. If the
    parameters were being ignored, both would report the same latency.
    """
    await start_clock(dut)
    await reset(dut)

    await send_frame(dut, telemetry_frame())
    measured = int(dut.latency_cycles.value)

    assert measured == LATENCY
    assert measured == MARKET_LATENCY + 2, (
        f"expected telemetry to decide 2 cycles later than market data "
        f"({MARKET_LATENCY} -> {LATENCY}), measured {measured}")


@cocotb.test()
async def test_rejects_non_matching_frames(dut):
    """Each condition rejects independently under the new field layout."""
    await start_clock(dut)
    await reset(dut)

    cases = {
        "wrong sensor":  dict(sensor_id=SENSOR_ID + 1),
        "wrong channel": dict(channel=CHANNEL + 1),
        "wrong port":    dict(dst_port=PORT + 1),
        "not IPv4":      dict(ethertype=0x0806),
        "not UDP":       dict(ip_proto=0x06),
    }

    for name, kwargs in cases.items():
        before = int(dut.match_count.value)
        await send_frame(dut, telemetry_frame(**kwargs))
        assert int(dut.match_count.value) == before, f"{name}: not rejected"


@cocotb.test()
async def test_rejects_a_market_data_frame(dut):
    """Cross-check: the telemetry instance must not accept the other config's
    traffic. Two engines on the same wire have to stay in their lanes."""
    await start_clock(dut)
    await reset(dut)

    market = build_frame(5000, {42: u16(0x0001), 44: u16(42), 46: u32(1)})
    await send_frame(dut, market)
    assert int(dut.match_count.value) == 0


@cocotb.test()
async def test_capture_field(dut):
    """Capture reads from byte 48 in this configuration, not byte 46."""
    await start_clock(dut)
    await reset(dut)

    await send_frame(dut, telemetry_frame(sample=0xCAFEF00D))
    assert int(dut.capture.value) == 0xCAFEF00D
