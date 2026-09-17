`timescale 1ns/1ps
`include "hft_rmic_accounting_defs.svh"
`include "hft_rmic_policy_defs.svh"

// Atomic CL2EX admission controller.
//
// Transaction order:
//   policy PASS -> futures RESERVE -> order-context INSERT -> PASS
//
// If INSERT fails after a successful RESERVE, the controller issues a matching
// RELEASE before returning the normal reject.  If RELEASE itself fails, the
// transaction fails closed with ADMISSION_ROLLBACK_FAILED and requires explicit
// recovery; the original HFT payload is never marked accepted.
module hft_rmic_cl2ex_admission_v1 #(
    parameter integer ORDER_WIDTH = 256,
    parameter integer ACCOUNT_ID_W = 8,
    parameter integer PRODUCT_ID_W = 8,
    parameter integer PRICE_W = 32,
    parameter integer QTY_W = 16
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
    output reg                          result_accepted,
    output reg [1:0]                    result_reason_source,
    output reg [7:0]                    result_reason_code,
    output reg [31:0]                   result_order_id,
    output reg [ORDER_WIDTH-1:0]        result_order_data,

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
    input  wire [7:0]                   acct_rsp_reason_code,

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
    input  wire [2:0]                   store_rsp_status
);
    localparam [1:0] STORE_INSERT = 2'd1;
    localparam [2:0] STORE_ST_OK     = 3'd0;
    localparam [2:0] STORE_ST_EXISTS = 3'd2;
    localparam [2:0] STORE_ST_FULL   = 3'd3;

    localparam [3:0] S_IDLE           = 4'd0;
    localparam [3:0] S_RESERVE_ISSUE  = 4'd1;
    localparam [3:0] S_RESERVE_WAIT   = 4'd2;
    localparam [3:0] S_INSERT_ISSUE   = 4'd3;
    localparam [3:0] S_INSERT_WAIT    = 4'd4;
    localparam [3:0] S_ROLLBACK_ISSUE = 4'd5;
    localparam [3:0] S_ROLLBACK_WAIT  = 4'd6;
    localparam [3:0] S_RESP           = 4'd7;

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

    reg [1:0] rollback_reject_source;
    reg [7:0] rollback_reject_code;

    assign order_ready = (state == S_IDLE);
    assign result_valid = (state == S_RESP);
    wire order_fire = order_valid && order_ready;

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
            S_RESERVE_ISSUE: begin
                acct_req_valid = 1'b1;
                acct_req_event_kind = `HFT_RMIC_ACCT_EVENT_RESERVE;
                acct_req_order_qty = tx_qty;
            end
            S_RESERVE_WAIT: begin
                acct_rsp_ready = 1'b1;
            end
            S_INSERT_ISSUE: begin
                store_req_valid = 1'b1;
            end
            S_INSERT_WAIT: begin
                store_rsp_ready = 1'b1;
            end
            S_ROLLBACK_ISSUE: begin
                acct_req_valid = 1'b1;
                acct_req_event_kind = `HFT_RMIC_ACCT_EVENT_RELEASE;
                acct_req_release_qty = tx_qty;
            end
            S_ROLLBACK_WAIT: begin
                acct_rsp_ready = 1'b1;
            end
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
            rollback_reject_source <= `HFT_RMIC_REASON_SRC_SYSTEM;
            rollback_reject_code <= `HFT_RMIC_SYSTEM_REASON_ORDER_STORE_FAILURE;
            result_accepted <= 1'b0;
            result_reason_source <= `HFT_RMIC_REASON_SRC_SYSTEM;
            result_reason_code <= `HFT_RMIC_SYSTEM_REASON_NOT_READY;
            result_order_id <= 32'd0;
            result_order_data <= {ORDER_WIDTH{1'b0}};
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

                        result_order_data <= order_data;
                        result_order_id <= order_id;
                        result_accepted <= 1'b0;
                        result_reason_source <= policy_reason_source;
                        result_reason_code <= policy_reason_code;

                        if (policy_pass) begin
                            state <= S_RESERVE_ISSUE;
                        end else begin
                            state <= S_RESP;
                        end
                    end
                end

                S_RESERVE_ISSUE: begin
                    if (acct_req_valid && acct_req_ready)
                        state <= S_RESERVE_WAIT;
                end

                S_RESERVE_WAIT: begin
                    if (acct_rsp_valid && acct_rsp_ready) begin
                        if (acct_rsp_ok) begin
                            state <= S_INSERT_ISSUE;
                        end else begin
                            result_accepted <= 1'b0;
                            result_reason_source <= acct_rsp_reason_source;
                            result_reason_code <= acct_rsp_reason_code;
                            state <= S_RESP;
                        end
                    end
                end

                S_INSERT_ISSUE: begin
                    if (store_req_valid && store_req_ready)
                        state <= S_INSERT_WAIT;
                end

                S_INSERT_WAIT: begin
                    if (store_rsp_valid && store_rsp_ready) begin
                        if (store_rsp_ok && store_rsp_found && (store_rsp_status == STORE_ST_OK)) begin
                            result_accepted <= 1'b1;
                            result_reason_source <= `HFT_RMIC_REASON_SRC_SYSTEM;
                            result_reason_code <= `HFT_RMIC_SYSTEM_REASON_PASS;
                            state <= S_RESP;
                        end else begin
                            rollback_reject_source <= `HFT_RMIC_REASON_SRC_SYSTEM;
                            rollback_reject_code <= store_failure_reason(store_rsp_status);
                            state <= S_ROLLBACK_ISSUE;
                        end
                    end
                end

                S_ROLLBACK_ISSUE: begin
                    if (acct_req_valid && acct_req_ready)
                        state <= S_ROLLBACK_WAIT;
                end

                S_ROLLBACK_WAIT: begin
                    if (acct_rsp_valid && acct_rsp_ready) begin
                        result_accepted <= 1'b0;
                        if (acct_rsp_ok) begin
                            result_reason_source <= rollback_reject_source;
                            result_reason_code <= rollback_reject_code;
                        end else begin
                            result_reason_source <= `HFT_RMIC_REASON_SRC_SYSTEM;
                            result_reason_code <= `HFT_RMIC_SYSTEM_REASON_ADMISSION_ROLLBACK_FAILED;
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
endmodule
