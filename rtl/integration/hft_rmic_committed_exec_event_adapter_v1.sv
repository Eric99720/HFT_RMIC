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

    reg [7:0]  live_msg_type_q, replay_msg_type_q;
    reg [31:0] live_order_id_q, replay_order_id_q;
    reg [31:0] live_report_seq_q, replay_report_seq_q;
    reg [7:0]  live_position_effect_q, replay_position_effect_q;
    reg [15:0] live_before_qty_q, replay_before_qty_q;

    wire is_r02 = (committed_msg_type == `HFT_RMIC_TAIFEX_MSG_R02);
    wire is_r32 = (committed_msg_type == `HFT_RMIC_TAIFEX_MSG_R32);
    wire is_r03 = (committed_msg_type == `HFT_RMIC_TAIFEX_MSG_R03);
    wire needs_meta = is_r02 || is_r32;

    // A pending cache entry always owns the next matching commit.  A new
    // metadata pulse may replace it only in the same cycle that the old entry
    // is successfully consumed.  This prevents silent overwrite if commit
    // delivery is ever delayed relative to packet parsing.
    wire live_cache_match = live_meta_available &&
        (live_msg_type_q == committed_msg_type) &&
        (live_order_id_q == committed_order_id) &&
        (live_report_seq_q == committed_report_seq);
    wire replay_cache_match = replay_meta_available &&
        (replay_msg_type_q == committed_msg_type) &&
        (replay_order_id_q == committed_order_id) &&
        (replay_report_seq_q == committed_report_seq);

    wire live_direct_match = !live_meta_available && live_meta_valid &&
        (live_meta_msg_type == committed_msg_type) &&
        (live_meta_order_id == committed_order_id) &&
        (live_meta_report_seq == committed_report_seq);
    wire replay_direct_match = !replay_meta_available && replay_meta_valid &&
        (replay_meta_msg_type == committed_msg_type) &&
        (replay_meta_order_id == committed_order_id) &&
        (replay_meta_report_seq == committed_report_seq);

    wire live_match = live_cache_match || live_direct_match;
    wire replay_match = replay_cache_match || replay_direct_match;
    wire selected_match = committed_from_replay ? replay_match : live_match;

    wire live_consume_cache = committed_valid && !committed_from_replay &&
                              needs_meta && live_cache_match;
    wire replay_consume_cache = committed_valid && committed_from_replay &&
                                needs_meta && replay_cache_match;
    wire live_consume_direct = committed_valid && !committed_from_replay &&
                               needs_meta && live_direct_match;
    wire replay_consume_direct = committed_valid && committed_from_replay &&
                                 needs_meta && replay_direct_match;

    wire live_overrun = live_meta_valid && live_meta_available && !live_consume_cache;
    wire replay_overrun = replay_meta_valid && replay_meta_available && !replay_consume_cache;
    wire commit_mismatch = committed_valid && needs_meta && !selected_match;

    wire [7:0] selected_position_effect =
        committed_from_replay ?
            (replay_meta_available ? replay_position_effect_q : replay_meta_position_effect) :
            (live_meta_available ? live_position_effect_q : live_meta_position_effect);
    wire [15:0] selected_before_qty =
        committed_from_replay ?
            (replay_meta_available ? replay_before_qty_q : replay_meta_before_qty) :
            (live_meta_available ? live_before_qty_q : live_meta_before_qty);

    assign metadata_error = commit_mismatch || live_overrun || replay_overrun;
    assign risk_commit_valid = committed_valid &&
        (is_r03 || (needs_meta && selected_match));
    assign risk_commit_msg_type = committed_msg_type;
    assign risk_commit_status_code = committed_status_code;
    assign risk_commit_exec_type = committed_exec_type;
    assign risk_commit_order_id = committed_order_id;
    assign risk_commit_side = committed_side;
    assign risk_commit_position_effect = needs_meta ? selected_position_effect : 8'd0;
    assign risk_commit_order_price = committed_order_price;
    assign risk_commit_last_qty = committed_last_qty;
    assign risk_commit_leaves_qty = committed_leaves_qty;
    assign risk_commit_before_qty = needs_meta ?
        {{(QTY_W-16){1'b0}}, selected_before_qty} : {QTY_W{1'b0}};
    assign risk_commit_report_seq = committed_report_seq;
    assign risk_commit_is_replay = committed_from_replay;

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            live_meta_available <= 1'b0;
            replay_meta_available <= 1'b0;
            live_msg_type_q <= 8'd0;
            live_order_id_q <= 32'd0;
            live_report_seq_q <= 32'd0;
            live_position_effect_q <= 8'd0;
            live_before_qty_q <= 16'd0;
            replay_msg_type_q <= 8'd0;
            replay_order_id_q <= 32'd0;
            replay_report_seq_q <= 32'd0;
            replay_position_effect_q <= 8'd0;
            replay_before_qty_q <= 16'd0;
        end else begin
            // Live cache.
            if (live_meta_available) begin
                if (live_consume_cache) begin
                    if (live_meta_valid) begin
                        live_msg_type_q <= live_meta_msg_type;
                        live_order_id_q <= live_meta_order_id;
                        live_report_seq_q <= live_meta_report_seq;
                        live_position_effect_q <= live_meta_position_effect;
                        live_before_qty_q <= live_meta_before_qty;
                        live_meta_available <= 1'b1;
                    end else begin
                        live_meta_available <= 1'b0;
                    end
                end
                // On overrun retain the old entry; metadata_error escalates the
                // full app into recovery-required rather than corrupting order
                // association.
            end else if (live_meta_valid && !live_consume_direct) begin
                live_msg_type_q <= live_meta_msg_type;
                live_order_id_q <= live_meta_order_id;
                live_report_seq_q <= live_meta_report_seq;
                live_position_effect_q <= live_meta_position_effect;
                live_before_qty_q <= live_meta_before_qty;
                live_meta_available <= 1'b1;
            end

            // Replay cache.
            if (replay_meta_available) begin
                if (replay_consume_cache) begin
                    if (replay_meta_valid) begin
                        replay_msg_type_q <= replay_meta_msg_type;
                        replay_order_id_q <= replay_meta_order_id;
                        replay_report_seq_q <= replay_meta_report_seq;
                        replay_position_effect_q <= replay_meta_position_effect;
                        replay_before_qty_q <= replay_meta_before_qty;
                        replay_meta_available <= 1'b1;
                    end else begin
                        replay_meta_available <= 1'b0;
                    end
                end
            end else if (replay_meta_valid && !replay_consume_direct) begin
                replay_msg_type_q <= replay_meta_msg_type;
                replay_order_id_q <= replay_meta_order_id;
                replay_report_seq_q <= replay_meta_report_seq;
                replay_position_effect_q <= replay_meta_position_effect;
                replay_before_qty_q <= replay_meta_before_qty;
                replay_meta_available <= 1'b1;
            end
        end
    end

    initial begin
        if(QTY_W < 16) $error("QTY_W must be >= 16 for TAIFEX quantity fields");
    end
endmodule
