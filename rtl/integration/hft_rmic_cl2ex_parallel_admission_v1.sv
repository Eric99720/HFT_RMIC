`timescale 1ns/1ps
`include "hft_rmic_accounting_defs.svh"
`include "hft_rmic_policy_defs.svh"

// I5 latency-oriented CL2EX admission controller.
//
// Success-path difference from hft_rmic_cl2ex_admission_v1:
//   policy PASS -> futures RESERVE || order-context INSERT -> PASS
//
// The shared CL owner lock prevents EX from observing either provisional
// mutation before this controller returns a result.  Acceptance is asserted
// only after *both* operations succeed.
//
// If only one side succeeds, that side is rolled back before a reject is
// exposed:
//   RESERVE ok + INSERT fail -> accounting RELEASE
//   RESERVE fail + INSERT ok -> store DELETE
//
// Any rollback failure is escalated with ADMISSION_ROLLBACK_FAILED so the
// shared core enters recovery-required.  The original 256-bit HFT payload is
// never accepted before the pair has committed atomically.
//
// ENABLE_FAST_SUCCESS_BYPASS removes the otherwise mandatory S_RESP bubble on
// the all-success path. If the final registered accounting/store response
// arrives while the result consumer is ready, result_valid/result_accepted are
// asserted in that same cycle. Backpressure automatically falls back to S_RESP
// with a registered, stable result. Reject/rollback paths are unchanged.
//
// ENABLE_PROSPECTIVE_ISSUE removes the request-issue bubble on a policy-pass
// order. While still in S_IDLE, the live normalized order may issue RESERVE
// and INSERT in the same cycle that the order transaction is accepted. Each
// downstream handshake is remembered independently; a blocked leg simply
// retries from S_PARALLEL on the next cycle. Policy rejects never issue either
// mutation. The shared-core owner lock must enable the matching prospective-CL
// routing mode so EX still has same-cycle acquisition priority.
module hft_rmic_cl2ex_parallel_admission_v1 #(
    parameter integer ORDER_WIDTH = 256,
    parameter integer ACCOUNT_ID_W = 8,
    parameter integer PRODUCT_ID_W = 8,
    parameter integer PRICE_W = 32,
    parameter integer QTY_W = 16,
    parameter integer ENABLE_FAST_SUCCESS_BYPASS = 0,
    parameter integer ENABLE_PROSPECTIVE_ISSUE = 0
) (
    input  wire clk,
    input  wire rst_n,

    input  wire                         order_valid,
    output wire                         order_ready,
    input  wire [ORDER_WIDTH-1:0]       order_data,
    input  wire                         policy_pass,
    input  wire [1:0]                   policy_reason_source,
    input  wire [7:0]                   policy_reason_code,
    input  wire [31:0]                  order_id,
    input  wire [ACCOUNT_ID_W-1:0]      account_id,
    input  wire [PRODUCT_ID_W-1:0]      product_id,
    input  wire                         side,
    input  wire [7:0]                   position_effect,
    input  wire [7:0]                   order_type,
    input  wire [7:0]                   tif,
    input  wire [PRICE_W-1:0]           limit_price,
    input  wire [QTY_W-1:0]             qty,

    output wire                         result_valid,
    input  wire                         result_ready,
    output wire                         result_accepted,
    output wire [1:0]                   result_reason_source,
    output wire [7:0]                   result_reason_code,
    output wire [31:0]                  result_order_id,
    output wire [ORDER_WIDTH-1:0]        result_order_data,

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
    input  wire [7:0]                   acct_rsp_reason_code,

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
    input  wire [2:0]                   store_rsp_status
);
    localparam [1:0] STORE_INSERT = 2'd1;
    localparam [1:0] STORE_DELETE = 2'd2;
    localparam [2:0] STORE_ST_OK     = 3'd0;
    localparam [2:0] STORE_ST_EXISTS = 3'd2;
    localparam [2:0] STORE_ST_FULL   = 3'd3;

    localparam [3:0] S_IDLE                 = 4'd0;
    localparam [3:0] S_PARALLEL             = 4'd1;
    localparam [3:0] S_ACCT_ROLLBACK_ISSUE  = 4'd2;
    localparam [3:0] S_ACCT_ROLLBACK_WAIT   = 4'd3;
    localparam [3:0] S_STORE_ROLLBACK_ISSUE = 4'd4;
    localparam [3:0] S_STORE_ROLLBACK_WAIT  = 4'd5;
    localparam [3:0] S_RESP                 = 4'd6;

    reg [3:0] state;

    reg [ORDER_WIDTH-1:0] tx_order_data;
    reg [31:0] tx_order_id;
    reg [ACCOUNT_ID_W-1:0] tx_account_id;
    reg [PRODUCT_ID_W-1:0] tx_product_id;
    reg tx_side;
    reg [7:0] tx_position_effect;
    reg [7:0] tx_order_type;
    reg [7:0] tx_tif;
    reg [PRICE_W-1:0] tx_limit_price;
    reg [QTY_W-1:0] tx_qty;

    reg acct_req_sent;
    reg store_req_sent;
    reg acct_done;
    reg store_done;
    reg acct_ok_q;
    reg [1:0] acct_reason_source_q;
    reg [7:0] acct_reason_code_q;
    reg store_ok_q;
    reg [2:0] store_status_q;

    reg result_accepted_q;
    reg [1:0] result_reason_source_q;
    reg [7:0] result_reason_code_q;
    reg [31:0] result_order_id_q;
    reg [ORDER_WIDTH-1:0] result_order_data_q;

    reg [1:0] rollback_reject_source;
    reg [7:0] rollback_reject_code;

    assign order_ready = (state == S_IDLE);

    wire order_fire = order_valid && order_ready;
    wire prospective_issue =
        (ENABLE_PROSPECTIVE_ISSUE != 0) &&
        (state == S_IDLE) && order_valid && order_ready && policy_pass;
    wire acct_req_fire = acct_req_valid && acct_req_ready;
    wire store_req_fire = store_req_valid && store_req_ready;
    wire acct_rsp_fire = acct_rsp_valid && acct_rsp_ready;
    wire store_rsp_fire = store_rsp_valid && store_rsp_ready;

    wire acct_done_now = acct_done || acct_rsp_fire;
    wire store_done_now = store_done || store_rsp_fire;
    wire acct_ok_now = acct_rsp_fire ? acct_rsp_ok : acct_ok_q;
    wire [1:0] acct_reason_source_now =
        acct_rsp_fire ? acct_rsp_reason_source : acct_reason_source_q;
    wire [7:0] acct_reason_code_now =
        acct_rsp_fire ? acct_rsp_reason_code : acct_reason_code_q;
    wire store_ok_now = store_rsp_fire ? store_rsp_ok : store_ok_q;
    wire [2:0] store_status_now =
        store_rsp_fire ? store_rsp_status : store_status_q;
    wire store_insert_success_now =
        store_ok_now && (store_status_now == STORE_ST_OK);

    // Zero-extra-cycle success handoff. Both downstream responses are already
    // registered protocol results, so the bypass only joins their valid/OK
    // bits with the transaction payload captured at order acceptance.
    wire fast_success_now =
        (ENABLE_FAST_SUCCESS_BYPASS != 0) &&
        (state == S_PARALLEL) &&
        acct_done_now && store_done_now &&
        acct_ok_now && store_insert_success_now;

    assign result_valid = (state == S_RESP) || fast_success_now;
    assign result_accepted = fast_success_now ? 1'b1 : result_accepted_q;
    assign result_reason_source = fast_success_now ?
        `HFT_RMIC_REASON_SRC_SYSTEM : result_reason_source_q;
    assign result_reason_code = fast_success_now ?
        `HFT_RMIC_SYSTEM_REASON_PASS : result_reason_code_q;
    assign result_order_id = result_order_id_q;
    assign result_order_data = result_order_data_q;

    function automatic [7:0] store_failure_reason;
        input [2:0] status;
        begin
            case (status)
                STORE_ST_EXISTS: store_failure_reason = `HFT_RMIC_SYSTEM_REASON_ORDER_CONTEXT_EXISTS;
                STORE_ST_FULL:   store_failure_reason = `HFT_RMIC_SYSTEM_REASON_ORDER_CONTEXT_FULL;
                default:         store_failure_reason = `HFT_RMIC_SYSTEM_REASON_ORDER_STORE_FAILURE;
            endcase
        end
    endfunction

    always @(*) begin
        acct_req_valid = 1'b0;
        acct_req_account_id = tx_account_id;
        acct_req_product_id = tx_product_id;
        acct_req_event_kind = `HFT_RMIC_ACCT_EVENT_QUERY;
        acct_req_side = tx_side;
        acct_req_position_effect = tx_position_effect;
        acct_req_order_qty = {QTY_W{1'b0}};
        acct_req_fill_qty = {QTY_W{1'b0}};
        acct_req_release_qty = {QTY_W{1'b0}};
        acct_rsp_ready = 1'b0;

        store_req_valid = 1'b0;
        store_req_op = STORE_INSERT;
        store_req_order_id = tx_order_id;
        store_req_account_id = tx_account_id;
        store_req_product_id = tx_product_id;
        store_req_side = tx_side;
        store_req_position_effect = tx_position_effect;
        store_req_order_type = tx_order_type;
        store_req_tif = tx_tif;
        store_req_limit_price = tx_limit_price;
        store_req_remaining_qty = tx_qty;
        store_rsp_ready = 1'b0;

        case (state)
            S_IDLE: begin
                if (prospective_issue) begin
                    // Use the live normalized order on the owner-acquisition
                    // cycle. No transaction state is exposed externally until
                    // both downstream mutations report success.
                    acct_req_valid = 1'b1;
                    acct_req_account_id = account_id;
                    acct_req_product_id = product_id;
                    acct_req_event_kind = `HFT_RMIC_ACCT_EVENT_RESERVE;
                    acct_req_side = side;
                    acct_req_position_effect = position_effect;
                    acct_req_order_qty = qty;

                    store_req_valid = 1'b1;
                    store_req_op = STORE_INSERT;
                    store_req_order_id = order_id;
                    store_req_account_id = account_id;
                    store_req_product_id = product_id;
                    store_req_side = side;
                    store_req_position_effect = position_effect;
                    store_req_order_type = order_type;
                    store_req_tif = tif;
                    store_req_limit_price = limit_price;
                    store_req_remaining_qty = qty;
                end
            end

            S_PARALLEL: begin
                acct_req_valid = !acct_req_sent;
                acct_req_event_kind = `HFT_RMIC_ACCT_EVENT_RESERVE;
                acct_req_order_qty = tx_qty;
                store_req_valid = !store_req_sent;
                store_req_op = STORE_INSERT;

                acct_rsp_ready = acct_req_sent && !acct_done;
                store_rsp_ready = store_req_sent && !store_done;
            end

            S_ACCT_ROLLBACK_ISSUE: begin
                acct_req_valid = 1'b1;
                acct_req_event_kind = `HFT_RMIC_ACCT_EVENT_RELEASE;
                acct_req_release_qty = tx_qty;
            end
            S_ACCT_ROLLBACK_WAIT: acct_rsp_ready = 1'b1;

            S_STORE_ROLLBACK_ISSUE: begin
                store_req_valid = 1'b1;
                store_req_op = STORE_DELETE;
            end
            S_STORE_ROLLBACK_WAIT: store_rsp_ready = 1'b1;

            default: begin end
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            tx_order_data <= {ORDER_WIDTH{1'b0}};
            tx_order_id <= 32'd0;
            tx_account_id <= {ACCOUNT_ID_W{1'b0}};
            tx_product_id <= {PRODUCT_ID_W{1'b0}};
            tx_side <= 1'b0;
            tx_position_effect <= 8'd0;
            tx_order_type <= 8'd0;
            tx_tif <= 8'd0;
            tx_limit_price <= {PRICE_W{1'b0}};
            tx_qty <= {QTY_W{1'b0}};

            acct_req_sent <= 1'b0;
            store_req_sent <= 1'b0;
            acct_done <= 1'b0;
            store_done <= 1'b0;
            acct_ok_q <= 1'b0;
            acct_reason_source_q <= `HFT_RMIC_REASON_SRC_POLICY;
            acct_reason_code_q <= `HFT_RMIC_POLICY_REASON_PASS;
            store_ok_q <= 1'b0;
            store_status_q <= STORE_ST_OK;

            rollback_reject_source <= `HFT_RMIC_REASON_SRC_SYSTEM;
            rollback_reject_code <= `HFT_RMIC_SYSTEM_REASON_ORDER_STORE_FAILURE;

            result_accepted_q <= 1'b0;
            result_reason_source_q <= `HFT_RMIC_REASON_SRC_SYSTEM;
            result_reason_code_q <= `HFT_RMIC_SYSTEM_REASON_NOT_READY;
            result_order_id_q <= 32'd0;
            result_order_data_q <= {ORDER_WIDTH{1'b0}};
        end else begin
            case (state)
                S_IDLE: begin
                    if (order_fire) begin
                        tx_order_data <= order_data;
                        tx_order_id <= order_id;
                        tx_account_id <= account_id;
                        tx_product_id <= product_id;
                        tx_side <= side;
                        tx_position_effect <= position_effect;
                        tx_order_type <= order_type;
                        tx_tif <= tif;
                        tx_limit_price <= limit_price;
                        tx_qty <= qty;

                        result_order_data_q <= order_data;
                        result_order_id_q <= order_id;
                        result_accepted_q <= 1'b0;
                        result_reason_source_q <= policy_reason_source;
                        result_reason_code_q <= policy_reason_code;

                        acct_req_sent <= prospective_issue && acct_req_fire;
                        store_req_sent <= prospective_issue && store_req_fire;
                        acct_done <= 1'b0;
                        store_done <= 1'b0;
                        acct_ok_q <= 1'b0;
                        acct_reason_source_q <= `HFT_RMIC_REASON_SRC_POLICY;
                        acct_reason_code_q <= `HFT_RMIC_POLICY_REASON_PASS;
                        store_ok_q <= 1'b0;
                        store_status_q <= STORE_ST_OK;

                        if (policy_pass)
                            state <= S_PARALLEL;
                        else
                            state <= S_RESP;
                    end
                end

                S_PARALLEL: begin
                    if (acct_req_fire)
                        acct_req_sent <= 1'b1;
                    if (store_req_fire)
                        store_req_sent <= 1'b1;

                    if (acct_rsp_fire) begin
                        acct_done <= 1'b1;
                        acct_ok_q <= acct_rsp_ok;
                        acct_reason_source_q <= acct_rsp_reason_source;
                        acct_reason_code_q <= acct_rsp_reason_code;
                    end
                    if (store_rsp_fire) begin
                        store_done <= 1'b1;
                        store_ok_q <= store_rsp_ok;
                        store_status_q <= store_rsp_status;
                    end

                    if (acct_done_now && store_done_now) begin
                        if (acct_ok_now && store_insert_success_now) begin
                            result_accepted_q <= 1'b1;
                            result_reason_source_q <= `HFT_RMIC_REASON_SRC_SYSTEM;
                            result_reason_code_q <= `HFT_RMIC_SYSTEM_REASON_PASS;
                            if ((ENABLE_FAST_SUCCESS_BYPASS != 0) && result_ready)
                                state <= S_IDLE;
                            else
                                state <= S_RESP;
                        end else if (acct_ok_now && !store_insert_success_now) begin
                            rollback_reject_source <= `HFT_RMIC_REASON_SRC_SYSTEM;
                            rollback_reject_code <= store_failure_reason(store_status_now);
                            state <= S_ACCT_ROLLBACK_ISSUE;
                        end else if (!acct_ok_now && store_insert_success_now) begin
                            rollback_reject_source <= acct_reason_source_now;
                            rollback_reject_code <= acct_reason_code_now;
                            state <= S_STORE_ROLLBACK_ISSUE;
                        end else begin
                            // Preserve the sequential controller's precedence:
                            // if accounting rejects, its reason is authoritative
                            // and no successful mutation remains to roll back.
                            result_accepted_q <= 1'b0;
                            result_reason_source_q <= acct_reason_source_now;
                            result_reason_code_q <= acct_reason_code_now;
                            state <= S_RESP;
                        end
                    end
                end

                S_ACCT_ROLLBACK_ISSUE: begin
                    if (acct_req_fire)
                        state <= S_ACCT_ROLLBACK_WAIT;
                end

                S_ACCT_ROLLBACK_WAIT: begin
                    if (acct_rsp_fire) begin
                        result_accepted_q <= 1'b0;
                        if (acct_rsp_ok) begin
                            result_reason_source_q <= rollback_reject_source;
                            result_reason_code_q <= rollback_reject_code;
                        end else begin
                            result_reason_source_q <= `HFT_RMIC_REASON_SRC_SYSTEM;
                            result_reason_code_q <= `HFT_RMIC_SYSTEM_REASON_ADMISSION_ROLLBACK_FAILED;
                        end
                        state <= S_RESP;
                    end
                end

                S_STORE_ROLLBACK_ISSUE: begin
                    if (store_req_fire)
                        state <= S_STORE_ROLLBACK_WAIT;
                end

                S_STORE_ROLLBACK_WAIT: begin
                    if (store_rsp_fire) begin
                        result_accepted_q <= 1'b0;
                        if (store_rsp_ok) begin
                            result_reason_source_q <= rollback_reject_source;
                            result_reason_code_q <= rollback_reject_code;
                        end else begin
                            result_reason_source_q <= `HFT_RMIC_REASON_SRC_SYSTEM;
                            result_reason_code_q <= `HFT_RMIC_SYSTEM_REASON_ADMISSION_ROLLBACK_FAILED;
                        end
                        state <= S_RESP;
                    end
                end

                S_RESP: begin
                    if (result_ready)
                        state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

    wire _unused_store_rsp_found = store_rsp_found;
endmodule
