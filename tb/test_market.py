"""Market-data configuration: message type at 42, symbol at 44, price at 46.

Decision lands at byte 45, response at cycle 46.
"""

import random

import cocotb

from framelib import (build_frame, expected_latency, reset, send_frame,
                      start_clock, u16, u32)

PORT = 5000
MSG_TYPE = 0x0001
SYMBOL = 42

F0_OFF, F1_OFF, CAP_OFF = 42, 44, 46
LATENCY = expected_latency(F0_OFF, F1_OFF)   # 46


def market_frame(dst_port=PORT, msg_type=MSG_TYPE, symbol=SYMBOL,
                 price=0x0001_2345, **kwargs):
    return build_frame(dst_port, {
        F0_OFF:  u16(msg_type),
        F1_OFF:  u16(symbol),
        CAP_OFF: u32(price),
    }, **kwargs)


def model_should_match(dst_port, msg_type, symbol, ethertype, ip_proto):
    """Reference model, written from the specification rather than the RTL."""
    return (ethertype == 0x0800 and ip_proto == 0x11
            and dst_port == PORT and msg_type == MSG_TYPE and symbol == SYMBOL)


@cocotb.test()
async def test_matching_frame(dut):
    """A frame meeting every filter condition produces a response."""
    await start_clock(dut)
    await reset(dut)

    await send_frame(dut, market_frame())

    assert int(dut.match_count.value) == 1
    assert int(dut.latency_cycles.value) == LATENCY, (
        f"latency {int(dut.latency_cycles.value)}, expected {LATENCY}")
    assert int(dut.overrun_count.value) == 0


@cocotb.test()
async def test_latency_is_independent_of_frame_length(dut):
    """Cut-through: a 1500-byte frame must respond as fast as a 64-byte one.

    This is the test that fails if anyone ever 'simplifies' the design by
    buffering the frame before parsing it.
    """
    await start_clock(dut)
    await reset(dut)

    await send_frame(dut, market_frame(pad_to=64))
    short = int(dut.latency_cycles.value)

    await send_frame(dut, market_frame(pad_to=1500))
    long = int(dut.latency_cycles.value)

    assert short == long == LATENCY, f"length-dependent: {short} vs {long}"


@cocotb.test()
async def test_rejects_non_matching_frames(dut):
    """Every filter condition must independently be able to reject a frame."""
    await start_clock(dut)
    await reset(dut)

    cases = {
        "wrong symbol":   dict(symbol=SYMBOL + 1),
        "wrong port":     dict(dst_port=PORT + 1),
        "wrong msg type": dict(msg_type=MSG_TYPE + 1),
        "not IPv4":       dict(ethertype=0x0806),
        "not UDP":        dict(ip_proto=0x06),
    }

    for name, kwargs in cases.items():
        before = int(dut.match_count.value)
        await send_frame(dut, market_frame(**kwargs))
        assert int(dut.match_count.value) == before, f"{name}: not rejected"


@cocotb.test()
async def test_back_to_back_frames(dut):
    """State from one frame must not leak into the next.

    A rejected frame followed immediately by a good one is the case that breaks
    a parser which never clears its accumulated header verdicts.
    """
    await start_clock(dut)
    await reset(dut)

    await send_frame(dut, market_frame(ethertype=0x0806), gap=0)   # reject
    await send_frame(dut, market_frame(), gap=0)                   # accept
    assert int(dut.match_count.value) == 1

    await send_frame(dut, market_frame(), gap=0)                   # accept
    assert int(dut.match_count.value) == 2

    await send_frame(dut, market_frame(symbol=999), gap=0)         # reject
    assert int(dut.match_count.value) == 2


@cocotb.test()
async def test_capture_field(dut):
    """The observability path reports the payload capture field correctly."""
    await start_clock(dut)
    await reset(dut)

    await send_frame(dut, market_frame(price=0xDEADBEEF))
    assert int(dut.capture.value) == 0xDEADBEEF


@cocotb.test()
async def test_constrained_random(dut):
    """Randomised frames against the reference model, with coverage closure.

    Values are drawn so matching frames are common rather than vanishingly rare;
    uniform random over 16-bit fields would almost never produce a hit, and a
    test that only exercises the reject path proves very little.
    """
    await start_clock(dut)
    await reset(dut)

    random.seed(0xC0FFEE)   # a CI failure must be reproducible

    coverage = {"match": 0, "reject_port": 0, "reject_msg": 0,
                "reject_symbol": 0, "reject_ethertype": 0, "reject_proto": 0}
    matches = 0

    for _ in range(200):
        dst_port  = random.choice([PORT] * 4 + [random.randrange(65536)])
        msg_type  = random.choice([MSG_TYPE] * 4 + [random.randrange(65536)])
        symbol    = random.choice([SYMBOL] * 4 + [random.randrange(65536)])
        ethertype = random.choice([0x0800] * 9 + [0x0806])
        ip_proto  = random.choice([0x11] * 9 + [0x06])

        expected = model_should_match(dst_port, msg_type, symbol,
                                      ethertype, ip_proto)
        if expected:
            coverage["match"] += 1
        elif ethertype != 0x0800:
            coverage["reject_ethertype"] += 1
        elif ip_proto != 0x11:
            coverage["reject_proto"] += 1
        elif dst_port != PORT:
            coverage["reject_port"] += 1
        elif msg_type != MSG_TYPE:
            coverage["reject_msg"] += 1
        else:
            coverage["reject_symbol"] += 1

        before = int(dut.match_count.value)
        await send_frame(dut, market_frame(
            dst_port=dst_port, msg_type=msg_type, symbol=symbol,
            ethertype=ethertype, ip_proto=ip_proto), gap=2)
        got = int(dut.match_count.value) > before

        assert got == expected, (
            f"model/DUT disagree: port={dst_port} msg={msg_type} "
            f"symbol={symbol} ethertype={ethertype:#x} proto={ip_proto:#x} "
            f"-> dut={got} model={expected}")

        if expected:
            matches += 1
            assert int(dut.latency_cycles.value) == LATENCY

    dut._log.info(f"coverage bins: {coverage}")

    unhit = [name for name, count in coverage.items() if count == 0]
    assert not unhit, f"coverage holes, bins never exercised: {unhit}"
    assert matches > 20, f"only {matches} matching frames, raise the hit rate"
