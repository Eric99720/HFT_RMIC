`timescale 1ns/1ps

// CI-only handshake stub for the private frozen HFT encoder dependency.
// Local I4 XSim/Vivado uses the real pinned HFT encoder.  This stub is not R01
// byte-format evidence; it exists only to validate integration ownership,
// reject suppression and backpressure in GitHub CI without private submodules.
module financial_protocol_encoder #(
    parameter ORDER_WIDTH=256, DATA_WIDTH=64, MAX_PAYLOAD_BYTES=256,
    parameter FIFO_DEPTH=16, PAYLOAD_LEN_WIDTH=16,
    parameter ALLOW_STRATEGY_BYPASS_WITHOUT_TX_READY=1'b0,
    parameter ENABLE_TMP_MAINTENANCE=1'b0,
    parameter ENABLE_TMP_FLOW_CONTROL=1'b0
) (
    input wire clk, input wire rst,
    input wire manual_order_valid, output wire manual_order_ready,
    input wire [ORDER_WIDTH-1:0] manual_order_data,
    input wire strategy_order_valid, output wire strategy_order_ready,
    input wire [ORDER_WIDTH-1:0] strategy_order_data,
    input wire r04_valid, output wire r04_ready,
    input wire local_r04_valid, output wire local_r04_ready,
    input wire ordinary_credit_available,
    input wire [31:0] msg_epoch_s, input wire [15:0] msg_ms,
    input wire [15:0] fcm_id, input wire [15:0] session_id,
    input wire [15:0] cm_id, input wire [15:0] body_fcm_id,
    input wire [63:0] user_define, input wire [159:0] symbol_text,
    input wire [7:0] order_source, input wire [23:0] info_source,
    input wire [31:0] r01_msg_seq_num,
    input wire network_ready,
    output reg [DATA_WIDTH-1:0] tx_data,
    output reg [(DATA_WIDTH/8)-1:0] tx_keep,
    output reg tx_valid, input wire tx_ready,
    output reg tx_last, output reg [PAYLOAD_LEN_WIDTH-1:0] tx_payload_len,
    output wire tx_complete, output reg [7:0] tx_message_type,
    output wire fifo_full, output wire fifo_empty, output wire encoder_busy,
    output wire payload_active, output reg error_overflow,
    output reg [31:0] accepted_order_count, output reg [31:0] sent_order_count,
    output reg [31:0] sent_r01_count, output reg [31:0] sent_r05_count,
    output reg [31:0] sent_r04_count, output reg [31:0] dropped_order_count,
    output reg [31:0] r01_tcp_payload_sum, output reg r01_tcp_payload_sum_valid
);
    assign manual_order_ready = 1'b0;
    assign r04_ready = 1'b0;
    assign local_r04_ready = 1'b0;
    assign fifo_full = 1'b0;
    assign fifo_empty = ~tx_valid;
    assign encoder_busy = tx_valid;
    assign payload_active = tx_valid;
    assign strategy_order_ready = network_ready && (!tx_valid || tx_ready);
    assign tx_complete = tx_valid && tx_ready && tx_last;

    always @(posedge clk) begin
        if (rst) begin
            tx_data <= 0; tx_keep <= 0; tx_valid <= 0; tx_last <= 0;
            tx_payload_len <= 0; tx_message_type <= 0; error_overflow <= 0;
            accepted_order_count <= 0; sent_order_count <= 0; sent_r01_count <= 0;
            sent_r05_count <= 0; sent_r04_count <= 0; dropped_order_count <= 0;
            r01_tcp_payload_sum <= 0; r01_tcp_payload_sum_valid <= 0;
        end else begin
            if (tx_complete) begin
                tx_valid <= 1'b0;
                sent_order_count <= sent_order_count + 1'b1;
                sent_r01_count <= sent_r01_count + 1'b1;
            end
            if (strategy_order_valid && strategy_order_ready) begin
                accepted_order_count <= accepted_order_count + 1'b1;
                tx_data <= strategy_order_data[DATA_WIDTH-1:0];
                tx_keep <= {(DATA_WIDTH/8){1'b1}};
                tx_valid <= 1'b1;
                tx_last <= 1'b1;
                tx_payload_len <= 16'd80;
                tx_message_type <= 8'd101;
            end
        end
    end
endmodule
