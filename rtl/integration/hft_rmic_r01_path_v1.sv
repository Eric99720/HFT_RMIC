`timescale 1ns/1ps

// I4 focused R01 integration path.
//
// Both frozen-HFT order_data producers (ordinary bridge and R01 prebuild) enter
// one prebuild-priority source mux, then one shared futures risk core.  Only the
// accepted original 256-bit payload is presented to the frozen financial
// protocol encoder.  R04/R05/session behavior is intentionally not recreated
// here; this focused composition establishes the exact order->risk->R01 data
// boundary before the later full app-top integration.
module hft_rmic_r01_path_v1 #(
    parameter integer ORDER_WIDTH = 256,
    parameter integer DATA_WIDTH = 64,
    parameter integer QTY_W = 16,
    parameter integer MARGIN_W = 64
) (
    input  wire clk,
    input  wire rst_n,

    // Frozen HFT order producers.
    input  wire legacy_order_valid,
    output wire legacy_order_ready,
    input  wire [ORDER_WIDTH-1:0] legacy_order_data,
    input  wire prebuild_order_valid,
    output wire prebuild_order_accept,
    input  wire [ORDER_WIDTH-1:0] prebuild_order_data,

    // Risk/policy/configuration.
    input  wire integration_ready,
    input  wire accounting_ready,
    input  wire global_kill,
    input  wire recovery_clear,
    output wire recovery_required,
    output wire store_init_done,
    output wire [1:0] transaction_owner,
    input  wire [255:0] order_type_allow_mask,
    input  wire [255:0] tif_allow_mask,
    input  wire [255:0] position_effect_allow_mask,

    input  wire account_cfg_we,
    input  wire [3:0] account_cfg_index,
    input  wire account_cfg_valid,
    input  wire [31:0] account_cfg_key,
    input  wire [7:0] account_cfg_value,
    input  wire product_cfg_we,
    input  wire [3:0] product_cfg_index,
    input  wire product_cfg_valid,
    input  wire [15:0] product_cfg_key,
    input  wire [7:0] product_cfg_value,

    input  wire cfg_valid,
    output wire cfg_ready,
    input  wire [7:0] cfg_account_id,
    input  wire [7:0] cfg_product_id,
    input  wire cfg_enabled,
    input  wire [MARGIN_W-1:0] cfg_margin_budget,
    input  wire [MARGIN_W-1:0] cfg_margin_per_contract,
    input  wire [QTY_W-1:0] cfg_long_position,
    input  wire [QTY_W-1:0] cfg_short_position,
    input  wire [QTY_W-1:0] cfg_pending_open_long,
    input  wire [QTY_W-1:0] cfg_pending_open_short,
    input  wire [QTY_W-1:0] cfg_reserved_close_long,
    input  wire [QTY_W-1:0] cfg_reserved_close_short,
    output wire cfg_done,
    output wire cfg_ok,
    output wire [7:0] cfg_reason_code,

    // Committed execution feedback.
    input  wire exec_commit_valid,
    output wire exec_commit_ready,
    input  wire [7:0] exec_commit_msg_type,
    input  wire [7:0] exec_commit_status_code,
    input  wire [7:0] exec_commit_exec_type,
    input  wire [31:0] exec_commit_order_id,
    input  wire exec_commit_side,
    input  wire [7:0] exec_commit_position_effect,
    input  wire [31:0] exec_commit_order_price,
    input  wire [QTY_W-1:0] exec_commit_last_qty,
    input  wire [QTY_W-1:0] exec_commit_leaves_qty,
    input  wire [QTY_W-1:0] exec_commit_before_qty,
    output wire exec_result_valid,
    input  wire exec_result_ready,
    output wire exec_result_ok,
    output wire [1:0] exec_result_reason_source,
    output wire [7:0] exec_result_reason_code,
    output wire [31:0] exec_result_order_id,
    output wire [QTY_W-1:0] exec_result_remaining_qty,

    // Local risk reject telemetry.
    output wire risk_reject_valid,
    input  wire risk_reject_ready,
    output wire [31:0] risk_reject_order_id,
    output wire [1:0] risk_reject_reason_source,
    output wire [7:0] risk_reject_reason_code,

    // Frozen R01 encoder metadata.
    input  wire [31:0] msg_epoch_s,
    input  wire [15:0] msg_ms,
    input  wire [15:0] fcm_id,
    input  wire [15:0] session_id,
    input  wire [15:0] cm_id,
    input  wire [15:0] body_fcm_id,
    input  wire [63:0] user_define,
    input  wire [159:0] symbol_text,
    input  wire [7:0] order_source,
    input  wire [23:0] info_source,
    input  wire [31:0] r01_msg_seq_num,
    input  wire network_ready,

    output wire [DATA_WIDTH-1:0] tx_data,
    output wire [(DATA_WIDTH/8)-1:0] tx_keep,
    output wire tx_valid,
    input  wire tx_ready,
    output wire tx_last,
    output wire [15:0] tx_payload_len,
    output wire tx_complete,
    output wire [7:0] tx_message_type,
    output wire [31:0] encoder_accepted_order_count,
    output wire [31:0] encoder_sent_r01_count
);
    wire risk_source_valid, risk_source_ready;
    wire [ORDER_WIDTH-1:0] risk_source_data;
    wire source_prebuild_unused;

    hft_rmic_dual_order_source_v1 #(.ORDER_WIDTH(ORDER_WIDTH)) u_source_mux (
        .legacy_valid(legacy_order_valid), .legacy_ready(legacy_order_ready),
        .legacy_data(legacy_order_data), .prebuild_valid(prebuild_order_valid),
        .prebuild_accept(prebuild_order_accept), .prebuild_data(prebuild_order_data),
        .risk_valid(risk_source_valid), .risk_ready(risk_source_ready),
        .risk_data(risk_source_data), .risk_source_prebuild(source_prebuild_unused)
    );

    wire accepted_order_valid, accepted_order_ready;
    wire [ORDER_WIDTH-1:0] accepted_order_data;
    wire [31:0] accepted_order_id_unused;

    hft_rmic_shared_core_v1 #(.ORDER_WIDTH(ORDER_WIDTH), .QTY_W(QTY_W), .MARGIN_W(MARGIN_W)) u_risk (
        .clk(clk), .rst_n(rst_n),
        .integration_ready(integration_ready), .accounting_ready(accounting_ready),
        .global_kill(global_kill), .recovery_clear(recovery_clear),
        .recovery_required(recovery_required), .store_init_done(store_init_done),
        .transaction_owner(transaction_owner),
        .order_type_allow_mask(order_type_allow_mask), .tif_allow_mask(tif_allow_mask),
        .position_effect_allow_mask(position_effect_allow_mask),
        .account_cfg_we(account_cfg_we), .account_cfg_index(account_cfg_index),
        .account_cfg_valid(account_cfg_valid), .account_cfg_key(account_cfg_key),
        .account_cfg_value(account_cfg_value), .product_cfg_we(product_cfg_we),
        .product_cfg_index(product_cfg_index), .product_cfg_valid(product_cfg_valid),
        .product_cfg_key(product_cfg_key), .product_cfg_value(product_cfg_value),
        .cfg_valid(cfg_valid), .cfg_ready(cfg_ready), .cfg_account_id(cfg_account_id),
        .cfg_product_id(cfg_product_id), .cfg_enabled(cfg_enabled),
        .cfg_margin_budget(cfg_margin_budget), .cfg_margin_per_contract(cfg_margin_per_contract),
        .cfg_long_position(cfg_long_position), .cfg_short_position(cfg_short_position),
        .cfg_pending_open_long(cfg_pending_open_long), .cfg_pending_open_short(cfg_pending_open_short),
        .cfg_reserved_close_long(cfg_reserved_close_long), .cfg_reserved_close_short(cfg_reserved_close_short),
        .cfg_done(cfg_done), .cfg_ok(cfg_ok), .cfg_reason_code(cfg_reason_code),
        .order_valid(risk_source_valid), .order_ready(risk_source_ready), .order_data(risk_source_data),
        .accepted_order_valid(accepted_order_valid), .accepted_order_ready(accepted_order_ready),
        .accepted_order_data(accepted_order_data), .accepted_order_id(accepted_order_id_unused),
        .reject_valid(risk_reject_valid), .reject_ready(risk_reject_ready),
        .reject_order_id(risk_reject_order_id), .reject_reason_source(risk_reject_reason_source),
        .reject_reason_code(risk_reject_reason_code),
        .exec_commit_valid(exec_commit_valid), .exec_commit_ready(exec_commit_ready),
        .exec_commit_msg_type(exec_commit_msg_type), .exec_commit_status_code(exec_commit_status_code),
        .exec_commit_exec_type(exec_commit_exec_type), .exec_commit_order_id(exec_commit_order_id),
        .exec_commit_side(exec_commit_side), .exec_commit_position_effect(exec_commit_position_effect),
        .exec_commit_order_price(exec_commit_order_price), .exec_commit_last_qty(exec_commit_last_qty),
        .exec_commit_leaves_qty(exec_commit_leaves_qty), .exec_commit_before_qty(exec_commit_before_qty),
        .exec_result_valid(exec_result_valid), .exec_result_ready(exec_result_ready),
        .exec_result_ok(exec_result_ok), .exec_result_reason_source(exec_result_reason_source),
        .exec_result_reason_code(exec_result_reason_code), .exec_result_order_id(exec_result_order_id),
        .exec_result_remaining_qty(exec_result_remaining_qty)
    );

    wire fifo_full_unused, fifo_empty_unused, encoder_busy_unused, payload_active_unused;
    wire error_overflow_unused;
    wire [31:0] sent_order_unused, sent_r05_unused, sent_r04_unused, dropped_unused;
    wire [31:0] r01_sum_unused;
    wire r01_sum_valid_unused;
    wire manual_ready_unused, r04_ready_unused, local_r04_ready_unused;

    financial_protocol_encoder #(
        .ORDER_WIDTH(ORDER_WIDTH), .DATA_WIDTH(DATA_WIDTH),
        .ALLOW_STRATEGY_BYPASS_WITHOUT_TX_READY(1'b0),
        .ENABLE_TMP_MAINTENANCE(1'b0), .ENABLE_TMP_FLOW_CONTROL(1'b0)
    ) u_frozen_encoder (
        .clk(clk), .rst(~rst_n),
        .manual_order_valid(1'b0), .manual_order_ready(manual_ready_unused),
        .manual_order_data({ORDER_WIDTH{1'b0}}),
        .strategy_order_valid(accepted_order_valid),
        .strategy_order_ready(accepted_order_ready),
        .strategy_order_data(accepted_order_data),
        .r04_valid(1'b0), .r04_ready(r04_ready_unused),
        .local_r04_valid(1'b0), .local_r04_ready(local_r04_ready_unused),
        .ordinary_credit_available(1'b1),
        .msg_epoch_s(msg_epoch_s), .msg_ms(msg_ms), .fcm_id(fcm_id),
        .session_id(session_id), .cm_id(cm_id), .body_fcm_id(body_fcm_id),
        .user_define(user_define), .symbol_text(symbol_text), .order_source(order_source),
        .info_source(info_source), .r01_msg_seq_num(r01_msg_seq_num),
        .network_ready(network_ready),
        .tx_data(tx_data), .tx_keep(tx_keep), .tx_valid(tx_valid), .tx_ready(tx_ready),
        .tx_last(tx_last), .tx_payload_len(tx_payload_len), .tx_complete(tx_complete),
        .tx_message_type(tx_message_type),
        .fifo_full(fifo_full_unused), .fifo_empty(fifo_empty_unused),
        .encoder_busy(encoder_busy_unused), .payload_active(payload_active_unused),
        .error_overflow(error_overflow_unused),
        .accepted_order_count(encoder_accepted_order_count),
        .sent_order_count(sent_order_unused), .sent_r01_count(encoder_sent_r01_count),
        .sent_r05_count(sent_r05_unused), .sent_r04_count(sent_r04_unused),
        .dropped_order_count(dropped_unused),
        .r01_tcp_payload_sum(r01_sum_unused), .r01_tcp_payload_sum_valid(r01_sum_valid_unused)
    );
endmodule
