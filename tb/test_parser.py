"""cocotb testbench for the streaming UDP packet parser.

Three things are being proven here, in order of what an interviewer will ask:

  1. It matches the frames it should and rejects the ones it should not.
  2. It commits to the decision at byte 45, not at end of frame - which is
     what "cut-through" means and where the latency claim comes from.
  3. It survives back-to-back frames, which is where a parser that forgets to
     clear its accumulated header verdicts falls over.

The constrained-random test at the end drives randomised frames against an
independent Python model of the filter. That model is deliberately written from
the specification rather than from the RTL, so agreement between the two means
something.
"""

import random
import struct

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

# Must match the parameters the DUT was elaborated with.
FILTER_PORT = 5000
FILTER_MSG = 0x0001
FILTER_SYMBOL = 42

OFF_DECISION = 45
EXPECTED_LATENCY = OFF_DECISION + 1  # response SOF is one cycle after match

CLK_NS = 8  # 125 MHz, the GMII byte clock for gigabit Ethernet


def build_frame(dst_port=FILTER_PORT, msg_type=FILTER_MSG, symbol=FILTER_SYMBOL,
                price=0x0001_2345, qty=100, ethertype=0x0800, ip_proto=0x11,
                pad_to=64):
    """Assemble an Ethernet II / IPv4 / UDP frame with a fixed-format payload.

    Only the fields the parser inspects are meaningful; everything else is
    filler, which is itself part of the test - the design must ignore it.
    """
    frame = bytearray()
    frame += b"\xff" * 6                       # 0..5    dst MAC
    frame += b"\x01\x02\x03\x04\x05\x06"       # 6..11   src MAC
    frame += struct.pack(">H", ethertype)      # 12..13  EtherType

    ip = bytearray(20)                         # 14..33  IPv4 header
    ip[0] = 0x45                               #         version 4, IHL 5
    ip[9] = ip_proto                           # 23      protocol
    frame += ip

    frame += struct.pack(">H", 1234)           # 34..35  UDP source port
    frame += struct.pack(">H", dst_port)       # 36..37  UDP dest port
    frame += struct.pack(">H", 40)             # 38..39  UDP length
    frame += struct.pack(">H", 0)              # 40..41  UDP checksum

    frame += struct.pack(">H", msg_type)       # 42..43
    frame += struct.pack(">H", symbol)         # 44..45
    frame += struct.pack(">I", price)          # 46..49
    frame += struct.pack(">I", qty)            # 50..53

    if len(frame) < pad_to:
        frame += b"\x00" * (pad_to - len(frame))
    return bytes(frame)


def model_should_match(dst_port, msg_type, symbol, ethertype, ip_proto):
    """Independent reference model of the filter, written from the spec."""
    return (ethertype == 0x0800
            and ip_proto == 0x11
            and dst_port == FILTER_PORT
            and msg_type == FILTER_MSG
            and symbol == FILTER_SYMBOL)


async def reset(dut):
    dut.rst_n.value = 0
    dut.in_valid.value = 0
    dut.in_sof.value = 0
    dut.in_eof.value = 0
    dut.in_data.value = 0
    for _ in range(5):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)


async def send_frame(dut, frame, gap=4):
    """Drive one frame, one byte per cycle, then idle for `gap` cycles."""
    for i, byte in enumerate(frame):
        dut.in_valid.value = 1
        dut.in_sof.value = 1 if i == 0 else 0
        dut.in_eof.value = 1 if i == len(frame) - 1 else 0
        dut.in_data.value = byte
        await RisingEdge(dut.clk)

    dut.in_valid.value = 0
    dut.in_sof.value = 0
    dut.in_eof.value = 0
    for _ in range(gap):
        await RisingEdge(dut.clk)


async def start_clock(dut):
    cocotb.start_soon(Clock(dut.clk, CLK_NS, units="ns").start())


@cocotb.test()
async def test_matching_frame(dut):
    """A frame meeting every filter condition produces a response."""
    await start_clock(dut)
    await reset(dut)

    before = int(dut.match_count.value)
    await send_frame(dut, build_frame())

    assert int(dut.match_count.value) == before + 1, "expected exactly one match"
    assert int(dut.latency_cycles.value) == EXPECTED_LATENCY, (
        f"latency was {int(dut.latency_cycles.value)} cycles, "
        f"expected {EXPECTED_LATENCY}")
    assert int(dut.overrun_count.value) == 0


