`timescale 1ns/1ps
`include "hft_rmic_policy_defs.svh"

module tb_hft_rmic_policy_gate;
    reg integration_ready = 1'b0;
    reg accounting_ready = 1'b0;
    reg global_kill = 1'b0;
    reg side_valid = 1'b1;
    reg account_map_hit = 1'b1;
    reg account_map_ambiguous = 1'b0;
    reg product_map_hit = 1'b1;
    reg product_map_ambiguous = 1'b0;
    reg qty_width_valid = 1'b1;
    reg [7:0] order_type = 8'h02;
    reg [7:0] tif = 8'h00;
    reg [7:0] position_effect = 8'h4f;
    reg [255:0] order_type_allow_mask = 256'd0;
    reg [255:0] tif_allow_mask = 256'd0;
    reg [255:0] position_effect_allow_mask = 256'd0;

    wire policy_pass;
    wire [1:0] reason_source;
    wire [7:0] reason_code;

    hft_rmic_policy_gate dut (.*);

    task automatic expect_reject(input [1:0] src, input [7:0] code, input [255:0] label_text);
    begin
        #1;
        if (policy_pass || reason_source !== src || reason_code !== code) begin
            $display("POLICY_FAIL %0s pass=%0b src=%0d code=%0d", label_text, policy_pass, reason_source, reason_code);
            $fatal(1);
        end
    end
    endtask

    initial begin
        order_type_allow_mask[8'h02] = 1'b1;
        tif_allow_mask[8'h00] = 1'b1;
        position_effect_allow_mask[8'h4f] = 1'b1;

        expect_reject(`HFT_RMIC_REASON_SRC_SYSTEM, `HFT_RMIC_SYSTEM_REASON_NOT_READY, "not_ready");

        integration_ready = 1'b1;
        expect_reject(`HFT_RMIC_REASON_SRC_POLICY, `HFT_RMIC_POLICY_REASON_ACCOUNTING_UNREADY, "accounting_unready");

        accounting_ready = 1'b1;
        #1;
        if (!policy_pass || reason_source !== `HFT_RMIC_REASON_SRC_POLICY || reason_code !== `HFT_RMIC_POLICY_REASON_PASS)
            $fatal(1, "POLICY expected configured request to pass");
        $display("HFT_RMIC_POLICY_PASS");

        global_kill = 1'b1;
        expect_reject(`HFT_RMIC_REASON_SRC_POLICY, `HFT_RMIC_POLICY_REASON_KILL_SWITCH, "kill_switch");
        global_kill = 1'b0;

        side_valid = 1'b0;
        expect_reject(`HFT_RMIC_REASON_SRC_ADAPTER, `HFT_RMIC_ADAPTER_REASON_SIDE_INVALID, "invalid_side");
        side_valid = 1'b1;

        account_map_hit = 1'b0;
        expect_reject(`HFT_RMIC_REASON_SRC_ADAPTER, `HFT_RMIC_ADAPTER_REASON_ACCOUNT_UNMAPPED, "account_miss");
        account_map_hit = 1'b1;
        account_map_ambiguous = 1'b1;
        expect_reject(`HFT_RMIC_REASON_SRC_ADAPTER, `HFT_RMIC_ADAPTER_REASON_ACCOUNT_AMBIGUOUS, "account_ambiguous");
        account_map_ambiguous = 1'b0;

        product_map_hit = 1'b0;
        expect_reject(`HFT_RMIC_REASON_SRC_ADAPTER, `HFT_RMIC_ADAPTER_REASON_PRODUCT_UNMAPPED, "product_miss");
        product_map_hit = 1'b1;
        product_map_ambiguous = 1'b1;
        expect_reject(`HFT_RMIC_REASON_SRC_ADAPTER, `HFT_RMIC_ADAPTER_REASON_PRODUCT_AMBIGUOUS, "product_ambiguous");
        product_map_ambiguous = 1'b0;

        qty_width_valid = 1'b0;
        expect_reject(`HFT_RMIC_REASON_SRC_ADAPTER, `HFT_RMIC_ADAPTER_REASON_QTY_WIDTH, "qty_width");
        qty_width_valid = 1'b1;

        order_type = 8'h99;
        expect_reject(`HFT_RMIC_REASON_SRC_POLICY, `HFT_RMIC_POLICY_REASON_ORDER_TYPE_UNSUPPORTED, "order_type");
        order_type = 8'h02;

        tif = 8'h03;
        expect_reject(`HFT_RMIC_REASON_SRC_POLICY, `HFT_RMIC_POLICY_REASON_TIF_UNSUPPORTED, "tif");
        tif = 8'h00;

        position_effect = 8'h55;
        expect_reject(`HFT_RMIC_REASON_SRC_POLICY, `HFT_RMIC_POLICY_REASON_POSITION_EFFECT, "position_effect");
        position_effect = 8'h4f;

        #1;
        if (!policy_pass) $fatal(1, "POLICY did not recover after reject cases");
        $display("HFT_RMIC_POLICY_FAIL_CLOSED_PASS");
        $display("HFT_RMIC_POLICY_TB_PASS");
        $finish;
    end
endmodule
