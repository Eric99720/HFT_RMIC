`timescale 1ns/1ps
`include "hft_rmic_contract.svh"

// Frozen-HFT-facing CL2EX risk gate.
//
// Mapping/adapter/policy are purely front-end decisions.  The original 256-bit
// HFT order payload is never rewritten; it is returned byte-for-byte only when
// the atomic admission controller has completed futures RESERVE + AMU INSERT.
module hft_rmic_order_gate_v1 #(
    parameter integer ORDER_WIDTH = `HFT_RMIC_ORDER_WIDTH,
    parameter integer ACCOUNT_MAP_ENTRIES = 16,
    parameter integer PRODUCT_MAP_ENTRIES = 16,
    parameter integer ACCOUNT_MAP_INDEX_W = (ACCOUNT_MAP_ENTRIES <= 1) ? 1 : $clog2(ACCOUNT_MAP_ENTRIES),
    parameter integer PRODUCT_MAP_INDEX_W = (PRODUCT_MAP_ENTRIES <= 1) ? 1 : $clog2(PRODUCT_MAP_ENTRIES),
    parameter integer QTY_W = 16,
    parameter integer ENABLE_HOT_MAP_CACHE = 0
) (
    input  wire clk,
    input  wire rst_n,

    input  wire integration_ready,
    input  wire accounting_ready,
    input  wire global_kill,
    input  wire [255:0] order_type_allow_mask,
    input  wire [255:0] tif_allow_mask,
    input  wire [255:0] position_effect_allow_mask,

    // Host-configured Investor Account -> compact account ID map.
    input  wire                         account_cfg_we,
    input  wire [ACCOUNT_MAP_INDEX_W-1:0] account_cfg_index,
    input  wire                         account_cfg_valid,
    input  wire [31:0]                  account_cfg_key,
    input  wire [7:0]                   account_cfg_value,

    // Host-configured frozen HFT symbol-slot -> compact product ID map.
    input  wire                         product_cfg_we,
    input  wire [PRODUCT_MAP_INDEX_W-1:0] product_cfg_index,
    input  wire                         product_cfg_valid,
    input  wire [15:0]                  product_cfg_key,
    input  wire [7:0]                   product_cfg_value,
    input  wire [31:0]                  hot_account_key,
    input  wire [15:0]                  hot_product_key,

    input  wire                         order_valid,
    output wire                         order_ready,
    input  wire [ORDER_WIDTH-1:0]       order_data,

    output wire                         result_valid,
    input  wire                         result_ready,
    output wire                         result_accepted,
    output wire [1:0]                   result_reason_source,
    output wire [7:0]                   result_reason_code,
    output wire [31:0]                  result_order_id,
    output wire [ORDER_WIDTH-1:0]       result_order_data,

    // Exclusive state-manager client from admission controller.
    output wire                         acct_req_valid,
    input  wire                         acct_req_ready,
    output wire [7:0]                   acct_req_account_id,
    output wire [7:0]                   acct_req_product_id,
    output wire [2:0]                   acct_req_event_kind,
    output wire                         acct_req_side,
    output wire [7:0]                   acct_req_position_effect,
    output wire [QTY_W-1:0]             acct_req_order_qty,
    output wire [QTY_W-1:0]             acct_req_fill_qty,
    output wire [QTY_W-1:0]             acct_req_release_qty,
    input  wire                         acct_rsp_valid,
    output wire                         acct_rsp_ready,
    input  wire                         acct_rsp_ok,
    input  wire [1:0]                   acct_rsp_reason_source,
    input  wire [7:0]                   acct_rsp_reason_code,

    // Exclusive order-context-store client from admission controller.
    output wire                         store_req_valid,
    input  wire                         store_req_ready,
    output wire [1:0]                   store_req_op,
    output wire [31:0]                  store_req_order_id,
    output wire [7:0]                   store_req_account_id,
    output wire [7:0]                   store_req_product_id,
    output wire                         store_req_side,
    output wire [7:0]                   store_req_position_effect,
    output wire [7:0]                   store_req_order_type,
    output wire [7:0]                   store_req_tif,
    output wire [31:0]                  store_req_limit_price,
    output wire [QTY_W-1:0]             store_req_remaining_qty,
    input  wire                         store_rsp_valid,
    output wire                         store_rsp_ready,
    input  wire                         store_rsp_ok,
    input  wire                         store_rsp_found,
    input  wire [2:0]                   store_rsp_status
);
    wire [31:0] investor_account;
    wire [15:0] symbol_slot;

    wire account_map_hit;
    wire account_map_ambiguous;
    wire [7:0] account_map_value;
    wire product_map_hit;
    wire product_map_ambiguous;
    wire [7:0] product_map_value;

    wire account_cache_ready;
    wire product_cache_ready;

    generate
        if (ENABLE_HOT_MAP_CACHE != 0) begin : g_hot_map_cache
            hft_rmic_cached_exact_map_v1 #(.KEY_W(32),.VALUE_W(8),.ENTRIES(ACCOUNT_MAP_ENTRIES),.INDEX_W(ACCOUNT_MAP_INDEX_W)) u_account_map (
                .clk(clk),.rst_n(rst_n),.cfg_we(account_cfg_we),.cfg_index(account_cfg_index),
                .cfg_valid(account_cfg_valid),.cfg_key(account_cfg_key),.cfg_value(account_cfg_value),
                .hot_key(hot_account_key),.lookup_key(investor_account),.cache_ready(account_cache_ready),
                .lookup_hit(account_map_hit),.lookup_ambiguous(account_map_ambiguous),.lookup_value(account_map_value));
            hft_rmic_cached_exact_map_v1 #(.KEY_W(16),.VALUE_W(8),.ENTRIES(PRODUCT_MAP_ENTRIES),.INDEX_W(PRODUCT_MAP_INDEX_W)) u_product_map (
                .clk(clk),.rst_n(rst_n),.cfg_we(product_cfg_we),.cfg_index(product_cfg_index),
                .cfg_valid(product_cfg_valid),.cfg_key(product_cfg_key),.cfg_value(product_cfg_value),
                .hot_key(hot_product_key),.lookup_key(symbol_slot),.cache_ready(product_cache_ready),
                .lookup_hit(product_map_hit),.lookup_ambiguous(product_map_ambiguous),.lookup_value(product_map_value));
        end else begin : g_direct_map
            configurable_exact_map #(.KEY_W(32),.VALUE_W(8),.ENTRIES(ACCOUNT_MAP_ENTRIES)) u_account_map (
                .clk(clk),.rst_n(rst_n),.cfg_we(account_cfg_we),.cfg_index(account_cfg_index),
                .cfg_valid(account_cfg_valid),.cfg_key(account_cfg_key),.cfg_value(account_cfg_value),
                .lookup_key(investor_account),.lookup_hit(account_map_hit),
                .lookup_ambiguous(account_map_ambiguous),.lookup_value(account_map_value));
            configurable_exact_map #(.KEY_W(16),.VALUE_W(8),.ENTRIES(PRODUCT_MAP_ENTRIES)) u_product_map (
                .clk(clk),.rst_n(rst_n),.cfg_we(product_cfg_we),.cfg_index(product_cfg_index),
                .cfg_valid(product_cfg_valid),.cfg_key(product_cfg_key),.cfg_value(product_cfg_value),
                .lookup_key(symbol_slot),.lookup_hit(product_map_hit),
                .lookup_ambiguous(product_map_ambiguous),.lookup_value(product_map_value));
            assign account_cache_ready = 1'b1;
            assign product_cache_ready = 1'b1;
        end
    endgenerate

    wire [31:0] normalized_order_id;
    wire [7:0] normalized_account_id;
    wire [7:0] normalized_product_id;
    wire normalized_side;
    wire [31:0] normalized_price;
    wire [31:0] normalized_qty32;
    wire [7:0] policy_tif;
    wire [7:0] policy_position_effect;
    wire [7:0] policy_investor_flag;
    wire [7:0] policy_flags;
    wire [7:0] policy_order_type;
    wire [39:0] order_number_unused;
    wire [7:0] packed_side_unused;
    wire side_valid;
    wire account_valid_unused;
    wire product_valid_unused;
    wire adapter_valid_unused;

    hft_order_to_rmic #(.ORDER_WIDTH(ORDER_WIDTH)) u_adapter (
        .order_data(order_data),
        .account_map_hit(account_map_hit),
        .account_map_ambiguous(account_map_ambiguous),
        .account_map_value(account_map_value),
        .product_map_hit(product_map_hit),
        .product_map_ambiguous(product_map_ambiguous),
        .product_map_value(product_map_value),
        .rmic_order_id(normalized_order_id),
        .rmic_account_id(normalized_account_id),
        .rmic_product_id(normalized_product_id),
        .rmic_side(normalized_side),
        .rmic_price(normalized_price),
        .rmic_qty(normalized_qty32),
        .policy_tif(policy_tif),
        .policy_position_effect(policy_position_effect),
        .policy_investor_flag(policy_investor_flag),
        .policy_flags(policy_flags),
        .policy_order_type(policy_order_type),
        .investor_account(investor_account),
        .order_number(order_number_unused),
        .symbol_slot(symbol_slot),
        .packed_side_byte(packed_side_unused),
        .side_valid(side_valid),
        .account_valid(account_valid_unused),
        .product_valid(product_valid_unused),
        .adapter_valid(adapter_valid_unused)
    );

    // Frozen order_data physically carries uint16 quantity; the adapter
    // zero-extends it.  I3 intentionally binds the futures state/store to the
    // same 16-bit TMP quantity contract.
    wire qty_width_valid = (normalized_qty32[31:16] == 16'd0);
    wire policy_pass;
    wire [1:0] policy_reason_source;
    wire [7:0] policy_reason_code;

    hft_rmic_policy_gate u_policy (
        .integration_ready(integration_ready),
        .accounting_ready(accounting_ready),
        .global_kill(global_kill),
        .side_valid(side_valid),
        .account_map_hit(account_map_hit),
        .account_map_ambiguous(account_map_ambiguous),
        .product_map_hit(product_map_hit),
        .product_map_ambiguous(product_map_ambiguous),
        .qty_width_valid(qty_width_valid),
        .order_type(policy_order_type),
        .tif(policy_tif),
        .position_effect(policy_position_effect),
        .order_type_allow_mask(order_type_allow_mask),
        .tif_allow_mask(tif_allow_mask),
        .position_effect_allow_mask(position_effect_allow_mask),
        .policy_pass(policy_pass),
        .reason_source(policy_reason_source),
        .reason_code(policy_reason_code)
    );

    wire admission_order_ready;
    wire config_quiet = !account_cfg_we && !product_cfg_we &&
                        account_cache_ready && product_cache_ready;
    assign order_ready = admission_order_ready && config_quiet;

    hft_rmic_cl2ex_admission_v1 #(
        .ORDER_WIDTH(ORDER_WIDTH), .QTY_W(QTY_W)
    ) u_admission (
        .clk(clk), .rst_n(rst_n),
        .order_valid(order_valid && config_quiet),
        .order_ready(admission_order_ready),
        .order_data(order_data),
        .policy_pass(policy_pass),
        .policy_reason_source(policy_reason_source),
        .policy_reason_code(policy_reason_code),
        .order_id(normalized_order_id),
        .account_id(normalized_account_id),
        .product_id(normalized_product_id),
        .side(normalized_side),
        .position_effect(policy_position_effect),
        .order_type(policy_order_type),
        .tif(policy_tif),
        .limit_price(normalized_price),
        .qty(normalized_qty32[QTY_W-1:0]),
        .result_valid(result_valid), .result_ready(result_ready),
        .result_accepted(result_accepted),
        .result_reason_source(result_reason_source),
        .result_reason_code(result_reason_code),
        .result_order_id(result_order_id),
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

    initial begin
        if (QTY_W != 16)
            $error("hft_rmic_order_gate_v1 QTY_W must match frozen TMP uint16 quantity");
    end
endmodule
