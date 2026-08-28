// Fixed frame geometry for Ethernet II / IPv4 / UDP.
//
//   0  .. 5    destination MAC
//   6  .. 11   source MAC
//   12 .. 13   EtherType            (0x0800 for IPv4)
//   14         IPv4 version / IHL   (0x45 assumed: 20-byte header, no options)
//   23         IPv4 protocol        (0x11 for UDP)
//   34 .. 35   UDP source port
//   36 .. 37   UDP destination port
//   38 .. 41   UDP length, checksum
//   42 ..      application payload  <- layout is configuration, not geometry
//
// Only the parts that are the same for every UDP frame live here. Where the
// payload's fields sit is a property of whatever protocol is riding on top, so
// that belongs in parameters on frame_parse - see rtl/examples/ for two
// configurations that differ only in those.
//
// The IHL is assumed to be 5 (a 20-byte IPv4 header with no options). Real
// feeds do not use IP options, and assuming it is what allows every payload
// offset to be a compile-time constant instead of a runtime addition - the
// difference between a comparator and an adder in the critical path.
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

  // Where the application payload begins: 14 (Ethernet) + 20 (IPv4) + 8 (UDP).
  localparam off_t OFF_PAYLOAD = 11'd42;

  localparam logic [15:0] ETHERTYPE_IPV4 = 16'h0800;
  localparam logic [7:0]  IP_PROTO_UDP   = 8'h11;

  // The decision byte is not a constant of the design - it is a property of the
  // configuration. It is wherever the LAST field being matched on ends, because
  // that is the earliest point at which the answer is knowable and the latest
  // point at which anything can still change it.
  //
  // Elaborating it from the configured field offsets rather than hard-coding it
  // means a config that moves a match field automatically moves the decision,
  // and the testbench can assert the resulting latency without being told.
  function automatic off_t decision_offset(off_t field_a_hi, off_t field_b_hi);
    off_t later = (field_a_hi > field_b_hi) ? field_a_hi : field_b_hi;
    return later + off_t'(1);   // +1: a 16-bit field ends on its second byte
  endfunction

endpackage
