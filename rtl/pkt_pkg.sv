// Frame layout constants for an Ethernet II / IPv4 / UDP frame carrying a
// fixed-format application message.
//
// Offsets are byte positions counted from the first byte of the destination
// MAC address, which is byte 0 of the frame as it arrives from the PHY.
//
//   0  .. 5    destination MAC
//   6  .. 11   source MAC
//   12 .. 13   EtherType            (0x0800 for IPv4)
//   14         IPv4 version / IHL   (0x45 assumed: 20-byte header, no options)
//   23         IPv4 protocol        (0x11 for UDP)
//   34 .. 35   UDP source port
//   36 .. 37   UDP destination port
//   38 .. 41   UDP length, checksum
//   42 .. 43   message type      |
//   44 .. 45   symbol id         |  fixed-format application payload
//   46 .. 49   price             |
//   50 .. 53   quantity          |
//
// The IHL is assumed to be 5 (a 20-byte IPv4 header with no options). Real
// market data feeds do not use IP options, and assuming it is what allows every
// payload offset to be a compile-time constant instead of a runtime addition -
// the difference between a comparator and an adder in the critical path.
//
// Every offset is declared at the counter's own width. Declaring them as plain
// `int` reads more naturally but makes each comparison a 32-bit-against-11-bit
// operation, which Verilator flags under -Wall and which hides genuine width
// bugs in the noise.

package pkt_pkg;

  // 11 bits covers offset 1517, the last byte of a maximum-size frame.
  localparam int CNT_W = 11;
  typedef logic [CNT_W-1:0] off_t;

  // Two-byte fields are named _HI / _LO because the parser consumes them one
  // byte per cycle and needs to act at each half separately.
  localparam off_t OFF_ETHERTYPE_HI = 11'd12;
  localparam off_t OFF_ETHERTYPE_LO = 11'd13;
  localparam off_t OFF_IP_PROTO     = 11'd23;
  localparam off_t OFF_UDP_DPORT_HI = 11'd36;
  localparam off_t OFF_UDP_DPORT_LO = 11'd37;
  localparam off_t OFF_MSG_TYPE_HI  = 11'd42;
  localparam off_t OFF_MSG_TYPE_LO  = 11'd43;
  localparam off_t OFF_SYMBOL_HI    = 11'd44;
  localparam off_t OFF_SYMBOL_LO    = 11'd45;
  localparam off_t OFF_PRICE_B3     = 11'd46;   // big-endian on the wire
  localparam off_t OFF_PRICE_B2     = 11'd47;
  localparam off_t OFF_PRICE_B1     = 11'd48;
  localparam off_t OFF_PRICE_B0     = 11'd49;

  // The last byte the filter decision depends on. Deciding here, rather than at
  // end-of-frame, is the entire latency argument of this design: a 64-byte
  // minimum Ethernet frame is 64 cycles on an 8-bit datapath, and this commits
  // at cycle 45 regardless of how long the frame turns out to be.
  localparam off_t OFF_DECISION = OFF_SYMBOL_LO;

  localparam logic [15:0] ETHERTYPE_IPV4 = 16'h0800;
  localparam logic [7:0]  IP_PROTO_UDP   = 8'h11;

endpackage
