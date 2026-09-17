`timescale 1ns/1ps
`include "hft_rmic_policy_defs.svh"

// Fail-closed policy shell in front of the frozen RMIC M5.4 core.
//
// This module intentionally does not encode exchange-specific TAIFEX business
// rules. Supported order type / TIF / position-effect values are supplied as
// configuration masks. The final futures accounting engine must assert
// accounting_ready only after its semantics are configured and validated.
module hft_rmic_policy_gate (
    input  wire        integration_ready,
    input  wire        accounting_ready,
    input  wire        global_kill,

    input  wire        side_valid,
    input  wire        account_map_hit,
    input  wire        account_map_ambiguous,
    input  wire        product_map_hit,
    input  wire        product_map_ambiguous,
    input  wire        qty_width_valid,

    input  wire [7:0]  order_type,
    input  wire [7:0]  tif,
    input  wire [7:0]  position_effect,

    input  wire [255:0] order_type_allow_mask,
    input  wire [255:0] tif_allow_mask,
    input  wire [255:0] position_effect_allow_mask,

    output reg         policy_pass,
    output reg [1:0]   reason_source,
    output reg [7:0]   reason_code
);
    wire order_type_allowed = order_type_allow_mask[order_type];
    wire tif_allowed = tif_allow_mask[tif];
    wire position_effect_allowed = position_effect_allow_mask[position_effect];

    always @(*) begin
        policy_pass = 1'b0;
        reason_source = `HFT_RMIC_REASON_SRC_POLICY;
        reason_code = `HFT_RMIC_POLICY_REASON_PASS;

        // Adapter failures have precedence because no normalized RMIC request
        // can be trusted when field decoding or identifier mapping is invalid.
        if (!side_valid) begin
            reason_source = `HFT_RMIC_REASON_SRC_ADAPTER;
            reason_code = `HFT_RMIC_ADAPTER_REASON_SIDE_INVALID;
        end else if (account_map_ambiguous) begin
            reason_source = `HFT_RMIC_REASON_SRC_ADAPTER;
            reason_code = `HFT_RMIC_ADAPTER_REASON_ACCOUNT_AMBIGUOUS;
        end else if (!account_map_hit) begin
            reason_source = `HFT_RMIC_REASON_SRC_ADAPTER;
            reason_code = `HFT_RMIC_ADAPTER_REASON_ACCOUNT_UNMAPPED;
        end else if (product_map_ambiguous) begin
            reason_source = `HFT_RMIC_REASON_SRC_ADAPTER;
            reason_code = `HFT_RMIC_ADAPTER_REASON_PRODUCT_AMBIGUOUS;
        end else if (!product_map_hit) begin
            reason_source = `HFT_RMIC_REASON_SRC_ADAPTER;
            reason_code = `HFT_RMIC_ADAPTER_REASON_PRODUCT_UNMAPPED;
        end else if (!qty_width_valid) begin
            reason_source = `HFT_RMIC_REASON_SRC_ADAPTER;
            reason_code = `HFT_RMIC_ADAPTER_REASON_QTY_WIDTH;
        end else if (!integration_ready) begin
            reason_source = `HFT_RMIC_REASON_SRC_SYSTEM;
            reason_code = `HFT_RMIC_SYSTEM_REASON_NOT_READY;
        end else if (global_kill) begin
            reason_source = `HFT_RMIC_REASON_SRC_POLICY;
            reason_code = `HFT_RMIC_POLICY_REASON_KILL_SWITCH;
        end else if (!accounting_ready) begin
            reason_source = `HFT_RMIC_REASON_SRC_POLICY;
            reason_code = `HFT_RMIC_POLICY_REASON_ACCOUNTING_UNREADY;
        end else if (!order_type_allowed) begin
            reason_source = `HFT_RMIC_REASON_SRC_POLICY;
            reason_code = `HFT_RMIC_POLICY_REASON_ORDER_TYPE_UNSUPPORTED;
        end else if (!tif_allowed) begin
            reason_source = `HFT_RMIC_REASON_SRC_POLICY;
            reason_code = `HFT_RMIC_POLICY_REASON_TIF_UNSUPPORTED;
        end else if (!position_effect_allowed) begin
            reason_source = `HFT_RMIC_REASON_SRC_POLICY;
            reason_code = `HFT_RMIC_POLICY_REASON_POSITION_EFFECT;
        end else begin
            policy_pass = 1'b1;
            reason_source = `HFT_RMIC_REASON_SRC_POLICY;
            reason_code = `HFT_RMIC_POLICY_REASON_PASS;
        end
    end
endmodule
