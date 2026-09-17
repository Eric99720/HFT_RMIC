`timescale 1ns/1ps
`include "hft_rmic_contract.svh"

module tb_hft_order_to_rmic;
    reg clk = 1'b0;
    always #5 clk = ~clk;
    reg rst_n = 1'b0;

    reg account_cfg_we = 1'b0;
    reg [3:0] account_cfg_index = 4'd0;
    reg account_cfg_valid = 1'b0;
    reg [31:0] account_cfg_key = 32'd0;
    reg [7:0] account_cfg_value = 8'd0;

    reg product_cfg_we = 1'b0;
    reg [3:0] product_cfg_index = 4'd0;
    reg product_cfg_valid = 1'b0;
    reg [15:0] product_cfg_key = 16'd0;
    reg [7:0] product_cfg_value = 8'd0;

    reg [255:0] order_data = 256'd0;

    wire [31:0] investor_account;
    wire [15:0] symbol_slot;

    wire account_hit, account_ambiguous;
    wire [7:0] account_value;
    wire product_hit, product_ambiguous;
    wire [7:0] product_value;

    configurable_exact_map #(.KEY_W(32), .VALUE_W(8), .ENTRIES(16)) u_account_map (
        .clk(clk), .rst_n(rst_n),
        .cfg_we(account_cfg_we), .cfg_index(account_cfg_index), .cfg_valid(account_cfg_valid),
        .cfg_key(account_cfg_key), .cfg_value(account_cfg_value),
        .lookup_key(investor_account), .lookup_hit(account_hit),
        .lookup_ambiguous(account_ambiguous), .lookup_value(account_value)
    );

    configurable_exact_map #(.KEY_W(16), .VALUE_W(8), .ENTRIES(16)) u_product_map (
        .clk(clk), .rst_n(rst_n),
        .cfg_we(product_cfg_we), .cfg_index(product_cfg_index), .cfg_valid(product_cfg_valid),
        .cfg_key(product_cfg_key), .cfg_value(product_cfg_value),
        .lookup_key(symbol_slot), .lookup_hit(product_hit),
        .lookup_ambiguous(product_ambiguous), .lookup_value(product_value)
    );

    wire [31:0] rmic_order_id;
    wire [7:0] rmic_account_id, rmic_product_id;
    wire rmic_side;
    wire [31:0] rmic_price, rmic_qty;
    wire [7:0] policy_tif, policy_position_effect, policy_investor_flag;
    wire [7:0] policy_flags, policy_order_type, packed_side_byte;
    wire [39:0] order_number;
    wire side_valid, account_valid, product_valid, adapter_valid;

    hft_order_to_rmic u_adapter (
        .order_data(order_data),
        .account_map_hit(account_hit), .account_map_ambiguous(account_ambiguous),
        .account_map_value(account_value),
        .product_map_hit(product_hit), .product_map_ambiguous(product_ambiguous),
        .product_map_value(product_value),
        .rmic_order_id(rmic_order_id), .rmic_account_id(rmic_account_id),
        .rmic_product_id(rmic_product_id), .rmic_side(rmic_side),
        .rmic_price(rmic_price), .rmic_qty(rmic_qty),
        .policy_tif(policy_tif), .policy_position_effect(policy_position_effect),
        .policy_investor_flag(policy_investor_flag), .policy_flags(policy_flags),
        .policy_order_type(policy_order_type), .investor_account(investor_account),
        .order_number(order_number), .symbol_slot(symbol_slot),
        .packed_side_byte(packed_side_byte), .side_valid(side_valid),
        .account_valid(account_valid), .product_valid(product_valid),
        .adapter_valid(adapter_valid)
    );

    task automatic cfg_account(input [3:0] idx, input valid, input [31:0] key, input [7:0] value);
    begin
        @(negedge clk);
        account_cfg_index = idx;
        account_cfg_valid = valid;
        account_cfg_key = key;
        account_cfg_value = value;
        account_cfg_we = 1'b1;
        @(negedge clk);
        account_cfg_we = 1'b0;
    end
    endtask

    task automatic cfg_product(input [3:0] idx, input valid, input [15:0] key, input [7:0] value);
    begin
        @(negedge clk);
        product_cfg_index = idx;
        product_cfg_valid = valid;
        product_cfg_key = key;
        product_cfg_value = value;
        product_cfg_we = 1'b1;
        @(negedge clk);
        product_cfg_we = 1'b0;
    end
    endtask

    task automatic build_order(input [7:0] side_byte, input [31:0] inv_acno, input [15:0] slot);
    begin
        order_data = 256'd0;
        order_data[`HFT_RMIC_PRICE_LSB +: 32] = 32'd123456;
        order_data[`HFT_RMIC_QTY_LSB +: 16] = 16'd321;
        order_data[`HFT_RMIC_SIDE_LSB +: 8] = side_byte;
        order_data[`HFT_RMIC_TIF_LSB +: 8] = 8'h03;
        order_data[`HFT_RMIC_POS_EFFECT_LSB +: 8] = 8'h4f;
        order_data[`HFT_RMIC_INV_FLAG_LSB +: 8] = 8'h41;
        order_data[`HFT_RMIC_INV_ACNO_LSB +: 32] = inv_acno;
        order_data[`HFT_RMIC_ORDER_ID_LSB +: 32] = 32'h12345678;
        order_data[`HFT_RMIC_ORDER_NO_LSB +: 40] = 40'h0102030405;
        order_data[`HFT_RMIC_SYMBOL_SLOT_LSB +: 16] = slot;
        order_data[`HFT_RMIC_FLAGS_LSB +: 8] = 8'hA5;
        order_data[`HFT_RMIC_ORD_TYPE_LSB +: 8] = 8'h02;
        #1;
    end
    endtask

    initial begin
        repeat (3) @(negedge clk);
        rst_n = 1'b1;

        cfg_account(4'd0, 1'b1, 32'h0012D687, 8'd3);
        cfg_product(4'd0, 1'b1, 16'd1, 8'd9);

        build_order(`HFT_RMIC_TMP_SIDE_BUY, 32'h0012D687, 16'd1);
        if (!adapter_valid) $fatal(1, "ADAPTER expected valid BUY mapping");
        if (rmic_order_id !== 32'h12345678) $fatal(1, "ADAPTER order id mismatch");
        if (rmic_account_id !== 8'd3 || rmic_product_id !== 8'd9) $fatal(1, "ADAPTER map mismatch");
        if (rmic_side !== `HFT_RMIC_RMIC_SIDE_BUY) $fatal(1, "ADAPTER BUY side translation mismatch");
        if (rmic_price !== 32'd123456 || rmic_qty !== 32'd321) $fatal(1, "ADAPTER price/qty mismatch");
        if (policy_tif !== 8'h03 || policy_position_effect !== 8'h4f || policy_investor_flag !== 8'h41)
            $fatal(1, "ADAPTER policy metadata mismatch");
        if (order_number !== 40'h0102030405 || policy_flags !== 8'hA5 || policy_order_type !== 8'h02)
            $fatal(1, "ADAPTER extended metadata mismatch");
        $display("HFT_RMIC_ADAPTER_BUY_PASS");

        build_order(`HFT_RMIC_TMP_SIDE_SELL, 32'h0012D687, 16'd1);
        if (!adapter_valid || rmic_side !== `HFT_RMIC_RMIC_SIDE_SELL)
            $fatal(1, "ADAPTER SELL side translation mismatch");
        $display("HFT_RMIC_ADAPTER_SELL_PASS");

        build_order(8'h7f, 32'h0012D687, 16'd1);
        if (side_valid || adapter_valid) $fatal(1, "ADAPTER invalid side was accepted");
        $display("HFT_RMIC_ADAPTER_SIDE_REJECT_PASS");

        build_order(`HFT_RMIC_TMP_SIDE_BUY, 32'hDEADBEEF, 16'd1);
        if (account_valid || adapter_valid) $fatal(1, "ADAPTER account miss was accepted");
        $display("HFT_RMIC_ADAPTER_ACCOUNT_MISS_PASS");

        build_order(`HFT_RMIC_TMP_SIDE_BUY, 32'h0012D687, 16'd99);
        if (product_valid || adapter_valid) $fatal(1, "ADAPTER product miss was accepted");
        $display("HFT_RMIC_ADAPTER_PRODUCT_MISS_PASS");

        // Duplicate account-map configuration is intentionally fail-closed.
        cfg_account(4'd1, 1'b1, 32'h0012D687, 8'd4);
        build_order(`HFT_RMIC_TMP_SIDE_BUY, 32'h0012D687, 16'd1);
        if (!account_ambiguous || account_valid || adapter_valid)
            $fatal(1, "ADAPTER ambiguous account mapping was not fail-closed");
        $display("HFT_RMIC_ADAPTER_AMBIGUOUS_MAP_PASS");

        $display("HFT_RMIC_ADAPTER_TB_PASS");
        $finish;
    end

    initial begin
        #100000;
        $fatal(1, "HFT_RMIC_ADAPTER_TB_TIMEOUT");
    end
endmodule
