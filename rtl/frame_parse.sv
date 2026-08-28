// Streaming, cut-through frame parser.
//
// Consumes one byte per cycle as it arrives from the MAC and commits to a
// filter decision the moment the last byte the decision depends on is on the
// wire - byte 45 of the frame. It never buffers the frame, so the design has no
// packet memory and its latency does not depend on frame length.
//
// The header fields are compared incrementally as they land rather than all at
// once at the decision byte. That keeps the combinational cone at byte 45 down
// to a single 16-bit comparator plus an AND of already-registered results,
// instead of a four-field comparison that would set the critical path.

module frame_parse
  import pkt_pkg::*;
#(
  parameter logic [15:0] FILTER_PORT   = 16'd5000,
  parameter logic [15:0] FILTER_MSG    = 16'h0001,
  parameter logic [15:0] FILTER_SYMBOL = 16'd42
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
  output logic [31:0] price,
  output logic        price_valid
);

  // Offset of the byte currently presented on in_data.
  off_t cnt_q, cnt;
  logic in_frame_q;
  logic active;

  assign cnt    = in_sof ? off_t'(0) : cnt_q;
  assign active = in_sof | in_frame_q;

  // Registered per-field results, accumulated as the header streams past.
  logic ethertype_ok_q;
  logic ip_proto_ok_q;
  logic dport_ok_q;
  logic msgtype_ok_q;

  // Half-captured 16-bit fields awaiting their low byte.
  logic [7:0] ethertype_hi_q;
  logic [7:0] dport_hi_q;
  logic [7:0] msgtype_hi_q;
  logic [7:0] symbol_hi_q;

  logic [23:0] price_partial_q;

  // The symbol id completes on this cycle: high byte is registered, low byte is
  // the byte currently on the wire.
  logic [15:0] symbol_now;
  assign symbol_now = {symbol_hi_q, in_data};

  logic header_ok;
  assign header_ok = ethertype_ok_q & ip_proto_ok_q & dport_ok_q & msgtype_ok_q;

  assign match = in_valid
               & active
               & (cnt == OFF_DECISION)
               & header_ok
               & (symbol_now == FILTER_SYMBOL);

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      cnt_q           <= '0;
      in_frame_q      <= 1'b0;
      ethertype_ok_q  <= 1'b0;
      ip_proto_ok_q   <= 1'b0;
      dport_ok_q      <= 1'b0;
      msgtype_ok_q    <= 1'b0;
      ethertype_hi_q  <= '0;
      dport_hi_q      <= '0;
      msgtype_hi_q    <= '0;
      symbol_hi_q     <= '0;
      price_partial_q <= '0;
      price           <= '0;
      price_valid     <= 1'b0;
    end else begin
      price_valid <= 1'b0;

      if (in_valid) begin
        cnt_q      <= cnt + off_t'(1);
        in_frame_q <= ~in_eof;

        // A new frame clears every accumulated verdict. Without this a frame
        // that passed the EtherType check would leave that bit set for the
        // next one, and a non-IP frame could inherit a stale pass.
        if (in_sof) begin
          ethertype_ok_q <= 1'b0;
          ip_proto_ok_q  <= 1'b0;
          dport_ok_q     <= 1'b0;
          msgtype_ok_q   <= 1'b0;
        end

        case (cnt)
          OFF_ETHERTYPE_HI: ethertype_hi_q <= in_data;
          OFF_ETHERTYPE_LO: ethertype_ok_q <=
                              ({ethertype_hi_q, in_data} == ETHERTYPE_IPV4);

          OFF_IP_PROTO:     ip_proto_ok_q  <= (in_data == IP_PROTO_UDP);

          OFF_UDP_DPORT_HI: dport_hi_q     <= in_data;
          OFF_UDP_DPORT_LO: dport_ok_q     <=
                              ({dport_hi_q, in_data} == FILTER_PORT);

          OFF_MSG_TYPE_HI:  msgtype_hi_q   <= in_data;
          OFF_MSG_TYPE_LO:  msgtype_ok_q   <=
                              ({msgtype_hi_q, in_data} == FILTER_MSG);

          OFF_SYMBOL_HI:    symbol_hi_q    <= in_data;

          OFF_PRICE_B3:     price_partial_q[23:16] <= in_data;
          OFF_PRICE_B2:     price_partial_q[15:8]  <= in_data;
          OFF_PRICE_B1:     price_partial_q[7:0]   <= in_data;
          OFF_PRICE_B0: begin
            price       <= {price_partial_q, in_data};
            price_valid <= 1'b1;
          end

          default: ; // nothing to capture at this offset
        endcase
      end
    end
  end

endmodule
