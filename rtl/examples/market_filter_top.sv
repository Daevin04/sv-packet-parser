// Example configuration: exchange market-data pre-filter.
//
// Drops every UDP frame that is not the instrument this engine cares about,
// before it reaches the host. The benefit is not only reduced load - it is that
// the software path never sees the packet at all: no DMA, no interrupt, no
// cache pollution, and so no jitter injected into the hot path.
//
// Payload layout:
//   +0 .. +1   message type   (byte 42..43)  -> match field 0
//   +2 .. +3   symbol id      (byte 44..45)  -> match field 1
//   +4 .. +7   price          (byte 46..49)  -> captured for statistics
//
// Match field 1 ends at byte 45, so the decision commits at byte 45 - while
// bytes 46 onward of a 64-byte minimum frame are still arriving.

module market_filter_top
  import pkt_pkg::*;
(
  input  logic        clk,
  input  logic        rst_n,
  input  logic        in_valid,
  input  logic        in_sof,
  input  logic        in_eof,
  input  logic [7:0]  in_data,
  output logic        resp_valid,
  output logic [7:0]  resp_data,
  output logic        resp_sof,
  output logic        resp_eof,
  output logic [15:0] latency_cycles,
  output logic        latency_valid,
  output logic [31:0] capture,
  output logic        capture_valid,
  output logic [15:0] match_count,
  output logic [15:0] overrun_count
);

  parser_top #(
    .FILTER_PORT (16'd5000),
    .F0_OFF      (11'd42),      // message type
    .F0_VAL      (16'h0001),
    .F1_OFF      (11'd44),      // symbol id
    .F1_VAL      (16'd42),
    .CAP_OFF     (11'd46)       // price
  ) u_engine (.*);

endmodule