@cocotb.test()
async def test_latency_is_independent_of_frame_length(dut):
    """Cut-through: a 1500-byte frame must respond as fast as a 64-byte one.

    This is the test that would fail if anyone ever 'simplified' the design by
    buffering the frame before parsing it.
    """
    await start_clock(dut)
    await reset(dut)

    await send_frame(dut, build_frame(pad_to=64))
    short = int(dut.latency_cycles.value)

    await send_frame(dut, build_frame(pad_to=1500))
    long = int(dut.latency_cycles.value)

    assert short == long == EXPECTED_LATENCY, (
        f"latency depends on frame length: {short} vs {long}")


@cocotb.test()
async def test_rejects_non_matching_frames(dut):
    """Every filter condition must independently be able to reject a frame."""
    await start_clock(dut)
    await reset(dut)

    cases = {
        "wrong symbol":    dict(symbol=FILTER_SYMBOL + 1),
        "wrong port":      dict(dst_port=FILTER_PORT + 1),
        "wrong msg type":  dict(msg_type=FILTER_MSG + 1),
        "not IPv4":        dict(ethertype=0x0806),
        "not UDP":         dict(ip_proto=0x06),
    }

    for name, kwargs in cases.items():
        before = int(dut.match_count.value)
        await send_frame(dut, build_frame(**kwargs))
        after = int(dut.match_count.value)
        assert after == before, f"{name}: frame should have been rejected"


@cocotb.test()
async def test_back_to_back_frames(dut):
    """State from one frame must not leak into the next.

    A rejected frame followed immediately by a good one is the case that breaks
    a parser which never clears its accumulated header verdicts.
    """
    await start_clock(dut)
    await reset(dut)

    await send_frame(dut, build_frame(ethertype=0x0806), gap=0)   # reject
    await send_frame(dut, build_frame(), gap=0)                   # accept
    assert int(dut.match_count.value) == 1

    await send_frame(dut, build_frame(), gap=0)                   # accept
    assert int(dut.match_count.value) == 2

    await send_frame(dut, build_frame(symbol=999), gap=0)         # reject
    assert int(dut.match_count.value) == 2


@cocotb.test()
async def test_price_capture(dut):
    """The observability path reports the payload price field correctly."""
    await start_clock(dut)
    await reset(dut)

    await send_frame(dut, build_frame(price=0xDEADBEEF))
    assert int(dut.price.value) == 0xDEADBEEF, (
        f"price was {int(dut.price.value):#x}, expected 0xDEADBEEF")


@cocotb.test()
async def test_constrained_random(dut):
    """Randomised frames against an independent model, with coverage tracking.

    Values are drawn so that matching frames are common rather than vanishingly
    rare - uniform random over 16-bit fields would almost never produce a hit,
    and a test that only ever exercises the reject path proves very little.
    """
    await start_clock(dut)
    await reset(dut)

    random.seed(0xC0FFEE)   # deterministic: a CI failure must be reproducible

    coverage = {"match": 0, "reject_port": 0, "reject_msg": 0,
                "reject_symbol": 0, "reject_ethertype": 0, "reject_proto": 0}

    matches = 0
    for _ in range(200):
        dst_port  = random.choice([FILTER_PORT] * 4 + [random.randrange(65536)])
        msg_type  = random.choice([FILTER_MSG] * 4 + [random.randrange(65536)])
        symbol    = random.choice([FILTER_SYMBOL] * 4 + [random.randrange(65536)])
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
        elif dst_port != FILTER_PORT:
            coverage["reject_port"] += 1
        elif msg_type != FILTER_MSG:
            coverage["reject_msg"] += 1
        else:
            coverage["reject_symbol"] += 1

        before = int(dut.match_count.value)
        await send_frame(dut, build_frame(dst_port=dst_port, msg_type=msg_type,
                                          symbol=symbol, ethertype=ethertype,
                                          ip_proto=ip_proto), gap=2)
        got = int(dut.match_count.value) > before

        assert got == expected, (
            f"model/DUT disagree: port={dst_port} msg={msg_type} "
            f"symbol={symbol} ethertype={ethertype:#x} proto={ip_proto:#x} "
            f"-> dut={got} model={expected}")

        if expected:
            matches += 1
            assert int(dut.latency_cycles.value) == EXPECTED_LATENCY

    dut._log.info(f"coverage bins: {coverage}")

    # Coverage closure: every bin must be hit, or the run proved less than the
    # pass count suggests.
    unhit = [name for name, count in coverage.items() if count == 0]
    assert not unhit, f"coverage holes, bins never exercised: {unhit}"
    assert matches > 20, f"only {matches} matching frames, raise the hit rate"
