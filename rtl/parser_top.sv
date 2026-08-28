// Top level: byte stream in, response stream out, latency measured in cycles.
//
// The latency counter is the point of the whole project. It counts from the
// first byte of the frame to the first byte of the response, in cycles, in
// hardware - not estimated from a simulation waveform by hand. Multiply by the
// clock period for the number that goes on the resume.

module parser_top
  import pkt_pkg::*;
#(
  parameter logic [15:0] FILTER_PORT = 16'd5000,
  parameter off_t        F0_OFF      = OFF_PAYLOAD,
  parameter logic [15:0] F0_VAL      = 16'h0001,
  parameter off_t        F1_OFF      = OFF_PAYLOAD + 11'd2,
  parameter logic [15:0] F1_VAL      = 16'd42,
  parameter off_t        CAP_OFF     = OFF_PAYLOAD + 11'd4,
  parameter int          RESP_BYTES  = 8
) (
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

  // Statistics.
  output logic [15:0] latency_cycles,   // SOF -> first response byte
  output logic        latency_valid,    // one-cycle pulse when updated
  output logic [31:0] capture,
  output logic        capture_valid,
  output logic [15:0] match_count,
  output logic [15:0] overrun_count
);

  logic match;

  frame_parse #(
    .FILTER_PORT (FILTER_PORT),
    .F0_OFF      (F0_OFF),
    .F0_VAL      (F0_VAL),
    .F1_OFF      (F1_OFF),
    .F1_VAL      (F1_VAL),
    .CAP_OFF     (CAP_OFF)
  ) u_parse (
    .clk           (clk),
    .rst_n         (rst_n),
    .in_valid      (in_valid),
    .in_sof        (in_sof),
    .in_eof        (in_eof),
    .in_data       (in_data),
    .match         (match),
    .capture       (capture),
    .capture_valid (capture_valid)
  );

  resp_gen #(
    .RESP_BYTES (RESP_BYTES)
  ) u_resp (
    .clk           (clk),
    .rst_n         (rst_n),
    .match         (match),
    .resp_valid    (resp_valid),
    .resp_data     (resp_data),
    .resp_sof      (resp_sof),
    .resp_eof      (resp_eof),
    .overrun_count (overrun_count)
  );

  // Free-running cycle counter, sampled at start of frame. Measuring against a
  // free-running counter rather than starting one at SOF means the measurement
  // costs nothing on the fast path.
  logic [15:0] now_q;
  logic [15:0] sof_stamp_q;
  logic        timing_q;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      now_q          <= '0;
      sof_stamp_q    <= '0;
      timing_q       <= 1'b0;
      latency_cycles <= '0;
      latency_valid  <= 1'b0;
      match_count    <= '0;
    end else begin
      now_q         <= now_q + 16'd1;
      latency_valid <= 1'b0;

      if (in_valid && in_sof) begin
        sof_stamp_q <= now_q;
        timing_q    <= 1'b1;
      end

      if (match) begin
        match_count <= match_count + 16'd1;
      end

      // resp_sof is asserted on the first response byte, one cycle after match.
      if (resp_sof && timing_q) begin
        latency_cycles <= now_q - sof_stamp_q;
        latency_valid  <= 1'b1;
        timing_q       <= 1'b0;
      end
    end
  end

endmodule
