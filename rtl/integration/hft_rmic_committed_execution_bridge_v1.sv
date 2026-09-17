`timescale 1ns/1ps
`include "hft_rmic_accounting_defs.svh"
`include "hft_rmic_policy_defs.svh"
`include "taifex_tmp_v2187_defs.svh"

// I2 committed execution reconciler.
//
// IMPORTANT CONTRACT:
//   commit_valid is asserted only for an execution/error event that the frozen
//   HFT path has already admitted (R02/R32 through report-sequence ownership;
//   R03 through the checksum-valid committed error path). Raw decoder-valid is
//   not a legal mutation source.
//
// The bridge owns no storage. It arbitrates one event at a time across a
// futures order-context store and the futures account/product state manager.
// This makes the transactional ordering explicit and independently testable.
module hft_rmic_committed_execution_bridge_v1 #(
    parameter integer ACCOUNT_ID_W = 8,
    parameter integer PRODUCT_ID_W = 8,
    parameter integer PRICE_W = 32,
    parameter integer QTY_W = 16
) (
    input  wire clk,
    input  wire rst_n,

    input  wire                         commit_valid,
    output wire                         commit_ready,
    input  wire [7:0]                   commit_msg_type,
    input  wire [7:0]                   commit_status_code,
    input  wire [7:0]                   commit_exec_type,
    input  wire [31:0]                  commit_order_id,
    input  wire                         commit_side,
    input  wire [7:0]                   commit_position_effect,
    input  wire [PRICE_W-1:0]           commit_order_price,
    input  wire [QTY_W-1:0]             commit_last_qty,
    input  wire [QTY_W-1:0]             commit_leaves_qty,
    input  wire [QTY_W-1:0]             commit_before_qty,

    output reg                          result_valid,
    input  wire                         result_ready,
    output reg                          result_ok,
    output reg [1:0]                    result_reason_source,
    output reg [7:0]                    result_reason_code,
    output reg [31:0]                   result_order_id,
    output reg [QTY_W-1:0]              result_remaining_qty,

    // Exclusive client interface to futures order-context store.
    output reg                          store_req_valid,
    input  wire                         store_req_ready,
    output reg [1:0]                    store_req_op,
    output reg [31:0]                   store_req_order_id,
    output reg [ACCOUNT_ID_W-1:0]       store_req_account_id,
    output reg [PRODUCT_ID_W-1:0]       store_req_product_id,
    output reg                          store_req_side,
    output reg [7:0]                    store_req_position_effect,
    output reg [7:0]                    store_req_order_type,
    output reg [7:0]                    store_req_tif,
    output reg [PRICE_W-1:0]            store_req_limit_price,
    output reg [QTY_W-1:0]              store_req_remaining_qty,

    input  wire                         store_rsp_valid,
    output reg                          store_rsp_ready,
    input  wire                         store_rsp_ok,
    input  wire                         store_rsp_found,
    input  wire [2:0]                   store_rsp_status,
    input  wire [ACCOUNT_ID_W-1:0]      store_rsp_account_id,
    input  wire [PRODUCT_ID_W-1:0]      store_rsp_product_id,
    input  wire                         store_rsp_side,
    input  wire [7:0]                   store_rsp_position_effect,
    input  wire [7:0]                   store_rsp_order_type,
    input  wire [7:0]                   store_rsp_tif,
    input  wire [PRICE_W-1:0]           store_rsp_limit_price,
    input  wire [QTY_W-1:0]             store_rsp_remaining_qty,

    // Exclusive client interface to futures state manager.
    output reg                          acct_req_valid,
    input  wire                         acct_req_ready,
    output reg [ACCOUNT_ID_W-1:0]       acct_req_account_id,
    output reg [PRODUCT_ID_W-1:0]       acct_req_product_id,
    output reg [2:0]                    acct_req_event_kind,
    output reg                          acct_req_side,
    output reg [7:0]                    acct_req_position_effect,
    output reg [QTY_W-1:0]              acct_req_order_qty,
    output reg [QTY_W-1:0]              acct_req_fill_qty,
    output reg [QTY_W-1:0]              acct_req_release_qty,

    input  wire                         acct_rsp_valid,
    output reg                          acct_rsp_ready,
    input  wire                         acct_rsp_ok,
    input  wire [1:0]                   acct_rsp_reason_source,
    input  wire [7:0]                   acct_rsp_reason_code
);
    localparam [1:0] STORE_LOOKUP = 2'd0;
    localparam [1:0] STORE_DELETE = 2'd2;
    localparam [1:0] STORE_UPDATE = 2'd3;

    localparam [3:0] S_IDLE        = 4'd0;
    localparam [3:0] S_LOOKUP_WAIT = 4'd1;
    localparam [3:0] S_PREP        = 4'd2;
    localparam [3:0] S_ACCT1_ISSUE = 4'd3;
    localparam [3:0] S_ACCT1_WAIT  = 4'd4;
    localparam [3:0] S_ACCT2_ISSUE = 4'd5;
    localparam [3:0] S_ACCT2_WAIT  = 4'd6;
    localparam [3:0] S_STORE_ISSUE = 4'd7;
    localparam [3:0] S_STORE_WAIT  = 4'd8;
    localparam [3:0] S_RESP        = 4'd9;

    reg [3:0] state;

    reg [7:0] ev_msg_type;
    reg [7:0] ev_status_code;
    reg [7:0] ev_exec_type;
    reg [31:0] ev_order_id;
    reg ev_side;
    reg [7:0] ev_position_effect;
    reg [PRICE_W-1:0] ev_order_price;
    reg [QTY_W-1:0] ev_last_qty;
    reg [QTY_W-1:0] ev_leaves_qty;
    reg [QTY_W-1:0] ev_before_qty;

    reg [ACCOUNT_ID_W-1:0] ctx_account_id;
    reg [PRODUCT_ID_W-1:0] ctx_product_id;
    reg ctx_side;
    reg [7:0] ctx_position_effect;
    reg [7:0] ctx_order_type;
    reg [7:0] ctx_tif;
    reg [PRICE_W-1:0] ctx_limit_price;
    reg [QTY_W-1:0] ctx_remaining_qty;

    reg prep_ok;
    reg [7:0] prep_fail_reason;
    reg need_acct1;
    reg [2:0] acct1_kind;
    reg [QTY_W-1:0] acct1_fill_qty;
    reg [QTY_W-1:0] acct1_release_qty;
    reg need_acct2;
    reg [2:0] acct2_kind;
    reg [QTY_W-1:0] acct2_fill_qty;
    reg [QTY_W-1:0] acct2_release_qty;
    reg need_store_final;
    reg [1:0] final_store_op;
    reg [QTY_W-1:0] final_remaining_qty;
    reg [PRICE_W-1:0] final_limit_price;

    wire [QTY_W:0] trade_sum = {1'b0,ev_last_qty} + {1'b0,ev_leaves_qty};
    wire [QTY_W:0] auto_release_wide =
        {1'b0,ev_before_qty} - trade_sum;

    assign commit_ready = (state == S_IDLE) && !result_valid && store_req_ready;
    wire commit_fire = commit_valid && commit_ready;

    always @(*) begin
        prep_ok = 1'b0;
        prep_fail_reason = `HFT_RMIC_SYSTEM_REASON_EXEC_UNSUPPORTED;
        need_acct1 = 1'b0;
        acct1_kind = `HFT_RMIC_ACCT_EVENT_QUERY;
        acct1_fill_qty = {QTY_W{1'b0}};
        acct1_release_qty = {QTY_W{1'b0}};
        need_acct2 = 1'b0;
        acct2_kind = `HFT_RMIC_ACCT_EVENT_QUERY;
        acct2_fill_qty = {QTY_W{1'b0}};
        acct2_release_qty = {QTY_W{1'b0}};
        need_store_final = 1'b0;
        final_store_op = STORE_UPDATE;
        final_remaining_qty = ctx_remaining_qty;
        final_limit_price = ctx_limit_price;

        // R03 is a terminal exchange reject for a locally reserved order.
        // The order context itself is the authoritative side/PositionEffect.
        if (ev_msg_type == `HFT_RMIC_TAIFEX_MSG_R03) begin
            prep_ok = 1'b1;
            if (ctx_remaining_qty != {QTY_W{1'b0}}) begin
                need_acct1 = 1'b1;
                acct1_kind = `HFT_RMIC_ACCT_EVENT_RELEASE;
                acct1_release_qty = ctx_remaining_qty;
            end
            need_store_final = 1'b1;
            final_store_op = STORE_DELETE;
            final_remaining_qty = {QTY_W{1'b0}};
        end else if ((ev_msg_type == `HFT_RMIC_TAIFEX_MSG_R02) ||
                     (ev_msg_type == `HFT_RMIC_TAIFEX_MSG_R32)) begin
            if ((ev_side != ctx_side) ||
                (ev_position_effect != ctx_position_effect)) begin
                prep_fail_reason = `HFT_RMIC_SYSTEM_REASON_EXEC_METADATA_MISMATCH;
            end else if ((ev_exec_type == `HFT_RMIC_TAIFEX_EXEC_TRADE) ||
                         (ev_exec_type == `HFT_RMIC_TAIFEX_EXEC_NEW_TRADE)) begin
                // Normal trade / trade+terminal-cancel path. The exchange may
                // consume only LastQty and cancel a remainder (IOC/status 47),
                // so before_qty = LastQty + LeavesQty + auto_release.
                if (ev_before_qty == ctx_remaining_qty) begin
                    if (trade_sum <= {1'b0,ev_before_qty}) begin
                        prep_ok = 1'b1;
                        if (ev_last_qty != {QTY_W{1'b0}}) begin
                            need_acct1 = 1'b1;
                            acct1_kind = `HFT_RMIC_ACCT_EVENT_FILL;
                            acct1_fill_qty = ev_last_qty;
                        end
                        if (auto_release_wide[QTY_W-1:0] != {QTY_W{1'b0}}) begin
                            if (need_acct1) begin
                                need_acct2 = 1'b1;
                                acct2_kind = `HFT_RMIC_ACCT_EVENT_RELEASE;
                                acct2_release_qty = auto_release_wide[QTY_W-1:0];
                            end else begin
                                need_acct1 = 1'b1;
                                acct1_kind = `HFT_RMIC_ACCT_EVENT_RELEASE;
                                acct1_release_qty = auto_release_wide[QTY_W-1:0];
                            end
                        end
                        need_store_final = 1'b1;
                        final_remaining_qty = ev_leaves_qty;
                        final_store_op = (ev_leaves_qty == {QTY_W{1'b0}}) ?
                            STORE_DELETE : STORE_UPDATE;
                    end else begin
                        prep_fail_reason = `HFT_RMIC_SYSTEM_REASON_EXEC_METADATA_MISMATCH;
                    end
                end else if ((ev_before_qty == {QTY_W{1'b0}}) &&
                             (ev_last_qty == {QTY_W{1'b0}}) &&
                             (ev_leaves_qty == {QTY_W{1'b0}}) &&
                             (ev_status_code != 8'd0)) begin
                    // Terminal exchange rejection/status report with inactive
                    // quantity fields. Release the complete local remainder.
                    prep_ok = 1'b1;
                    if (ctx_remaining_qty != {QTY_W{1'b0}}) begin
                        need_acct1 = 1'b1;
                        acct1_kind = `HFT_RMIC_ACCT_EVENT_RELEASE;
                        acct1_release_qty = ctx_remaining_qty;
                    end
                    need_store_final = 1'b1;
                    final_store_op = STORE_DELETE;
                    final_remaining_qty = {QTY_W{1'b0}};
                end else begin
                    prep_fail_reason = `HFT_RMIC_SYSTEM_REASON_EXEC_METADATA_MISMATCH;
                end
            end else if (ev_exec_type == `HFT_RMIC_TAIFEX_EXEC_CANCEL) begin
                if ((ev_status_code == 8'd0) &&
                    (ev_last_qty == {QTY_W{1'b0}}) &&
                    (ev_before_qty == ctx_remaining_qty) &&
                    (ev_leaves_qty == {QTY_W{1'b0}})) begin
                    prep_ok = 1'b1;
                    if (ctx_remaining_qty != {QTY_W{1'b0}}) begin
                        need_acct1 = 1'b1;
                        acct1_kind = `HFT_RMIC_ACCT_EVENT_RELEASE;
                        acct1_release_qty = ctx_remaining_qty;
                    end
                    need_store_final = 1'b1;
                    final_store_op = STORE_DELETE;
                    final_remaining_qty = {QTY_W{1'b0}};
                end else begin
                    prep_fail_reason = `HFT_RMIC_SYSTEM_REASON_EXEC_METADATA_MISMATCH;
                end
            end else if (ev_exec_type == `HFT_RMIC_TAIFEX_EXEC_REDUCE) begin
                if ((ev_status_code == 8'd0) &&
                    (ev_last_qty == {QTY_W{1'b0}}) &&
                    (ev_before_qty == ctx_remaining_qty) &&
                    (ev_leaves_qty < ev_before_qty)) begin
                    prep_ok = 1'b1;
                    need_acct1 = 1'b1;
                    acct1_kind = `HFT_RMIC_ACCT_EVENT_RELEASE;
                    acct1_release_qty = ev_before_qty - ev_leaves_qty;
                    need_store_final = 1'b1;
                    final_remaining_qty = ev_leaves_qty;
                    final_store_op = (ev_leaves_qty == {QTY_W{1'b0}}) ?
                        STORE_DELETE : STORE_UPDATE;
                end else begin
                    prep_fail_reason = `HFT_RMIC_SYSTEM_REASON_EXEC_METADATA_MISMATCH;
                end
            end else if ((ev_exec_type == `HFT_RMIC_TAIFEX_EXEC_CHANGE_UPPER) ||
                         (ev_exec_type == `HFT_RMIC_TAIFEX_EXEC_CHANGE_LOWER)) begin
                if ((ev_status_code == 8'd0) &&
                    (ev_last_qty == {QTY_W{1'b0}}) &&
                    (ev_before_qty == ctx_remaining_qty) &&
                    (ev_leaves_qty == ctx_remaining_qty)) begin
                    prep_ok = 1'b1;
                    need_store_final = 1'b1;
                    final_store_op = STORE_UPDATE;
                    final_remaining_qty = ctx_remaining_qty;
                    final_limit_price = ev_order_price;
                end else begin
                    prep_fail_reason = `HFT_RMIC_SYSTEM_REASON_EXEC_METADATA_MISMATCH;
                end
            end else if ((ev_exec_type == `HFT_RMIC_TAIFEX_EXEC_NEW) ||
                         (ev_exec_type == `HFT_RMIC_TAIFEX_EXEC_QUERY)) begin
                // Acknowledgement/query only: no accounting or order-context
                // mutation is needed.
                prep_ok = 1'b1;
            end else begin
                prep_fail_reason = `HFT_RMIC_SYSTEM_REASON_EXEC_UNSUPPORTED;
            end
        end else begin
            prep_fail_reason = `HFT_RMIC_SYSTEM_REASON_EXEC_UNSUPPORTED;
        end
    end

    always @(*) begin
        store_req_valid = 1'b0;
        store_req_op = STORE_LOOKUP;
        store_req_order_id = ev_order_id;
        store_req_account_id = ctx_account_id;
        store_req_product_id = ctx_product_id;
        store_req_side = ctx_side;
        store_req_position_effect = ctx_position_effect;
        store_req_order_type = ctx_order_type;
        store_req_tif = ctx_tif;
        store_req_limit_price = final_limit_price;
        store_req_remaining_qty = final_remaining_qty;
        store_rsp_ready = 1'b0;

        acct_req_valid = 1'b0;
        acct_req_account_id = ctx_account_id;
        acct_req_product_id = ctx_product_id;
        acct_req_event_kind = `HFT_RMIC_ACCT_EVENT_QUERY;
        acct_req_side = ctx_side;
        acct_req_position_effect = ctx_position_effect;
        acct_req_order_qty = {QTY_W{1'b0}};
        acct_req_fill_qty = {QTY_W{1'b0}};
        acct_req_release_qty = {QTY_W{1'b0}};
        acct_rsp_ready = 1'b0;

        if (state == S_IDLE) begin
            store_req_valid = commit_valid && !result_valid;
            store_req_op = STORE_LOOKUP;
            store_req_order_id = commit_order_id;
        end else if (state == S_LOOKUP_WAIT) begin
            store_rsp_ready = 1'b1;
        end else if (state == S_ACCT1_ISSUE) begin
            acct_req_valid = 1'b1;
            acct_req_event_kind = acct1_kind;
            acct_req_fill_qty = acct1_fill_qty;
            acct_req_release_qty = acct1_release_qty;
        end else if (state == S_ACCT1_WAIT) begin
            acct_rsp_ready = 1'b1;
        end else if (state == S_ACCT2_ISSUE) begin
            acct_req_valid = 1'b1;
            acct_req_event_kind = acct2_kind;
            acct_req_fill_qty = acct2_fill_qty;
            acct_req_release_qty = acct2_release_qty;
        end else if (state == S_ACCT2_WAIT) begin
            acct_rsp_ready = 1'b1;
        end else if (state == S_STORE_ISSUE) begin
            store_req_valid = 1'b1;
            store_req_op = final_store_op;
        end else if (state == S_STORE_WAIT) begin
            store_rsp_ready = 1'b1;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            result_valid <= 1'b0;
            result_ok <= 1'b0;
            result_reason_source <= `HFT_RMIC_REASON_SRC_SYSTEM;
            result_reason_code <= `HFT_RMIC_SYSTEM_REASON_PASS;
            result_order_id <= 32'd0;
            result_remaining_qty <= {QTY_W{1'b0}};

            ev_msg_type <= 8'd0;
            ev_status_code <= 8'd0;
            ev_exec_type <= 8'd0;
            ev_order_id <= 32'd0;
            ev_side <= 1'b0;
            ev_position_effect <= 8'd0;
            ev_order_price <= {PRICE_W{1'b0}};
            ev_last_qty <= {QTY_W{1'b0}};
            ev_leaves_qty <= {QTY_W{1'b0}};
            ev_before_qty <= {QTY_W{1'b0}};

            ctx_account_id <= {ACCOUNT_ID_W{1'b0}};
            ctx_product_id <= {PRODUCT_ID_W{1'b0}};
            ctx_side <= 1'b0;
            ctx_position_effect <= 8'd0;
            ctx_order_type <= 8'd0;
            ctx_tif <= 8'd0;
            ctx_limit_price <= {PRICE_W{1'b0}};
            ctx_remaining_qty <= {QTY_W{1'b0}};
        end else begin
            if ((state == S_RESP) && result_valid && result_ready) begin
                result_valid <= 1'b0;
                state <= S_IDLE;
            end

            case (state)
                S_IDLE: begin
                    if (commit_fire) begin
                        ev_msg_type <= commit_msg_type;
                        ev_status_code <= commit_status_code;
                        ev_exec_type <= commit_exec_type;
                        ev_order_id <= commit_order_id;
                        ev_side <= commit_side;
                        ev_position_effect <= commit_position_effect;
                        ev_order_price <= commit_order_price;
                        ev_last_qty <= commit_last_qty;
                        ev_leaves_qty <= commit_leaves_qty;
                        ev_before_qty <= commit_before_qty;
                        result_order_id <= commit_order_id;
                        state <= S_LOOKUP_WAIT;
                    end
                end

                S_LOOKUP_WAIT: begin
                    if (store_rsp_valid) begin
                        if (!store_rsp_ok || !store_rsp_found) begin
                            result_ok <= 1'b0;
                            result_reason_source <= `HFT_RMIC_REASON_SRC_SYSTEM;
                            result_reason_code <= `HFT_RMIC_SYSTEM_REASON_ORDER_CONTEXT_NOT_FOUND;
                            result_remaining_qty <= {QTY_W{1'b0}};
                            result_valid <= 1'b1;
                            state <= S_RESP;
                        end else begin
                            ctx_account_id <= store_rsp_account_id;
                            ctx_product_id <= store_rsp_product_id;
                            ctx_side <= store_rsp_side;
                            ctx_position_effect <= store_rsp_position_effect;
                            ctx_order_type <= store_rsp_order_type;
                            ctx_tif <= store_rsp_tif;
                            ctx_limit_price <= store_rsp_limit_price;
                            ctx_remaining_qty <= store_rsp_remaining_qty;
                            state <= S_PREP;
                        end
                    end
                end

                S_PREP: begin
                    if (!prep_ok) begin
                        result_ok <= 1'b0;
                        result_reason_source <= `HFT_RMIC_REASON_SRC_SYSTEM;
                        result_reason_code <= prep_fail_reason;
                        result_remaining_qty <= ctx_remaining_qty;
                        result_valid <= 1'b1;
                        state <= S_RESP;
                    end else if (need_acct1) begin
                        state <= S_ACCT1_ISSUE;
                    end else if (need_store_final) begin
                        state <= S_STORE_ISSUE;
                    end else begin
                        result_ok <= 1'b1;
                        result_reason_source <= `HFT_RMIC_REASON_SRC_SYSTEM;
                        result_reason_code <= `HFT_RMIC_SYSTEM_REASON_PASS;
                        result_remaining_qty <= ctx_remaining_qty;
                        result_valid <= 1'b1;
                        state <= S_RESP;
                    end
                end

                S_ACCT1_ISSUE: begin
                    if (acct_req_ready)
                        state <= S_ACCT1_WAIT;
                end

                S_ACCT1_WAIT: begin
                    if (acct_rsp_valid) begin
                        if (!acct_rsp_ok) begin
                            result_ok <= 1'b0;
                            result_reason_source <= acct_rsp_reason_source;
                            result_reason_code <= acct_rsp_reason_code;
                            result_remaining_qty <= ctx_remaining_qty;
                            result_valid <= 1'b1;
                            state <= S_RESP;
                        end else if (need_acct2) begin
                            state <= S_ACCT2_ISSUE;
                        end else if (need_store_final) begin
                            state <= S_STORE_ISSUE;
                        end else begin
                            result_ok <= 1'b1;
                            result_reason_source <= `HFT_RMIC_REASON_SRC_SYSTEM;
                            result_reason_code <= `HFT_RMIC_SYSTEM_REASON_PASS;
                            result_remaining_qty <= ctx_remaining_qty;
                            result_valid <= 1'b1;
                            state <= S_RESP;
                        end
                    end
                end

                S_ACCT2_ISSUE: begin
                    if (acct_req_ready)
                        state <= S_ACCT2_WAIT;
                end

                S_ACCT2_WAIT: begin
                    if (acct_rsp_valid) begin
                        if (!acct_rsp_ok) begin
                            // This indicates an internal invariant violation:
                            // acct1 committed, but the deterministic follow-up
                            // release failed. Integration must fail closed and
                            // enter recovery; do not modify order context.
                            result_ok <= 1'b0;
                            result_reason_source <= `HFT_RMIC_REASON_SRC_SYSTEM;
                            result_reason_code <= `HFT_RMIC_SYSTEM_REASON_RECOVERY_REQUIRED;
                            result_remaining_qty <= ctx_remaining_qty;
                            result_valid <= 1'b1;
                            state <= S_RESP;
                        end else if (need_store_final) begin
                            state <= S_STORE_ISSUE;
                        end else begin
                            result_ok <= 1'b1;
                            result_reason_source <= `HFT_RMIC_REASON_SRC_SYSTEM;
                            result_reason_code <= `HFT_RMIC_SYSTEM_REASON_PASS;
                            result_remaining_qty <= ctx_remaining_qty;
                            result_valid <= 1'b1;
                            state <= S_RESP;
                        end
                    end
                end

                S_STORE_ISSUE: begin
                    if (store_req_ready)
                        state <= S_STORE_WAIT;
                end

                S_STORE_WAIT: begin
                    if (store_rsp_valid) begin
                        if (!store_rsp_ok) begin
                            // With exclusive store ownership, UPDATE/DELETE of
                            // the key just looked up is expected to succeed.
                            // Failure after account commit requires recovery.
                            result_ok <= 1'b0;
                            result_reason_source <= `HFT_RMIC_REASON_SRC_SYSTEM;
                            result_reason_code <= `HFT_RMIC_SYSTEM_REASON_RECOVERY_REQUIRED;
                            result_remaining_qty <= ctx_remaining_qty;
                        end else begin
                            result_ok <= 1'b1;
                            result_reason_source <= `HFT_RMIC_REASON_SRC_SYSTEM;
                            result_reason_code <= `HFT_RMIC_SYSTEM_REASON_PASS;
                            result_remaining_qty <= final_remaining_qty;
                        end
                        result_valid <= 1'b1;
                        state <= S_RESP;
                    end
                end

                S_RESP: begin
                    // Hold response until accepted.
                end

                default: begin
                    result_ok <= 1'b0;
                    result_reason_source <= `HFT_RMIC_REASON_SRC_SYSTEM;
                    result_reason_code <= `HFT_RMIC_SYSTEM_REASON_RECOVERY_REQUIRED;
                    result_valid <= 1'b1;
                    state <= S_RESP;
                end
            endcase
        end
    end

    wire unused_store_status = ^store_rsp_status;
endmodule
