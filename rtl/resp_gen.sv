// Emits a fixed response payload, one byte per cycle, on a match pulse.
//
// The response contents are a compile-time constant held in a small ROM, so
// nothing is computed on the fast path: the first response byte is driven the
// cycle after match, with no lookup, no arithmetic and no arbitration.
//
// A match arriving while a response is still in flight is dropped and counted.
// Silently overwriting the in-flight response would corrupt it, and buffering
// would add a queue and its latency to the one path this design exists to keep
// short - so the overrun is made visible instead of absorbed.

module resp_gen #(
  parameter int RESP_BYTES = 8
) (
  input  logic       clk,
  input  logic       rst_n,

  input  logic       match,

  output logic       resp_valid,
  output logic [7:0] resp_data,
  output logic       resp_sof,
  output logic       resp_eof,

  output logic [15:0] overrun_count
);

  // The canned response. Replace with whatever the downstream device expects;
  // keeping it constant is what keeps the emit path free of logic.
  localparam logic [7:0] RESP_ROM [0:7] = '{
    8'hAA, 8'h55, 8'h00, 8'h01, 8'hDE, 8'hAD, 8'hBE, 8'hEF
  };

  // Index is exactly wide enough to address the ROM, so it wraps naturally and
  // every comparison against LAST_IDX is width-matched.
  localparam int   IDX_W = (RESP_BYTES <= 1) ? 1 : $clog2(RESP_BYTES);
  typedef logic [IDX_W-1:0] idx_t;
  localparam idx_t LAST_IDX = idx_t'(RESP_BYTES - 1);

  idx_t idx_q;
  logic busy_q;

  assign resp_valid = busy_q;
  assign resp_data  = RESP_ROM[idx_q];
  assign resp_sof   = busy_q & (idx_q == idx_t'(0));
  assign resp_eof   = busy_q & (idx_q == LAST_IDX);

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      idx_q         <= '0;
      busy_q        <= 1'b0;
      overrun_count <= '0;
    end else begin
      if (busy_q) begin
        if (match) begin
          overrun_count <= overrun_count + 16'd1;
        end
        if (idx_q == LAST_IDX) begin
          busy_q <= 1'b0;
          idx_q  <= idx_t'(0);
        end else begin
          idx_q <= idx_q + idx_t'(1);
        end
      end else if (match) begin
        busy_q <= 1'b1;
        idx_q  <= '0;
      end
    end
  end

endmodule
