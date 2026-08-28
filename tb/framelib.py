"""Shared frame construction and stream drivers.

Both example configurations use these, which is itself part of the point: the
frames differ only in where the payload fields sit, because the engine differs
only in where it is told to look.
"""

import struct

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

CLK_NS = 8  # 125 MHz, the GMII byte clock for gigabit Ethernet

# Fixed header offsets - properties of Ethernet/IPv4/UDP, not of any config.
OFF_ETHERTYPE = 12
OFF_IP_PROTO = 23
OFF_UDP_DPORT = 36
OFF_PAYLOAD = 42


def build_frame(dst_port, fields=None, ethertype=0x0800, ip_proto=0x11,
                pad_to=64):
    """Assemble an Ethernet II / IPv4 / UDP frame.

    `fields` maps an absolute frame byte offset to the bytes to place there, so
    a test describes a payload layout the same way the RTL is parameterised.
    Everything not named is left as filler, which is part of the test: the
    design must ignore it.
    """
    fields = fields or {}
    needed = max([pad_to] + [off + len(data) for off, data in fields.items()])
    frame = bytearray(needed)

    frame[0:6] = b"\xff" * 6                        # dst MAC
    frame[6:12] = b"\x01\x02\x03\x04\x05\x06"       # src MAC
    frame[12:14] = struct.pack(">H", ethertype)
    frame[14] = 0x45                                # IPv4, IHL 5
    frame[23] = ip_proto
    frame[34:36] = struct.pack(">H", 1234)          # src port
    frame[36:38] = struct.pack(">H", dst_port)
    frame[38:40] = struct.pack(">H", 40)            # UDP length
    frame[40:42] = struct.pack(">H", 0)             # UDP checksum

    for off, data in fields.items():
        frame[off:off + len(data)] = data

    return bytes(frame)


def u16(value):
    return struct.pack(">H", value)


def u32(value):
    return struct.pack(">I", value)


async def start_clock(dut):
    cocotb.start_soon(Clock(dut.clk, CLK_NS, units="ns").start())


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


def expected_latency(f0_off, f1_off):
    """Cycles from SOF to response SOF for a given configuration.

    Derived the same way the RTL elaborates it: the decision lands on the second
    byte of whichever match field ends later, and the response follows one cycle
    after. A test that hard-coded 46 would silently stop testing anything the
    moment a configuration moved a field.
    """
    return max(f0_off, f1_off) + 1 + 1
