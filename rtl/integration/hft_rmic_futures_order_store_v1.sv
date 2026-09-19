`timescale 1ns/1ps

// Futures-aware outstanding-order context packed into the frozen RMIC 96-bit
// AMU value. Generic users deliberately bind to the pinned
// `amu_banked_double_hash_v2`. I5 may select an integration-owned derivative
// that removes only the frozen s0 request register to reduce AMU round-trip
// latency while preserving bank/hash/stash semantics.
//
// Payload (89/96 bits default):
//   account_id(8), product_id(8), side(1), PositionEffect(8), OrdType(8),
//   TIF(8), limit_price(32), remaining_qty(16).
//
// order_id remains the AMU key.  The integration layer therefore reuses the
// measured collision-capable RMIC order-store primitive without reusing the
// frozen stock-like account accounting semantics.
module hft_rmic_futures_order_store_v1 #(
    parameter integer TABLE_SIZE = 4096,
    parameter integer BANKS = 8,
    parameter integer STASH_SIZE = 4,
    parameter integer ORDER_ID_W = 32,
    parameter integer ACCOUNT_ID_W = 8,
    parameter integer PRODUCT_ID_W = 8,
    parameter integer PRICE_W = 32,
    parameter integer QTY_W = 16,
    parameter integer AMU_VALUE_W = 96,
    parameter integer ENABLE_FAST_AMU = 0
) (
    input  wire clk,
    input  wire rst_n,

    input  wire                         req_valid,
    output wire                         req_ready,
    input  wire [1:0]                   req_op,
    input  wire [ORDER_ID_W-1:0]        req_order_id,
    input  wire [ACCOUNT_ID_W-1:0]      req_account_id,
    input  wire [PRODUCT_ID_W-1:0]      req_product_id,
    input  wire                         req_side,
    input  wire [7:0]                   req_position_effect,
    input  wire [7:0]                   req_order_type,
    input  wire [7:0]                   req_tif,
    input  wire [PRICE_W-1:0]           req_limit_price,
    input  wire [QTY_W-1:0]             req_remaining_qty,

    output wire                         rsp_valid,
    input  wire                         rsp_ready,
    output wire                         rsp_ok,
    output wire                         rsp_found,
    output wire [2:0]                   rsp_status,
    output wire [ACCOUNT_ID_W-1:0]      rsp_account_id,
    output wire [PRODUCT_ID_W-1:0]      rsp_product_id,
    output wire                         rsp_side,
    output wire [7:0]                   rsp_position_effect,
    output wire [7:0]                   rsp_order_type,
    output wire [7:0]                   rsp_tif,
    output wire [PRICE_W-1:0]           rsp_limit_price,
    output wire [QTY_W-1:0]             rsp_remaining_qty,
    output wire [$clog2(BANKS)-1:0]     rsp_bank,
    output wire                         rsp_in_stash,
    output wire                         init_done
);
    localparam integer ACC_LSB = 0;
    localparam integer PROD_LSB = ACC_LSB + ACCOUNT_ID_W;
    localparam integer SIDE_BIT = PROD_LSB + PRODUCT_ID_W;
    localparam integer POS_EFFECT_LSB = SIDE_BIT + 1;
    localparam integer ORDER_TYPE_LSB = POS_EFFECT_LSB + 8;
    localparam integer TIF_LSB = ORDER_TYPE_LSB + 8;
    localparam integer PRICE_LSB = TIF_LSB + 8;
    localparam integer QTY_LSB = PRICE_LSB + PRICE_W;
    localparam integer PAYLOAD_W = QTY_LSB + QTY_W;

    wire [AMU_VALUE_W-1:0] req_value;
    wire [AMU_VALUE_W-1:0] rsp_value;

    assign req_value = {{(AMU_VALUE_W-PAYLOAD_W){1'b0}},
                        req_remaining_qty,
                        req_limit_price,
                        req_tif,
                        req_order_type,
                        req_position_effect,
                        req_side,
                        req_product_id,
                        req_account_id};

    assign rsp_account_id = rsp_value[ACC_LSB +: ACCOUNT_ID_W];
    assign rsp_product_id = rsp_value[PROD_LSB +: PRODUCT_ID_W];
    assign rsp_side = rsp_value[SIDE_BIT];
    assign rsp_position_effect = rsp_value[POS_EFFECT_LSB +: 8];
    assign rsp_order_type = rsp_value[ORDER_TYPE_LSB +: 8];
    assign rsp_tif = rsp_value[TIF_LSB +: 8];
    assign rsp_limit_price = rsp_value[PRICE_LSB +: PRICE_W];
    assign rsp_remaining_qty = rsp_value[QTY_LSB +: QTY_W];

    generate
        if (ENABLE_FAST_AMU != 0) begin : g_fast_amu
            hft_rmic_amu_banked_double_hash_fast_v1 #(
                .TABLE_SIZE(TABLE_SIZE),
                .BANKS(BANKS),
                .STASH_SIZE(STASH_SIZE),
                .KEY_W(ORDER_ID_W),
                .VALUE_W(AMU_VALUE_W)
            ) u_fast_amu (
                .clk(clk), .rst_n(rst_n),
                .req_valid(req_valid), .req_ready(req_ready),
                .req_op(req_op), .req_key(req_order_id), .req_value(req_value),
                .rsp_valid(rsp_valid), .rsp_ready(rsp_ready),
                .rsp_ok(rsp_ok), .rsp_found(rsp_found), .rsp_status(rsp_status),
                .rsp_value(rsp_value), .rsp_bank(rsp_bank),
                .rsp_in_stash(rsp_in_stash), .init_done(init_done)
            );
        end else begin : g_frozen_amu
            amu_banked_double_hash_v2 #(
                .TABLE_SIZE(TABLE_SIZE),
                .BANKS(BANKS),
                .STASH_SIZE(STASH_SIZE),
                .KEY_W(ORDER_ID_W),
                .VALUE_W(AMU_VALUE_W)
            ) u_frozen_amu (
                .clk(clk), .rst_n(rst_n),
                .req_valid(req_valid), .req_ready(req_ready),
                .req_op(req_op), .req_key(req_order_id), .req_value(req_value),
                .rsp_valid(rsp_valid), .rsp_ready(rsp_ready),
                .rsp_ok(rsp_ok), .rsp_found(rsp_found), .rsp_status(rsp_status),
                .rsp_value(rsp_value), .rsp_bank(rsp_bank),
                .rsp_in_stash(rsp_in_stash), .init_done(init_done)
            );
        end
    endgenerate

    initial begin
        if (AMU_VALUE_W < PAYLOAD_W)
            $error("AMU_VALUE_W=%0d is smaller than futures order payload=%0d",
                   AMU_VALUE_W, PAYLOAD_W);
        if (ORDER_ID_W != 32)
            $error("frozen AMU v2 hash contract currently requires 32-bit order keys");
    end
endmodule
