`timescale 1ns/1ps
`include "hft_rmic_policy_defs.svh"

// I4 shared futures risk core.
//
// The already-verified I3 CL2EX order gate and I2 committed-execution bridge
// were intentionally written as exclusive clients.  I4 preserves those
// transaction semantics and adds a transaction-level owner lock around the
// single futures-state manager and single AMU order-context store.
//
// Execution receives acquisition priority when a committed report and a new
// order arrive in the same idle cycle.  Once one client acquires ownership,
// the other is backpressured until the owner's result is consumed.  This is a
// correctness-first arbitration point; later throughput work may replace it
// only with equivalent hazard/atomicity evidence.
module hft_rmic_shared_core_v1 #(
    parameter integer ORDER_WIDTH = 256,
    parameter integer QTY_W = 16,
    parameter integer MARGIN_W = 64,
    parameter integer ACCOUNT_MAP_ENTRIES = 16,
    parameter integer PRODUCT_MAP_ENTRIES = 16,
    parameter integer ACCOUNT_MAP_INDEX_W = (ACCOUNT_MAP_ENTRIES <= 1) ? 1 : $clog2(ACCOUNT_MAP_ENTRIES),
    parameter integer PRODUCT_MAP_INDEX_W = (PRODUCT_MAP_ENTRIES <= 1) ? 1 : $clog2(PRODUCT_MAP_ENTRIES),
    parameter integer ENABLE_HOT_MAP_CACHE = 0,
    parameter integer ENABLE_PARALLEL_CL_ADMISSION = 0,
    parameter integer ENABLE_L0_STATE_CACHE = 0
) (
    input  wire clk,
    input  wire rst_n,

    input  wire integration_ready,
    input  wire accounting_ready,
    input  wire global_kill,
    input  wire recovery_clear,
    output reg  recovery_required,
    output wire store_init_done,
    output wire [1:0] transaction_owner,

    input  wire [255:0] order_type_allow_mask,
    input  wire [255:0] tif_allow_mask,
    input  wire [255:0] position_effect_allow_mask,

    input  wire account_cfg_we,
    input  wire [ACCOUNT_MAP_INDEX_W-1:0] account_cfg_index,
    input  wire account_cfg_valid,
    input  wire [31:0] account_cfg_key,
    input  wire [7:0] account_cfg_value,
    input  wire product_cfg_we,
    input  wire [PRODUCT_MAP_INDEX_W-1:0] product_cfg_index,
    input  wire product_cfg_valid,
    input  wire [15:0] product_cfg_key,
    input  wire [7:0] product_cfg_value,
    input  wire [31:0] hot_account_key,
    input  wire [15:0] hot_product_key,

    // Host/recovery state configuration.
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

    // One packed HFT order stream after legacy/prebuild source arbitration.
    input  wire order_valid,
    output wire order_ready,
    input  wire [ORDER_WIDTH-1:0] order_data,

    // Accepted order becomes the only legal R01 input.
    output wire accepted_order_valid,
    input  wire accepted_order_ready,
    output wire [ORDER_WIDTH-1:0] accepted_order_data,
    output wire [31:0] accepted_order_id,

    // Local reject telemetry.  Rejected payload never appears on accepted path.
    output wire reject_valid,
    input  wire reject_ready,
    output wire [31:0] reject_order_id,
    output wire [1:0] reject_reason_source,
    output wire [7:0] reject_reason_code,

    // Committed R02/R32/R03 event from the frozen HFT ownership path.
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
    output wire [QTY_W-1:0] exec_result_remaining_qty
);
    localparam [1:0] OWNER_NONE = 2'd0;
    localparam [1:0] OWNER_CL   = 2'd1;
    localparam [1:0] OWNER_EX   = 2'd2;
    reg [1:0] owner;
    assign transaction_owner = owner;

    // ------------------------------------------------------------------
    // CL2EX order gate client
    // ------------------------------------------------------------------
    wire cl_order_ready;
    wire cl_result_valid, cl_result_accepted;
    wire cl_result_ready;
    wire [1:0] cl_result_reason_source;
    wire [7:0] cl_result_reason_code;
    wire [31:0] cl_result_order_id;
    wire [ORDER_WIDTH-1:0] cl_result_order_data;

    wire cl_acct_req_valid, cl_acct_req_ready;
    wire [7:0] cl_acct_req_account_id, cl_acct_req_product_id;
    wire [2:0] cl_acct_req_event_kind;
    wire cl_acct_req_side;
    wire [7:0] cl_acct_req_position_effect;
    wire [QTY_W-1:0] cl_acct_req_order_qty, cl_acct_req_fill_qty, cl_acct_req_release_qty;
    wire cl_acct_rsp_valid, cl_acct_rsp_ready, cl_acct_rsp_ok;
    wire [1:0] cl_acct_rsp_reason_source;
    wire [7:0] cl_acct_rsp_reason_code;

    wire cl_store_req_valid, cl_store_req_ready;
    wire [1:0] cl_store_req_op;
    wire [31:0] cl_store_req_order_id;
    wire [7:0] cl_store_req_account_id, cl_store_req_product_id;
    wire cl_store_req_side;
    wire [7:0] cl_store_req_position_effect, cl_store_req_order_type, cl_store_req_tif;
    wire [31:0] cl_store_req_limit_price;
    wire [QTY_W-1:0] cl_store_req_remaining_qty;
    wire cl_store_rsp_valid, cl_store_rsp_ready, cl_store_rsp_ok, cl_store_rsp_found;
    wire [2:0] cl_store_rsp_status;

    // ------------------------------------------------------------------
    // EX2CL committed execution client
    // ------------------------------------------------------------------
    wire ex_commit_ready_i;
    wire ex_result_valid_i, ex_result_ok_i;
    wire ex_result_ready_i;
    wire [1:0] ex_result_reason_source_i;
    wire [7:0] ex_result_reason_code_i;
    wire [31:0] ex_result_order_id_i;
    wire [QTY_W-1:0] ex_result_remaining_qty_i;

    wire ex_store_req_valid, ex_store_req_ready;
    wire [1:0] ex_store_req_op;
    wire [31:0] ex_store_req_order_id;
    wire [7:0] ex_store_req_account_id, ex_store_req_product_id;
    wire ex_store_req_side;
    wire [7:0] ex_store_req_position_effect, ex_store_req_order_type, ex_store_req_tif;
    wire [31:0] ex_store_req_limit_price;
    wire [QTY_W-1:0] ex_store_req_remaining_qty;
    wire ex_store_rsp_valid, ex_store_rsp_ready, ex_store_rsp_ok, ex_store_rsp_found;
    wire [2:0] ex_store_rsp_status;
    wire [7:0] ex_store_rsp_account_id, ex_store_rsp_product_id;
    wire ex_store_rsp_side;
    wire [7:0] ex_store_rsp_position_effect, ex_store_rsp_order_type, ex_store_rsp_tif;
    wire [31:0] ex_store_rsp_limit_price;
    wire [QTY_W-1:0] ex_store_rsp_remaining_qty;

    wire ex_acct_req_valid, ex_acct_req_ready;
    wire [7:0] ex_acct_req_account_id, ex_acct_req_product_id;
    wire [2:0] ex_acct_req_event_kind;
    wire ex_acct_req_side;
    wire [7:0] ex_acct_req_position_effect;
    wire [QTY_W-1:0] ex_acct_req_order_qty, ex_acct_req_fill_qty, ex_acct_req_release_qty;
    wire ex_acct_rsp_valid, ex_acct_rsp_ready, ex_acct_rsp_ok;
    wire [1:0] ex_acct_rsp_reason_source;
    wire [7:0] ex_acct_rsp_reason_code;

    // No runtime transaction starts until the AMU scrub is complete.  State
    // configuration is still allowed during recovery so software can restore
    // the complete record before clearing recovery_required.
    wire owner_none = (owner == OWNER_NONE);
    wire runtime_idle = owner_none && !cfg_valid && !recovery_required && store_init_done;
    wire choose_ex = runtime_idle && exec_commit_valid;
    wire choose_cl = runtime_idle && !exec_commit_valid;

    assign order_ready = choose_cl && cl_order_ready;
    wire cl_order_valid_i = choose_cl && order_valid;

    assign exec_commit_ready = runtime_idle && ex_commit_ready_i;
    wire ex_commit_valid_i = runtime_idle && exec_commit_valid;

    assign accepted_order_valid = (owner == OWNER_CL) && cl_result_valid && cl_result_accepted;
    assign accepted_order_data = cl_result_order_data;
    assign accepted_order_id = cl_result_order_id;
    assign reject_valid = (owner == OWNER_CL) && cl_result_valid && !cl_result_accepted;
    assign reject_order_id = cl_result_order_id;
    assign reject_reason_source = cl_result_reason_source;
    assign reject_reason_code = cl_result_reason_code;
    assign cl_result_ready = cl_result_accepted ? accepted_order_ready : reject_ready;

    assign exec_result_valid = (owner == OWNER_EX) && ex_result_valid_i;
    assign exec_result_ok = ex_result_ok_i;
    assign exec_result_reason_source = ex_result_reason_source_i;
    assign exec_result_reason_code = ex_result_reason_code_i;
    assign exec_result_order_id = ex_result_order_id_i;
    assign exec_result_remaining_qty = ex_result_remaining_qty_i;
    assign ex_result_ready_i = exec_result_ready;

    // Gate config writes are allowed only while no transaction owns the core.
    wire gate_account_cfg_we = account_cfg_we && owner_none;
    wire gate_product_cfg_we = product_cfg_we && owner_none;
    wire effective_integration_ready = integration_ready && store_init_done && !recovery_required;

    hft_rmic_order_gate_v1 #(
        .ORDER_WIDTH(ORDER_WIDTH), .QTY_W(QTY_W),
        .ACCOUNT_MAP_ENTRIES(ACCOUNT_MAP_ENTRIES),
        .PRODUCT_MAP_ENTRIES(PRODUCT_MAP_ENTRIES),
        .ENABLE_HOT_MAP_CACHE(ENABLE_HOT_MAP_CACHE),
        .ENABLE_PARALLEL_ADMISSION(ENABLE_PARALLEL_CL_ADMISSION)
    ) u_order_gate (
        .clk(clk), .rst_n(rst_n),
        .integration_ready(effective_integration_ready),
        .accounting_ready(accounting_ready), .global_kill(global_kill),
        .order_type_allow_mask(order_type_allow_mask), .tif_allow_mask(tif_allow_mask),
        .position_effect_allow_mask(position_effect_allow_mask),
        .account_cfg_we(gate_account_cfg_we), .account_cfg_index(account_cfg_index),
        .account_cfg_valid(account_cfg_valid), .account_cfg_key(account_cfg_key),
        .account_cfg_value(account_cfg_value),
        .product_cfg_we(gate_product_cfg_we), .product_cfg_index(product_cfg_index),
        .product_cfg_valid(product_cfg_valid), .product_cfg_key(product_cfg_key),
        .product_cfg_value(product_cfg_value),
        .hot_account_key(hot_account_key), .hot_product_key(hot_product_key),
        .order_valid(cl_order_valid_i), .order_ready(cl_order_ready), .order_data(order_data),
        .result_valid(cl_result_valid), .result_ready(cl_result_ready),
        .result_accepted(cl_result_accepted), .result_reason_source(cl_result_reason_source),
        .result_reason_code(cl_result_reason_code), .result_order_id(cl_result_order_id),
        .result_order_data(cl_result_order_data),
        .acct_req_valid(cl_acct_req_valid), .acct_req_ready(cl_acct_req_ready),
        .acct_req_account_id(cl_acct_req_account_id), .acct_req_product_id(cl_acct_req_product_id),
        .acct_req_event_kind(cl_acct_req_event_kind), .acct_req_side(cl_acct_req_side),
        .acct_req_position_effect(cl_acct_req_position_effect),
        .acct_req_order_qty(cl_acct_req_order_qty), .acct_req_fill_qty(cl_acct_req_fill_qty),
        .acct_req_release_qty(cl_acct_req_release_qty),
        .acct_rsp_valid(cl_acct_rsp_valid), .acct_rsp_ready(cl_acct_rsp_ready),
        .acct_rsp_ok(cl_acct_rsp_ok), .acct_rsp_reason_source(cl_acct_rsp_reason_source),
        .acct_rsp_reason_code(cl_acct_rsp_reason_code),
        .store_req_valid(cl_store_req_valid), .store_req_ready(cl_store_req_ready),
        .store_req_op(cl_store_req_op), .store_req_order_id(cl_store_req_order_id),
        .store_req_account_id(cl_store_req_account_id), .store_req_product_id(cl_store_req_product_id),
        .store_req_side(cl_store_req_side), .store_req_position_effect(cl_store_req_position_effect),
        .store_req_order_type(cl_store_req_order_type), .store_req_tif(cl_store_req_tif),
        .store_req_limit_price(cl_store_req_limit_price),
        .store_req_remaining_qty(cl_store_req_remaining_qty),
        .store_rsp_valid(cl_store_rsp_valid), .store_rsp_ready(cl_store_rsp_ready),
        .store_rsp_ok(cl_store_rsp_ok), .store_rsp_found(cl_store_rsp_found),
        .store_rsp_status(cl_store_rsp_status)
    );

    hft_rmic_committed_execution_bridge_v1 #(.QTY_W(QTY_W)) u_exec_bridge (
        .clk(clk), .rst_n(rst_n),
        .commit_valid(ex_commit_valid_i), .commit_ready(ex_commit_ready_i),
        .commit_msg_type(exec_commit_msg_type), .commit_status_code(exec_commit_status_code),
        .commit_exec_type(exec_commit_exec_type), .commit_order_id(exec_commit_order_id),
        .commit_side(exec_commit_side), .commit_position_effect(exec_commit_position_effect),
        .commit_order_price(exec_commit_order_price), .commit_last_qty(exec_commit_last_qty),
        .commit_leaves_qty(exec_commit_leaves_qty), .commit_before_qty(exec_commit_before_qty),
        .result_valid(ex_result_valid_i), .result_ready(ex_result_ready_i),
        .result_ok(ex_result_ok_i), .result_reason_source(ex_result_reason_source_i),
        .result_reason_code(ex_result_reason_code_i), .result_order_id(ex_result_order_id_i),
        .result_remaining_qty(ex_result_remaining_qty_i),
        .store_req_valid(ex_store_req_valid), .store_req_ready(ex_store_req_ready),
        .store_req_op(ex_store_req_op), .store_req_order_id(ex_store_req_order_id),
        .store_req_account_id(ex_store_req_account_id), .store_req_product_id(ex_store_req_product_id),
        .store_req_side(ex_store_req_side), .store_req_position_effect(ex_store_req_position_effect),
        .store_req_order_type(ex_store_req_order_type), .store_req_tif(ex_store_req_tif),
        .store_req_limit_price(ex_store_req_limit_price), .store_req_remaining_qty(ex_store_req_remaining_qty),
        .store_rsp_valid(ex_store_rsp_valid), .store_rsp_ready(ex_store_rsp_ready),
        .store_rsp_ok(ex_store_rsp_ok), .store_rsp_found(ex_store_rsp_found),
        .store_rsp_status(ex_store_rsp_status), .store_rsp_account_id(ex_store_rsp_account_id),
        .store_rsp_product_id(ex_store_rsp_product_id), .store_rsp_side(ex_store_rsp_side),
        .store_rsp_position_effect(ex_store_rsp_position_effect),
        .store_rsp_order_type(ex_store_rsp_order_type), .store_rsp_tif(ex_store_rsp_tif),
        .store_rsp_limit_price(ex_store_rsp_limit_price),
        .store_rsp_remaining_qty(ex_store_rsp_remaining_qty),
        .acct_req_valid(ex_acct_req_valid), .acct_req_ready(ex_acct_req_ready),
        .acct_req_account_id(ex_acct_req_account_id), .acct_req_product_id(ex_acct_req_product_id),
        .acct_req_event_kind(ex_acct_req_event_kind), .acct_req_side(ex_acct_req_side),
        .acct_req_position_effect(ex_acct_req_position_effect),
        .acct_req_order_qty(ex_acct_req_order_qty), .acct_req_fill_qty(ex_acct_req_fill_qty),
        .acct_req_release_qty(ex_acct_req_release_qty),
        .acct_rsp_valid(ex_acct_rsp_valid), .acct_rsp_ready(ex_acct_rsp_ready),
        .acct_rsp_ok(ex_acct_rsp_ok), .acct_rsp_reason_source(ex_acct_rsp_reason_source),
        .acct_rsp_reason_code(ex_acct_rsp_reason_code)
    );

    // ------------------------------------------------------------------
    // Shared state manager
    // ------------------------------------------------------------------
    wire state_cfg_ready;
    wire state_req_valid = (owner == OWNER_CL) ? cl_acct_req_valid :
                           (owner == OWNER_EX) ? ex_acct_req_valid : 1'b0;
    wire [7:0] state_req_account_id = (owner == OWNER_CL) ? cl_acct_req_account_id : ex_acct_req_account_id;
    wire [7:0] state_req_product_id = (owner == OWNER_CL) ? cl_acct_req_product_id : ex_acct_req_product_id;
    wire [2:0] state_req_event_kind = (owner == OWNER_CL) ? cl_acct_req_event_kind : ex_acct_req_event_kind;
    wire state_req_side = (owner == OWNER_CL) ? cl_acct_req_side : ex_acct_req_side;
    wire [7:0] state_req_position_effect = (owner == OWNER_CL) ? cl_acct_req_position_effect : ex_acct_req_position_effect;
    wire [QTY_W-1:0] state_req_order_qty = (owner == OWNER_CL) ? cl_acct_req_order_qty : ex_acct_req_order_qty;
    wire [QTY_W-1:0] state_req_fill_qty = (owner == OWNER_CL) ? cl_acct_req_fill_qty : ex_acct_req_fill_qty;
    wire [QTY_W-1:0] state_req_release_qty = (owner == OWNER_CL) ? cl_acct_req_release_qty : ex_acct_req_release_qty;
    wire state_rsp_ready = (owner == OWNER_CL) ? cl_acct_rsp_ready :
                           (owner == OWNER_EX) ? ex_acct_rsp_ready : 1'b0;
    wire state_req_ready_i, state_rsp_valid_i, state_rsp_ok_i;
    wire [1:0] state_rsp_reason_source_i;
    wire [7:0] state_rsp_reason_code_i;

    assign cl_acct_req_ready = (owner == OWNER_CL) ? state_req_ready_i : 1'b0;
    assign ex_acct_req_ready = (owner == OWNER_EX) ? state_req_ready_i : 1'b0;
    assign cl_acct_rsp_valid = (owner == OWNER_CL) ? state_rsp_valid_i : 1'b0;
    assign ex_acct_rsp_valid = (owner == OWNER_EX) ? state_rsp_valid_i : 1'b0;
    assign cl_acct_rsp_ok = state_rsp_ok_i;
    assign ex_acct_rsp_ok = state_rsp_ok_i;
    assign cl_acct_rsp_reason_source = state_rsp_reason_source_i;
    assign ex_acct_rsp_reason_source = state_rsp_reason_source_i;
    assign cl_acct_rsp_reason_code = state_rsp_reason_code_i;
    assign ex_acct_rsp_reason_code = state_rsp_reason_code_i;

    assign cfg_ready = owner_none && state_cfg_ready;
    hft_rmic_futures_state_manager_v1 #(
        .QTY_W(QTY_W), .MARGIN_W(MARGIN_W),
        .ENABLE_L0_FAST_CACHE(ENABLE_L0_STATE_CACHE)
    ) u_state (
        .clk(clk), .rst_n(rst_n),
        .cfg_valid(cfg_valid && owner_none), .cfg_ready(state_cfg_ready),
        .cfg_account_id(cfg_account_id), .cfg_product_id(cfg_product_id),
        .cfg_enabled(cfg_enabled), .cfg_margin_budget(cfg_margin_budget),
        .cfg_margin_per_contract(cfg_margin_per_contract),
        .cfg_long_position(cfg_long_position), .cfg_short_position(cfg_short_position),
        .cfg_pending_open_long(cfg_pending_open_long), .cfg_pending_open_short(cfg_pending_open_short),
        .cfg_reserved_close_long(cfg_reserved_close_long), .cfg_reserved_close_short(cfg_reserved_close_short),
        .cfg_done(cfg_done), .cfg_ok(cfg_ok), .cfg_reason_code(cfg_reason_code),
        .req_valid(state_req_valid), .req_ready(state_req_ready_i),
        .req_account_id(state_req_account_id), .req_product_id(state_req_product_id),
        .req_event_kind(state_req_event_kind), .req_side(state_req_side),
        .req_position_effect(state_req_position_effect), .req_order_qty(state_req_order_qty),
        .req_fill_qty(state_req_fill_qty), .req_release_qty(state_req_release_qty),
        .rsp_valid(state_rsp_valid_i), .rsp_ready(state_rsp_ready), .rsp_ok(state_rsp_ok_i),
        .rsp_reason_source(state_rsp_reason_source_i), .rsp_reason_code(state_rsp_reason_code_i),
        .rsp_account_id(), .rsp_product_id(), .rsp_entry_enabled(), .rsp_long_position(),
        .rsp_short_position(), .rsp_pending_open_long(), .rsp_pending_open_short(),
        .rsp_reserved_close_long(), .rsp_reserved_close_short(),
        .rsp_required_margin_before(), .rsp_required_margin_after()
    );

    // ------------------------------------------------------------------
    // Shared order-context store.  EX lookup is allowed prospectively in the
    // owner-acquisition cycle because the execution bridge issues LOOKUP on
    // the same cycle that commit_valid/commit_ready handshakes.
    // ------------------------------------------------------------------
    wire prospective_ex = owner_none && runtime_idle && exec_commit_valid;
    wire route_ex_store = (owner == OWNER_EX) || prospective_ex;
    wire store_req_valid_i = (owner == OWNER_CL) ? cl_store_req_valid :
                             route_ex_store ? ex_store_req_valid : 1'b0;
    wire [1:0] store_req_op_i = (owner == OWNER_CL) ? cl_store_req_op : ex_store_req_op;
    wire [31:0] store_req_order_id_i = (owner == OWNER_CL) ? cl_store_req_order_id : ex_store_req_order_id;
    wire [7:0] store_req_account_id_i = (owner == OWNER_CL) ? cl_store_req_account_id : ex_store_req_account_id;
    wire [7:0] store_req_product_id_i = (owner == OWNER_CL) ? cl_store_req_product_id : ex_store_req_product_id;
    wire store_req_side_i = (owner == OWNER_CL) ? cl_store_req_side : ex_store_req_side;
    wire [7:0] store_req_position_effect_i = (owner == OWNER_CL) ? cl_store_req_position_effect : ex_store_req_position_effect;
    wire [7:0] store_req_order_type_i = (owner == OWNER_CL) ? cl_store_req_order_type : ex_store_req_order_type;
    wire [7:0] store_req_tif_i = (owner == OWNER_CL) ? cl_store_req_tif : ex_store_req_tif;
    wire [31:0] store_req_limit_price_i = (owner == OWNER_CL) ? cl_store_req_limit_price : ex_store_req_limit_price;
    wire [QTY_W-1:0] store_req_remaining_qty_i = (owner == OWNER_CL) ? cl_store_req_remaining_qty : ex_store_req_remaining_qty;
    wire store_rsp_ready_i = (owner == OWNER_CL) ? cl_store_rsp_ready :
                             (owner == OWNER_EX) ? ex_store_rsp_ready : 1'b0;

    wire store_req_ready_i, store_rsp_valid_i, store_rsp_ok_i, store_rsp_found_i;
    wire [2:0] store_rsp_status_i;
    wire [7:0] store_rsp_account_id_i, store_rsp_product_id_i;
    wire store_rsp_side_i;
    wire [7:0] store_rsp_position_effect_i, store_rsp_order_type_i, store_rsp_tif_i;
    wire [31:0] store_rsp_limit_price_i;
    wire [QTY_W-1:0] store_rsp_remaining_qty_i;
    wire [2:0] store_rsp_bank_unused;
    wire store_rsp_stash_unused;

    assign cl_store_req_ready = (owner == OWNER_CL) ? store_req_ready_i : 1'b0;
    assign ex_store_req_ready = route_ex_store ? store_req_ready_i : 1'b0;
    assign cl_store_rsp_valid = (owner == OWNER_CL) ? store_rsp_valid_i : 1'b0;
    assign ex_store_rsp_valid = (owner == OWNER_EX) ? store_rsp_valid_i : 1'b0;
    assign cl_store_rsp_ok = store_rsp_ok_i;
    assign ex_store_rsp_ok = store_rsp_ok_i;
    assign cl_store_rsp_found = store_rsp_found_i;
    assign ex_store_rsp_found = store_rsp_found_i;
    assign cl_store_rsp_status = store_rsp_status_i;
    assign ex_store_rsp_status = store_rsp_status_i;
    assign ex_store_rsp_account_id = store_rsp_account_id_i;
    assign ex_store_rsp_product_id = store_rsp_product_id_i;
    assign ex_store_rsp_side = store_rsp_side_i;
    assign ex_store_rsp_position_effect = store_rsp_position_effect_i;
    assign ex_store_rsp_order_type = store_rsp_order_type_i;
    assign ex_store_rsp_tif = store_rsp_tif_i;
    assign ex_store_rsp_limit_price = store_rsp_limit_price_i;
    assign ex_store_rsp_remaining_qty = store_rsp_remaining_qty_i;

    hft_rmic_futures_order_store_v1 #(.QTY_W(QTY_W)) u_store (
        .clk(clk), .rst_n(rst_n),
        .req_valid(store_req_valid_i), .req_ready(store_req_ready_i),
        .req_op(store_req_op_i), .req_order_id(store_req_order_id_i),
        .req_account_id(store_req_account_id_i), .req_product_id(store_req_product_id_i),
        .req_side(store_req_side_i), .req_position_effect(store_req_position_effect_i),
        .req_order_type(store_req_order_type_i), .req_tif(store_req_tif_i),
        .req_limit_price(store_req_limit_price_i), .req_remaining_qty(store_req_remaining_qty_i),
        .rsp_valid(store_rsp_valid_i), .rsp_ready(store_rsp_ready_i),
        .rsp_ok(store_rsp_ok_i), .rsp_found(store_rsp_found_i), .rsp_status(store_rsp_status_i),
        .rsp_account_id(store_rsp_account_id_i), .rsp_product_id(store_rsp_product_id_i),
        .rsp_side(store_rsp_side_i), .rsp_position_effect(store_rsp_position_effect_i),
        .rsp_order_type(store_rsp_order_type_i), .rsp_tif(store_rsp_tif_i),
        .rsp_limit_price(store_rsp_limit_price_i), .rsp_remaining_qty(store_rsp_remaining_qty_i),
        .rsp_bank(store_rsp_bank_unused), .rsp_in_stash(store_rsp_stash_unused),
        .init_done(store_init_done)
    );

    // Transaction owner and sticky recovery state.
    wire cl_fire = cl_order_valid_i && cl_order_ready;
    wire ex_fire = ex_commit_valid_i && ex_commit_ready_i;
    wire cl_done = (owner == OWNER_CL) && cl_result_valid && cl_result_ready;
    wire ex_done = (owner == OWNER_EX) && ex_result_valid_i && ex_result_ready_i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            owner <= OWNER_NONE;
            recovery_required <= 1'b0;
        end else begin
            if (owner == OWNER_NONE) begin
                if (ex_fire)
                    owner <= OWNER_EX;
                else if (cl_fire)
                    owner <= OWNER_CL;
            end else if (cl_done || ex_done) begin
                owner <= OWNER_NONE;
            end

            if (owner_none && recovery_clear)
                recovery_required <= 1'b0;

            if (cl_done && !cl_result_accepted &&
                (cl_result_reason_source == `HFT_RMIC_REASON_SRC_SYSTEM) &&
                (cl_result_reason_code == `HFT_RMIC_SYSTEM_REASON_ADMISSION_ROLLBACK_FAILED))
                recovery_required <= 1'b1;

            if (ex_done && !ex_result_ok_i &&
                (ex_result_reason_source_i == `HFT_RMIC_REASON_SRC_SYSTEM) &&
                (ex_result_reason_code_i == `HFT_RMIC_SYSTEM_REASON_RECOVERY_REQUIRED))
                recovery_required <= 1'b1;
        end
    end
endmodule
