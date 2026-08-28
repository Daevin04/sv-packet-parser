// Example configuration: sensor telemetry triage.
//
// Identical engine, different payload contract. A sensor array streams UDP
// telemetry and only one sensor and channel are of interest; everything else is
// discarded in the fabric rather than being carried to a host that would have
// to look at it and throw it away.
//
// This is the same problem the LHC Level-1 trigger solves - decide inside a
// fixed latency budget which data is worth keeping, because keeping all of it
// is not physically possible.
//
// Payload layout:
//   +0 .. +1   sensor id      (byte 42..43)  -> match field 0
//   +4 .. +5   channel        (byte 46..47)  -> match field 1
//   +6 .. +9   sample         (byte 48..51)  -> captured
//
// Note the consequence: match field 1 now ends at byte 47, so this instance
// decides at byte 47 rather than 45. The decision offset is elaborated from the
// configured offsets, so it tracks the layout automatically - there is no
// constant to remember to update.

module telemetry_filter_top
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
    .FILTER_PORT (16'd6000),
    .F0_OFF      (11'd42),      // sensor id
    .F0_VAL      (16'h00A1),
    .F1_OFF      (11'd46),      // channel
    .F1_VAL      (16'd7),
    .CAP_OFF     (11'd48)       // sample
  ) u_engine (.*);

endmodule
