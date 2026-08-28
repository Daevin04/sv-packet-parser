// Streaming, cut-through frame parser - configurable match fields.
//
// Consumes one byte per cycle as it arrives from the MAC and commits to a
// filter decision the moment the last byte the decision depends on is on the
// wire. It never buffers the frame, so the design has no packet memory and its
// latency does not depend on frame length.
//
// The Ethernet/IPv4/UDP header checks are fixed, because those headers are
// fixed. What the payload means is not, so the two 16-bit match fields and the
// 32-bit capture field are given as offsets and expected values. The same
// engine filters an exchange market-data feed, a sensor telemetry stream, or
// anything else with a fixed-layout payload - see rtl/examples/.
//
// Header checks accumulate incrementally as each field lands rather than all at
// once at the decision byte. That keeps the combinational cone at the decision
// down to one 16-bit comparator ANDed with already-registered results, instead
// of a five-field comparison that would set the critical path.

module frame_parse
  import pkt_pkg::*;
#(
  parameter logic [15:0] FILTER_PORT = 16'd5000,

  // First match field: offset of its HIGH byte, and the value that passes.
  parameter off_t        F0_OFF = OFF_PAYLOAD,          // 42
  parameter logic [15:0] F0_VAL = 16'h0001,

  // Second match field. May sit before or after the first; the decision byte
  // follows whichever ends later.
  parameter off_t        F1_OFF = OFF_PAYLOAD + 11'd2,  // 44
  parameter logic [15:0] F1_VAL = 16'd42,

  // 32-bit big-endian field captured for observability. Not on the fast path.
  parameter off_t        CAP_OFF = OFF_PAYLOAD + 11'd4  // 46
) (
  input  logic        clk,
  input  logic        rst_n,

  // Byte stream in. in_sof marks the first byte of a frame, in_eof the last.
  input  logic        in_valid,
  input  logic        in_sof,
  input  logic        in_eof,
  input  logic [7:0]  in_data,

  // One-cycle pulse, asserted on the decision byte of a matching frame.
  output logic        match,

  // Observability. Captured later in the frame than the decision, so these are
  // for statistics and debug, never for the fast path.
  output logic [31:0] capture,
  output logic        capture_valid
);

  // Elaborated, not hard-coded: move F1_OFF and the decision moves with it.
  localparam off_t DECISION_OFF = decision_offset(F0_OFF, F1_OFF);

  // Offset of the byte currently presented on in_data.
  off_t cnt_q, cnt;
  logic in_frame_q;
  logic active;

  assign cnt    = in_sof ? off_t'(0) : cnt_q;
  assign active = in_sof | in_frame_q;

  // Registered per-field verdicts, accumulated as the frame streams past.
  logic ethertype_ok_q;
  logic ip_proto_ok_q;
  logic dport_ok_q;
  logic f0_ok_q;
  logic f1_ok_q;

  // Half-captured 16-bit fields awaiting their low byte.
  logic [7:0] ethertype_hi_q;
  logic [7:0] dport_hi_q;
  logic [7:0] f0_hi_q;
  logic [7:0] f1_hi_q;

  logic [23:0] cap_partial_q;

  // Whichever match field ends ON the decision byte cannot have been registered
  // yet - its low byte is the byte currently on the wire. Selecting between the
  // live and registered value is a compile-time decision, so this costs a
  // multiplexer in the source and nothing in the hardware.
  logic f0_ok_now, f1_ok_now;
  assign f0_ok_now = (F0_OFF + off_t'(1) == DECISION_OFF)
                   ? ({f0_hi_q, in_data} == F0_VAL) : f0_ok_q;
  assign f1_ok_now = (F1_OFF + off_t'(1) == DECISION_OFF)
                   ? ({f1_hi_q, in_data} == F1_VAL) : f1_ok_q;

  logic header_ok;
  assign header_ok = ethertype_ok_q & ip_proto_ok_q & dport_ok_q;

  assign match = in_valid
               & active
               & (cnt == DECISION_OFF)
               & header_ok
               & f0_ok_now
               & f1_ok_now;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      cnt_q          <= '0;
      in_frame_q     <= 1'b0;
      ethertype_ok_q <= 1'b0;
      ip_proto_ok_q  <= 1'b0;
      dport_ok_q     <= 1'b0;
      f0_ok_q        <= 1'b0;
      f1_ok_q        <= 1'b0;
      ethertype_hi_q <= '0;
      dport_hi_q     <= '0;
      f0_hi_q        <= '0;
      f1_hi_q        <= '0;
      cap_partial_q  <= '0;
      capture        <= '0;
      capture_valid  <= 1'b0;
    end else begin
      capture_valid <= 1'b0;

      if (in_valid) begin
        cnt_q      <= cnt + off_t'(1);
        in_frame_q <= ~in_eof;

        // A new frame clears every accumulated verdict. Without this, a frame
        // that passed the EtherType check leaves that bit set for the next one,
        // and a non-IP frame inherits a stale pass.
        if (in_sof) begin
          ethertype_ok_q <= 1'b0;
          ip_proto_ok_q  <= 1'b0;
          dport_ok_q     <= 1'b0;
          f0_ok_q        <= 1'b0;
          f1_ok_q        <= 1'b0;
        end

        // Fixed header fields.
        case (cnt)
          OFF_ETHERTYPE_HI: ethertype_hi_q <= in_data;
          OFF_ETHERTYPE_LO: ethertype_ok_q <=
                              ({ethertype_hi_q, in_data} == ETHERTYPE_IPV4);
          OFF_IP_PROTO:     ip_proto_ok_q  <= (in_data == IP_PROTO_UDP);
          OFF_UDP_DPORT_HI: dport_hi_q     <= in_data;
          OFF_UDP_DPORT_LO: dport_ok_q     <=
                              ({dport_hi_q, in_data} == FILTER_PORT);
          default: ;
        endcase

        // Configurable payload fields. Written as if-chains rather than case
        // items because the offsets are parameters: two configurations could
        // legitimately place a match field and the capture field adjacently,
        // and overlapping case labels would be an elaboration error.
        if (cnt == F0_OFF)                  f0_hi_q <= in_data;
        if (cnt == F0_OFF + off_t'(1))      f0_ok_q <= ({f0_hi_q, in_data} == F0_VAL);
        if (cnt == F1_OFF)                  f1_hi_q <= in_data;
        if (cnt == F1_OFF + off_t'(1))      f1_ok_q <= ({f1_hi_q, in_data} == F1_VAL);

        if (cnt == CAP_OFF)                 cap_partial_q[23:16] <= in_data;
        if (cnt == CAP_OFF + off_t'(1))     cap_partial_q[15:8]  <= in_data;
        if (cnt == CAP_OFF + off_t'(2))     cap_partial_q[7:0]   <= in_data;
        if (cnt == CAP_OFF + off_t'(3)) begin
          capture       <= {cap_partial_q, in_data};
          capture_valid <= 1'b1;
        end
      end
    end
  end

endmodule
