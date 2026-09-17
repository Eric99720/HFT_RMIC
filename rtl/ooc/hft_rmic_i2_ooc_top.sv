`timescale 1ns/1ps

// I2 physical-composition harness only.
//
// This is NOT the final HFT production top. It composes the real pinned RMIC
// AMU-backed futures order store, futures state manager and committed execution
// bridge so Vivado can measure resource/timing closure at 156.25 MHz.
//
// external_mode is a lab/OOC ownership selector. Keep it stable for an entire
// request/response transaction. Production arbitration is introduced only in
// the later full HFT integration phase.
module hft_rmic_i2_ooc_top #(
    parameter integer QTY_W = 16,
    parameter integer MARGIN_W = 64
) (
    input  wire clk,
    input  wire rst_n,
    input  wire external_mode,

    // State configuration/recovery.
    input  wire        cfg_valid,
    output wire        cfg_ready,
    input  wire [7:0]  cfg_account_id,
    input  wire [7:0]  cfg_product_id,
    input  wire        cfg_enabled,
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

    // OOC external order-store client. Runtime op keeps LOOKUP/INSERT/DELETE/
    // UPDATE logic physically reachable during synthesis.
    input  wire ext_store_req_valid,
    output wire ext_store_req_ready,
    input  wire [1:0] ext_store_req_op,
    input  wire [31:0] ext_store_req_order_id,
    input  wire [7:0] ext_store_req_account_id,
    input  wire [7:0] ext_store_req_product_id,
    input  wire ext_store_req_side,
    input  wire [7:0] ext_store_req_position_effect,
    input  wire [7:0] ext_store_req_order_type,
    input  wire [7:0] ext_store_req_tif,
    input  wire [31:0] ext_store_req_limit_price,
    input  wire [QTY_W-1:0] ext_store_req_remaining_qty,
    output wire ext_store_rsp_valid,
    input  wire ext_store_rsp_ready,
    output wire ext_store_rsp_ok,
    output wire ext_store_rsp_found,
    output wire [2:0] ext_store_rsp_status,
    output wire [QTY_W-1:0] ext_store_rsp_remaining_qty,
    output wire store_init_done,

    // OOC external account-state client. Runtime event keeps reserve/fill/
    // release/query logic physically reachable during synthesis.
    input  wire ext_acct_req_valid,
    output wire ext_acct_req_ready,
    input  wire [7:0] ext_acct_req_account_id,
    input  wire [7:0] ext_acct_req_product_id,
    input  wire [2:0] ext_acct_req_event_kind,
    input  wire ext_acct_req_side,
    input  wire [7:0] ext_acct_req_position_effect,
    input  wire [QTY_W-1:0] ext_acct_req_order_qty,
    input  wire [QTY_W-1:0] ext_acct_req_fill_qty,
    input  wire [QTY_W-1:0] ext_acct_req_release_qty,
    output wire ext_acct_rsp_valid,
    input  wire ext_acct_rsp_ready,
    output wire ext_acct_rsp_ok,
    output wire [1:0] ext_acct_rsp_reason_source,
    output wire [7:0] ext_acct_rsp_reason_code,

    // Committed execution/error event.
    input  wire commit_valid,
    output wire commit_ready,
    input  wire [7:0] commit_msg_type,
    input  wire [7:0] commit_status_code,
    input  wire [7:0] commit_exec_type,
    input  wire [31:0] commit_order_id,
    input  wire commit_side,
    input  wire [7:0] commit_position_effect,
    input  wire [31:0] commit_order_price,
    input  wire [QTY_W-1:0] commit_last_qty,
    input  wire [QTY_W-1:0] commit_leaves_qty,
    input  wire [QTY_W-1:0] commit_before_qty,
    output wire result_valid,
    input  wire result_ready,
    output wire result_ok,
    output wire [1:0] result_reason_source,
    output wire [7:0] result_reason_code,
    output wire [31:0] result_order_id,
    output wire [QTY_W-1:0] result_remaining_qty
);
    // Bridge-side order-store interface.
    wire br_store_req_valid, br_store_req_ready;
    wire [1:0] br_store_req_op;
    wire [31:0] br_store_req_order_id;
    wire [7:0] br_store_req_account_id, br_store_req_product_id;
    wire br_store_req_side;
    wire [7:0] br_store_req_position_effect, br_store_req_order_type, br_store_req_tif;
    wire [31:0] br_store_req_limit_price;
    wire [QTY_W-1:0] br_store_req_remaining_qty;
    wire br_store_rsp_valid, br_store_rsp_ready, br_store_rsp_ok, br_store_rsp_found;
    wire [2:0] br_store_rsp_status;
    wire [7:0] br_store_rsp_account_id, br_store_rsp_product_id;
    wire br_store_rsp_side;
    wire [7:0] br_store_rsp_position_effect, br_store_rsp_order_type, br_store_rsp_tif;
    wire [31:0] br_store_rsp_limit_price;
    wire [QTY_W-1:0] br_store_rsp_remaining_qty;

    wire store_req_valid = external_mode ? ext_store_req_valid : br_store_req_valid;
    wire [1:0] store_req_op = external_mode ? ext_store_req_op : br_store_req_op;
    wire [31:0] store_req_order_id = external_mode ? ext_store_req_order_id : br_store_req_order_id;
    wire [7:0] store_req_account_id = external_mode ? ext_store_req_account_id : br_store_req_account_id;
    wire [7:0] store_req_product_id = external_mode ? ext_store_req_product_id : br_store_req_product_id;
    wire store_req_side = external_mode ? ext_store_req_side : br_store_req_side;
    wire [7:0] store_req_position_effect = external_mode ? ext_store_req_position_effect : br_store_req_position_effect;
    wire [7:0] store_req_order_type = external_mode ? ext_store_req_order_type : br_store_req_order_type;
    wire [7:0] store_req_tif = external_mode ? ext_store_req_tif : br_store_req_tif;
    wire [31:0] store_req_limit_price = external_mode ? ext_store_req_limit_price : br_store_req_limit_price;
    wire [QTY_W-1:0] store_req_remaining_qty = external_mode ? ext_store_req_remaining_qty : br_store_req_remaining_qty;
    wire store_rsp_ready = external_mode ? ext_store_rsp_ready : br_store_rsp_ready;
    wire store_req_ready_i, store_rsp_valid_i, store_rsp_ok_i, store_rsp_found_i;
    wire [2:0] store_rsp_status_i;
    wire [7:0] store_rsp_account_id_i, store_rsp_product_id_i;
    wire store_rsp_side_i;
    wire [7:0] store_rsp_position_effect_i, store_rsp_order_type_i, store_rsp_tif_i;
    wire [31:0] store_rsp_limit_price_i;
    wire [QTY_W-1:0] store_rsp_remaining_qty_i;
    wire [2:0] store_rsp_bank_unused;
    wire store_rsp_stash_unused;

    assign ext_store_req_ready = external_mode ? store_req_ready_i : 1'b0;
    assign ext_store_rsp_valid = external_mode ? store_rsp_valid_i : 1'b0;
    assign ext_store_rsp_ok = store_rsp_ok_i;
    assign ext_store_rsp_found = store_rsp_found_i;
    assign ext_store_rsp_status = store_rsp_status_i;
    assign ext_store_rsp_remaining_qty = store_rsp_remaining_qty_i;
    assign br_store_req_ready = external_mode ? 1'b0 : store_req_ready_i;
    assign br_store_rsp_valid = external_mode ? 1'b0 : store_rsp_valid_i;
    assign br_store_rsp_ok = store_rsp_ok_i;
    assign br_store_rsp_found = store_rsp_found_i;
    assign br_store_rsp_status = store_rsp_status_i;
    assign br_store_rsp_account_id = store_rsp_account_id_i;
    assign br_store_rsp_product_id = store_rsp_product_id_i;
    assign br_store_rsp_side = store_rsp_side_i;
    assign br_store_rsp_position_effect = store_rsp_position_effect_i;
    assign br_store_rsp_order_type = store_rsp_order_type_i;
    assign br_store_rsp_tif = store_rsp_tif_i;
    assign br_store_rsp_limit_price = store_rsp_limit_price_i;
    assign br_store_rsp_remaining_qty = store_rsp_remaining_qty_i;

    hft_rmic_futures_order_store_v1 u_store (
        .clk(clk),.rst_n(rst_n),.req_valid(store_req_valid),.req_ready(store_req_ready_i),
        .req_op(store_req_op),.req_order_id(store_req_order_id),.req_account_id(store_req_account_id),
        .req_product_id(store_req_product_id),.req_side(store_req_side),
        .req_position_effect(store_req_position_effect),.req_order_type(store_req_order_type),
        .req_tif(store_req_tif),.req_limit_price(store_req_limit_price),
        .req_remaining_qty(store_req_remaining_qty),.rsp_valid(store_rsp_valid_i),
        .rsp_ready(store_rsp_ready),.rsp_ok(store_rsp_ok_i),.rsp_found(store_rsp_found_i),
        .rsp_status(store_rsp_status_i),.rsp_account_id(store_rsp_account_id_i),
        .rsp_product_id(store_rsp_product_id_i),.rsp_side(store_rsp_side_i),
        .rsp_position_effect(store_rsp_position_effect_i),.rsp_order_type(store_rsp_order_type_i),
        .rsp_tif(store_rsp_tif_i),.rsp_limit_price(store_rsp_limit_price_i),
        .rsp_remaining_qty(store_rsp_remaining_qty_i),.rsp_bank(store_rsp_bank_unused),
        .rsp_in_stash(store_rsp_stash_unused),.init_done(store_init_done)
    );

    // Bridge-side account interface.
    wire br_acct_req_valid, br_acct_req_ready;
    wire [7:0] br_acct_req_account_id, br_acct_req_product_id;
    wire [2:0] br_acct_req_event_kind;
    wire br_acct_req_side;
    wire [7:0] br_acct_req_position_effect;
    wire [QTY_W-1:0] br_acct_req_order_qty, br_acct_req_fill_qty, br_acct_req_release_qty;
    wire br_acct_rsp_valid, br_acct_rsp_ready, br_acct_rsp_ok;
    wire [1:0] br_acct_rsp_reason_source;
    wire [7:0] br_acct_rsp_reason_code;

    wire acct_req_valid = external_mode ? ext_acct_req_valid : br_acct_req_valid;
    wire [7:0] acct_req_account_id = external_mode ? ext_acct_req_account_id : br_acct_req_account_id;
    wire [7:0] acct_req_product_id = external_mode ? ext_acct_req_product_id : br_acct_req_product_id;
    wire [2:0] acct_req_event_kind = external_mode ? ext_acct_req_event_kind : br_acct_req_event_kind;
    wire acct_req_side = external_mode ? ext_acct_req_side : br_acct_req_side;
    wire [7:0] acct_req_position_effect = external_mode ? ext_acct_req_position_effect : br_acct_req_position_effect;
    wire [QTY_W-1:0] acct_req_order_qty = external_mode ? ext_acct_req_order_qty : br_acct_req_order_qty;
    wire [QTY_W-1:0] acct_req_fill_qty = external_mode ? ext_acct_req_fill_qty : br_acct_req_fill_qty;
    wire [QTY_W-1:0] acct_req_release_qty = external_mode ? ext_acct_req_release_qty : br_acct_req_release_qty;
    wire acct_rsp_ready = external_mode ? ext_acct_rsp_ready : br_acct_rsp_ready;
    wire acct_req_ready_i, acct_rsp_valid_i, acct_rsp_ok_i;
    wire [1:0] acct_rsp_reason_source_i;
    wire [7:0] acct_rsp_reason_code_i;

    assign ext_acct_req_ready = external_mode ? acct_req_ready_i : 1'b0;
    assign ext_acct_rsp_valid = external_mode ? acct_rsp_valid_i : 1'b0;
    assign ext_acct_rsp_ok = acct_rsp_ok_i;
    assign ext_acct_rsp_reason_source = acct_rsp_reason_source_i;
    assign ext_acct_rsp_reason_code = acct_rsp_reason_code_i;
    assign br_acct_req_ready = external_mode ? 1'b0 : acct_req_ready_i;
    assign br_acct_rsp_valid = external_mode ? 1'b0 : acct_rsp_valid_i;
    assign br_acct_rsp_ok = acct_rsp_ok_i;
    assign br_acct_rsp_reason_source = acct_rsp_reason_source_i;
    assign br_acct_rsp_reason_code = acct_rsp_reason_code_i;

    hft_rmic_futures_state_manager_v1 #(.QTY_W(QTY_W),.MARGIN_W(MARGIN_W)) u_state (
        .clk(clk),.rst_n(rst_n),.cfg_valid(cfg_valid),.cfg_ready(cfg_ready),
        .cfg_account_id(cfg_account_id),.cfg_product_id(cfg_product_id),.cfg_enabled(cfg_enabled),
        .cfg_margin_budget(cfg_margin_budget),.cfg_margin_per_contract(cfg_margin_per_contract),
        .cfg_long_position(cfg_long_position),.cfg_short_position(cfg_short_position),
        .cfg_pending_open_long(cfg_pending_open_long),.cfg_pending_open_short(cfg_pending_open_short),
        .cfg_reserved_close_long(cfg_reserved_close_long),.cfg_reserved_close_short(cfg_reserved_close_short),
        .cfg_done(cfg_done),.cfg_ok(cfg_ok),.cfg_reason_code(cfg_reason_code),
        .req_valid(acct_req_valid),.req_ready(acct_req_ready_i),.req_account_id(acct_req_account_id),
        .req_product_id(acct_req_product_id),.req_event_kind(acct_req_event_kind),.req_side(acct_req_side),
        .req_position_effect(acct_req_position_effect),.req_order_qty(acct_req_order_qty),
        .req_fill_qty(acct_req_fill_qty),.req_release_qty(acct_req_release_qty),
        .rsp_valid(acct_rsp_valid_i),.rsp_ready(acct_rsp_ready),.rsp_ok(acct_rsp_ok_i),
        .rsp_reason_source(acct_rsp_reason_source_i),.rsp_reason_code(acct_rsp_reason_code_i),
        .rsp_account_id(),.rsp_product_id(),.rsp_entry_enabled(),.rsp_long_position(),
        .rsp_short_position(),.rsp_pending_open_long(),.rsp_pending_open_short(),
        .rsp_reserved_close_long(),.rsp_reserved_close_short(),
        .rsp_required_margin_before(),.rsp_required_margin_after()
    );

    wire bridge_commit_ready;
    assign commit_ready = external_mode ? 1'b0 : bridge_commit_ready;

    hft_rmic_committed_execution_bridge_v1 #(.QTY_W(QTY_W)) u_bridge (
        .clk(clk),.rst_n(rst_n),.commit_valid(commit_valid && !external_mode),
        .commit_ready(bridge_commit_ready),.commit_msg_type(commit_msg_type),
        .commit_status_code(commit_status_code),.commit_exec_type(commit_exec_type),
        .commit_order_id(commit_order_id),.commit_side(commit_side),
        .commit_position_effect(commit_position_effect),.commit_order_price(commit_order_price),
        .commit_last_qty(commit_last_qty),.commit_leaves_qty(commit_leaves_qty),
        .commit_before_qty(commit_before_qty),.result_valid(result_valid),.result_ready(result_ready),
        .result_ok(result_ok),.result_reason_source(result_reason_source),
        .result_reason_code(result_reason_code),.result_order_id(result_order_id),
        .result_remaining_qty(result_remaining_qty),
        .store_req_valid(br_store_req_valid),.store_req_ready(br_store_req_ready),
        .store_req_op(br_store_req_op),.store_req_order_id(br_store_req_order_id),
        .store_req_account_id(br_store_req_account_id),.store_req_product_id(br_store_req_product_id),
        .store_req_side(br_store_req_side),.store_req_position_effect(br_store_req_position_effect),
        .store_req_order_type(br_store_req_order_type),.store_req_tif(br_store_req_tif),
        .store_req_limit_price(br_store_req_limit_price),.store_req_remaining_qty(br_store_req_remaining_qty),
        .store_rsp_valid(br_store_rsp_valid),.store_rsp_ready(br_store_rsp_ready),
        .store_rsp_ok(br_store_rsp_ok),.store_rsp_found(br_store_rsp_found),
        .store_rsp_status(br_store_rsp_status),.store_rsp_account_id(br_store_rsp_account_id),
        .store_rsp_product_id(br_store_rsp_product_id),.store_rsp_side(br_store_rsp_side),
        .store_rsp_position_effect(br_store_rsp_position_effect),.store_rsp_order_type(br_store_rsp_order_type),
        .store_rsp_tif(br_store_rsp_tif),.store_rsp_limit_price(br_store_rsp_limit_price),
        .store_rsp_remaining_qty(br_store_rsp_remaining_qty),
        .acct_req_valid(br_acct_req_valid),.acct_req_ready(br_acct_req_ready),
        .acct_req_account_id(br_acct_req_account_id),.acct_req_product_id(br_acct_req_product_id),
        .acct_req_event_kind(br_acct_req_event_kind),.acct_req_side(br_acct_req_side),
        .acct_req_position_effect(br_acct_req_position_effect),.acct_req_order_qty(br_acct_req_order_qty),
        .acct_req_fill_qty(br_acct_req_fill_qty),.acct_req_release_qty(br_acct_req_release_qty),
        .acct_rsp_valid(br_acct_rsp_valid),.acct_rsp_ready(br_acct_rsp_ready),
        .acct_rsp_ok(br_acct_rsp_ok),.acct_rsp_reason_source(br_acct_rsp_reason_source),
        .acct_rsp_reason_code(br_acct_rsp_reason_code)
    );
endmodule
