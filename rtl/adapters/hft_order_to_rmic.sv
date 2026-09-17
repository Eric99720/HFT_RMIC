`timescale 1ns/1ps
`include "hft_rmic_contract.svh"

// Pure field adapter from the frozen HFT 256-bit strategy_order_data layout to
// the normalized request shape consumed by the frozen RMIC core.
//
// This module does not mutate order_data.  The original 256-bit payload is
// expected to travel alongside the normalized request and is forwarded only
// after risk approval.
module hft_order_to_rmic #(
    parameter integer ORDER_WIDTH = `HFT_RMIC_ORDER_WIDTH,
    parameter integer ACCOUNT_ID_W = 8,
    parameter integer PRODUCT_ID_W = 8
) (
    input  wire [ORDER_WIDTH-1:0] order_data,

    input  wire                    account_map_hit,
    input  wire                    account_map_ambiguous,
    input  wire [ACCOUNT_ID_W-1:0] account_map_value,

    input  wire                    product_map_hit,
    input  wire                    product_map_ambiguous,
    input  wire [PRODUCT_ID_W-1:0] product_map_value,

    output wire [31:0]             rmic_order_id,
    output wire [ACCOUNT_ID_W-1:0] rmic_account_id,
    output wire [PRODUCT_ID_W-1:0] rmic_product_id,
    output reg                     rmic_side,
    output wire [31:0]             rmic_price,
    output wire [31:0]             rmic_qty,

    output wire [7:0]              policy_tif,
    output wire [7:0]              policy_position_effect,
    output wire [7:0]              policy_investor_flag,
    output wire [7:0]              policy_flags,
    output wire [7:0]              policy_order_type,
    output wire [31:0]             investor_account,
    output wire [39:0]             order_number,
    output wire [15:0]             symbol_slot,
    output wire [7:0]              packed_side_byte,

    output reg                     side_valid,
    output wire                    account_valid,
    output wire                    product_valid,
    output wire                    adapter_valid
);
    assign rmic_price = order_data[`HFT_RMIC_PRICE_LSB +: 32];
    assign rmic_qty = {
        {(32-`HFT_RMIC_PACKED_QTY_WIDTH){1'b0}},
        order_data[`HFT_RMIC_QTY_LSB +: `HFT_RMIC_PACKED_QTY_WIDTH]
    };
    assign packed_side_byte = order_data[`HFT_RMIC_SIDE_LSB +: 8];
    assign policy_tif = order_data[`HFT_RMIC_TIF_LSB +: 8];
    assign policy_position_effect = order_data[`HFT_RMIC_POS_EFFECT_LSB +: 8];
    assign policy_investor_flag = order_data[`HFT_RMIC_INV_FLAG_LSB +: 8];
    assign investor_account = order_data[`HFT_RMIC_INV_ACNO_LSB +: 32];
    assign rmic_order_id = order_data[`HFT_RMIC_ORDER_ID_LSB +: 32];
    assign order_number = order_data[`HFT_RMIC_ORDER_NO_LSB +: 40];
    assign symbol_slot = order_data[`HFT_RMIC_SYMBOL_SLOT_LSB +: 16];
    assign policy_flags = order_data[`HFT_RMIC_FLAGS_LSB +: 8];
    assign policy_order_type = order_data[`HFT_RMIC_ORD_TYPE_LSB +: 8];

    assign rmic_account_id = account_map_value;
    assign rmic_product_id = product_map_value;

    always @(*) begin
        side_valid = 1'b1;
        case (packed_side_byte)
            `HFT_RMIC_TMP_SIDE_BUY:  rmic_side = `HFT_RMIC_RMIC_SIDE_BUY;
            `HFT_RMIC_TMP_SIDE_SELL: rmic_side = `HFT_RMIC_RMIC_SIDE_SELL;
            default: begin
                rmic_side = `HFT_RMIC_RMIC_SIDE_BUY;
                side_valid = 1'b0;
            end
        endcase
    end

    assign account_valid = account_map_hit && !account_map_ambiguous;
    assign product_valid = product_map_hit && !product_map_ambiguous;
    assign adapter_valid = side_valid && account_valid && product_valid;

    initial begin
        if (ORDER_WIDTH < 216)
            $error("hft_order_to_rmic ORDER_WIDTH is too small for frozen HFT layout");
    end
endmodule
