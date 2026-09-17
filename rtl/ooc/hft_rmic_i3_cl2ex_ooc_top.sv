`timescale 1ns/1ps

// I3 physical-composition harness only.
//
// Composes the frozen-HFT-facing order gate with the real pinned RMIC AMU and
// the pipelined futures state manager.  This measures atomic CL2EX admission at
// 156.25 MHz; it is not the final HFT top and contains no network/TMP encoder.
module hft_rmic_i3_cl2ex_ooc_top #(
    parameter integer QTY_W = 16,
    parameter integer MARGIN_W = 64,
    parameter integer ACCOUNT_MAP_ENTRIES = 16,
    parameter integer PRODUCT_MAP_ENTRIES = 16
) (
    input  wire clk,
    input  wire rst_n,

    input  wire integration_ready,
    input  wire accounting_ready,
    input  wire global_kill,
    input  wire [255:0] order_type_allow_mask,
    input  wire [255:0] tif_allow_mask,
    input  wire [255:0] position_effect_allow_mask,

    input  wire account_cfg_we,
    input  wire [$clog2(ACCOUNT_MAP_ENTRIES)-1:0] account_cfg_index,
    input  wire account_cfg_valid,
    input  wire [31:0] account_cfg_key,
    input  wire [7:0] account_cfg_value,

    input  wire product_cfg_we,
    input  wire [$clog2(PRODUCT_MAP_ENTRIES)-1:0] product_cfg_index,
    input  wire product_cfg_valid,
    input  wire [15:0] product_cfg_key,
    input  wire [7:0] product_cfg_value,

    // Futures state host/recovery configuration.
    input  wire state_cfg_valid,
    output wire state_cfg_ready,
    input  wire [7:0] state_cfg_account_id,
    input  wire [7:0] state_cfg_product_id,
    input  wire state_cfg_enabled,
    input  wire [MARGIN_W-1:0] state_cfg_margin_budget,
    input  wire [MARGIN_W-1:0] state_cfg_margin_per_contract,
    input  wire [QTY_W-1:0] state_cfg_long_position,
    input  wire [QTY_W-1:0] state_cfg_short_position,
    input  wire [QTY_W-1:0] state_cfg_pending_open_long,
    input  wire [QTY_W-1:0] state_cfg_pending_open_short,
    input  wire [QTY_W-1:0] state_cfg_reserved_close_long,
    input  wire [QTY_W-1:0] state_cfg_reserved_close_short,
    output wire state_cfg_done,
    output wire state_cfg_ok,
    output wire [7:0] state_cfg_reason_code,

    input  wire order_valid,
    output wire order_ready,
    input  wire [255:0] order_data,
    output wire result_valid,
    input  wire result_ready,
    output wire result_accepted,
    output wire [1:0] result_reason_source,
    output wire [7:0] result_reason_code,
    output wire [31:0] result_order_id,
    output wire [255:0] result_order_data,
    output wire store_init_done
);
    wire acct_req_valid, acct_req_ready;
    wire [7:0] acct_req_account_id, acct_req_product_id;
    wire [2:0] acct_req_event_kind;
    wire acct_req_side;
    wire [7:0] acct_req_position_effect;
    wire [QTY_W-1:0] acct_req_order_qty, acct_req_fill_qty, acct_req_release_qty;
    wire acct_rsp_valid, acct_rsp_ready, acct_rsp_ok;
    wire [1:0] acct_rsp_reason_source;
    wire [7:0] acct_rsp_reason_code;

    wire store_req_valid, store_req_ready;
    wire [1:0] store_req_op;
    wire [31:0] store_req_order_id;
    wire [7:0] store_req_account_id, store_req_product_id;
    wire store_req_side;
    wire [7:0] store_req_position_effect, store_req_order_type, store_req_tif;
    wire [31:0] store_req_limit_price;
    wire [QTY_W-1:0] store_req_remaining_qty;
    wire store_rsp_valid, store_rsp_ready, store_rsp_ok, store_rsp_found;
    wire [2:0] store_rsp_status;

    hft_rmic_order_gate_v1 #(
        .ACCOUNT_MAP_ENTRIES(ACCOUNT_MAP_ENTRIES),
        .PRODUCT_MAP_ENTRIES(PRODUCT_MAP_ENTRIES),
        .QTY_W(QTY_W)
    ) u_gate (
        .clk(clk), .rst_n(rst_n),
        .integration_ready(integration_ready), .accounting_ready(accounting_ready),
        .global_kill(global_kill),
        .order_type_allow_mask(order_type_allow_mask), .tif_allow_mask(tif_allow_mask),
        .position_effect_allow_mask(position_effect_allow_mask),
        .account_cfg_we(account_cfg_we), .account_cfg_index(account_cfg_index),
        .account_cfg_valid(account_cfg_valid), .account_cfg_key(account_cfg_key),
        .account_cfg_value(account_cfg_value),
        .product_cfg_we(product_cfg_we), .product_cfg_index(product_cfg_index),
        .product_cfg_valid(product_cfg_valid), .product_cfg_key(product_cfg_key),
        .product_cfg_value(product_cfg_value),
        .order_valid(order_valid), .order_ready(order_ready), .order_data(order_data),
        .result_valid(result_valid), .result_ready(result_ready),
        .result_accepted(result_accepted), .result_reason_source(result_reason_source),
        .result_reason_code(result_reason_code), .result_order_id(result_order_id),
        .result_order_data(result_order_data),
        .acct_req_valid(acct_req_valid), .acct_req_ready(acct_req_ready),
        .acct_req_account_id(acct_req_account_id), .acct_req_product_id(acct_req_product_id),
        .acct_req_event_kind(acct_req_event_kind), .acct_req_side(acct_req_side),
        .acct_req_position_effect(acct_req_position_effect),
        .acct_req_order_qty(acct_req_order_qty), .acct_req_fill_qty(acct_req_fill_qty),
        .acct_req_release_qty(acct_req_release_qty),
        .acct_rsp_valid(acct_rsp_valid), .acct_rsp_ready(acct_rsp_ready),
        .acct_rsp_ok(acct_rsp_ok), .acct_rsp_reason_source(acct_rsp_reason_source),
        .acct_rsp_reason_code(acct_rsp_reason_code),
        .store_req_valid(store_req_valid), .store_req_ready(store_req_ready),
        .store_req_op(store_req_op), .store_req_order_id(store_req_order_id),
        .store_req_account_id(store_req_account_id), .store_req_product_id(store_req_product_id),
        .store_req_side(store_req_side), .store_req_position_effect(store_req_position_effect),
        .store_req_order_type(store_req_order_type), .store_req_tif(store_req_tif),
        .store_req_limit_price(store_req_limit_price),
        .store_req_remaining_qty(store_req_remaining_qty),
        .store_rsp_valid(store_rsp_valid), .store_rsp_ready(store_rsp_ready),
        .store_rsp_ok(store_rsp_ok), .store_rsp_found(store_rsp_found),
        .store_rsp_status(store_rsp_status)
    );

    hft_rmic_futures_state_manager_v1 #(
        .NUM_ACCOUNTS(16), .NUM_PRODUCTS(16), .QTY_W(QTY_W), .MARGIN_W(MARGIN_W)
    ) u_state (
        .clk(clk), .rst_n(rst_n),
        .cfg_valid(state_cfg_valid), .cfg_ready(state_cfg_ready),
        .cfg_account_id(state_cfg_account_id), .cfg_product_id(state_cfg_product_id),
        .cfg_enabled(state_cfg_enabled), .cfg_margin_budget(state_cfg_margin_budget),
        .cfg_margin_per_contract(state_cfg_margin_per_contract),
        .cfg_long_position(state_cfg_long_position), .cfg_short_position(state_cfg_short_position),
        .cfg_pending_open_long(state_cfg_pending_open_long),
        .cfg_pending_open_short(state_cfg_pending_open_short),
        .cfg_reserved_close_long(state_cfg_reserved_close_long),
        .cfg_reserved_close_short(state_cfg_reserved_close_short),
        .cfg_done(state_cfg_done), .cfg_ok(state_cfg_ok), .cfg_reason_code(state_cfg_reason_code),
        .req_valid(acct_req_valid), .req_ready(acct_req_ready),
        .req_account_id(acct_req_account_id), .req_product_id(acct_req_product_id),
        .req_event_kind(acct_req_event_kind), .req_side(acct_req_side),
        .req_position_effect(acct_req_position_effect), .req_order_qty(acct_req_order_qty),
        .req_fill_qty(acct_req_fill_qty), .req_release_qty(acct_req_release_qty),
        .rsp_valid(acct_rsp_valid), .rsp_ready(acct_rsp_ready), .rsp_ok(acct_rsp_ok),
        .rsp_reason_source(acct_rsp_reason_source), .rsp_reason_code(acct_rsp_reason_code),
        .rsp_account_id(), .rsp_product_id(), .rsp_entry_enabled(),
        .rsp_long_position(), .rsp_short_position(), .rsp_pending_open_long(),
        .rsp_pending_open_short(), .rsp_reserved_close_long(), .rsp_reserved_close_short(),
        .rsp_required_margin_before(), .rsp_required_margin_after()
    );

    wire [7:0] store_rsp_account_unused, store_rsp_product_unused;
    wire store_rsp_side_unused;
    wire [7:0] store_rsp_pe_unused, store_rsp_type_unused, store_rsp_tif_unused;
    wire [31:0] store_rsp_price_unused;
    wire [QTY_W-1:0] store_rsp_qty_unused;
    wire [2:0] store_rsp_bank_unused;
    wire store_rsp_stash_unused;

    hft_rmic_futures_order_store_v1 #(.QTY_W(QTY_W)) u_store (
        .clk(clk), .rst_n(rst_n),
        .req_valid(store_req_valid), .req_ready(store_req_ready), .req_op(store_req_op),
        .req_order_id(store_req_order_id), .req_account_id(store_req_account_id),
        .req_product_id(store_req_product_id), .req_side(store_req_side),
        .req_position_effect(store_req_position_effect), .req_order_type(store_req_order_type),
        .req_tif(store_req_tif), .req_limit_price(store_req_limit_price),
        .req_remaining_qty(store_req_remaining_qty),
        .rsp_valid(store_rsp_valid), .rsp_ready(store_rsp_ready), .rsp_ok(store_rsp_ok),
        .rsp_found(store_rsp_found), .rsp_status(store_rsp_status),
        .rsp_account_id(store_rsp_account_unused), .rsp_product_id(store_rsp_product_unused),
        .rsp_side(store_rsp_side_unused), .rsp_position_effect(store_rsp_pe_unused),
        .rsp_order_type(store_rsp_type_unused), .rsp_tif(store_rsp_tif_unused),
        .rsp_limit_price(store_rsp_price_unused), .rsp_remaining_qty(store_rsp_qty_unused),
        .rsp_bank(store_rsp_bank_unused), .rsp_in_stash(store_rsp_stash_unused),
        .init_done(store_init_done)
    );
endmodule
