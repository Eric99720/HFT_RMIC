`timescale 1ns/1ps
`include "taifex_tmp_v2187_defs.svh"

module hft_rmic_committed_exec_event_adapter_v1 #(
    parameter integer QTY_W = 16
) (
    input wire clk, input wire rst_n,

    input wire live_meta_valid,
    input wire [7:0] live_meta_msg_type,
    input wire [31:0] live_meta_order_id,
    input wire [31:0] live_meta_report_seq,
    input wire [7:0] live_meta_position_effect,
    input wire [15:0] live_meta_before_qty,
    input wire replay_meta_valid,
    input wire [7:0] replay_meta_msg_type,
    input wire [31:0] replay_meta_order_id,
    input wire [31:0] replay_meta_report_seq,
    input wire [7:0] replay_meta_position_effect,
    input wire [15:0] replay_meta_before_qty,

    input wire committed_valid,
    input wire committed_from_replay,
    input wire [7:0] committed_msg_type,
    input wire [7:0] committed_status_code,
    input wire [7:0] committed_exec_type,
    input wire [31:0] committed_order_id,
    input wire committed_side,
    input wire [31:0] committed_order_price,
    input wire [QTY_W-1:0] committed_last_qty,
    input wire [QTY_W-1:0] committed_leaves_qty,
    input wire [31:0] committed_report_seq,

    output wire risk_commit_valid,
    output wire [7:0] risk_commit_msg_type,
    output wire [7:0] risk_commit_status_code,
    output wire [7:0] risk_commit_exec_type,
    output wire [31:0] risk_commit_order_id,
    output wire risk_commit_side,
    output wire [7:0] risk_commit_position_effect,
    output wire [31:0] risk_commit_order_price,
    output wire [QTY_W-1:0] risk_commit_last_qty,
    output wire [QTY_W-1:0] risk_commit_leaves_qty,
    output wire [QTY_W-1:0] risk_commit_before_qty,
    output wire [31:0] risk_commit_report_seq,
    output wire risk_commit_is_replay,
    output wire metadata_error
);
    reg live_meta_available, replay_meta_available;

    wire is_r02 = (committed_msg_type == `HFT_RMIC_TAIFEX_MSG_R02);
    wire is_r32 = (committed_msg_type == `HFT_RMIC_TAIFEX_MSG_R32);
    wire is_r03 = (committed_msg_type == `HFT_RMIC_TAIFEX_MSG_R03);
    wire needs_meta = is_r02 || is_r32;

    wire live_match = (live_meta_available || live_meta_valid) &&
        (live_meta_msg_type == committed_msg_type) &&
        (live_meta_order_id == committed_order_id) &&
        (live_meta_report_seq == committed_report_seq);
    wire replay_match = (replay_meta_available || replay_meta_valid) &&
        (replay_meta_msg_type == committed_msg_type) &&
        (replay_meta_order_id == committed_order_id) &&
        (replay_meta_report_seq == committed_report_seq);
    wire selected_match = committed_from_replay ? replay_match : live_match;

    assign metadata_error = committed_valid && needs_meta && !selected_match;
    assign risk_commit_valid = committed_valid &&
        (is_r03 || (needs_meta && selected_match));
    assign risk_commit_msg_type = committed_msg_type;
    assign risk_commit_status_code = committed_status_code;
    assign risk_commit_exec_type = committed_exec_type;
    assign risk_commit_order_id = committed_order_id;
    assign risk_commit_side = committed_side;
    assign risk_commit_position_effect = needs_meta ?
        (committed_from_replay ? replay_meta_position_effect : live_meta_position_effect) : 8'd0;
    assign risk_commit_order_price = committed_order_price;
    assign risk_commit_last_qty = committed_last_qty;
    assign risk_commit_leaves_qty = committed_leaves_qty;
    assign risk_commit_before_qty = needs_meta ?
        {{(QTY_W-16){1'b0}}, (committed_from_replay ? replay_meta_before_qty : live_meta_before_qty)} : {QTY_W{1'b0}};
    assign risk_commit_report_seq = committed_report_seq;
    assign risk_commit_is_replay = committed_from_replay;

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            live_meta_available <= 1'b0;
            replay_meta_available <= 1'b0;
        end else begin
            if(live_meta_valid)
                live_meta_available <= 1'b1;
            else if(committed_valid && !committed_from_replay && needs_meta)
                live_meta_available <= 1'b0;

            if(replay_meta_valid)
                replay_meta_available <= 1'b1;
            else if(committed_valid && committed_from_replay && needs_meta)
                replay_meta_available <= 1'b0;
        end
    end

    initial begin
        if(QTY_W < 16) $error("QTY_W must be >= 16 for TAIFEX quantity fields");
    end
endmodule
