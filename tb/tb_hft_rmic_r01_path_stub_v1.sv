`timescale 1ns/1ps
`include "hft_rmic_contract.svh"
`include "hft_rmic_policy_defs.svh"
`include "taifex_tmp_v2187_defs.svh"

module tb_hft_rmic_r01_path_stub_v1;
    reg clk=0; always #5 clk=~clk; reg rst_n=0;
    reg legacy_order_valid=0; wire legacy_order_ready; reg [255:0] legacy_order_data=0;
    reg prebuild_order_valid=0; wire prebuild_order_accept; reg [255:0] prebuild_order_data=0;
    reg integration_ready=1,accounting_ready=1,global_kill=0,recovery_clear=0;
    wire recovery_required,store_init_done; wire [1:0] transaction_owner;
    reg [255:0] order_type_allow_mask=0,tif_allow_mask=0,position_effect_allow_mask=0;
    reg account_cfg_we=0; reg [3:0] account_cfg_index=0; reg account_cfg_valid=0; reg [31:0] account_cfg_key=0; reg [7:0] account_cfg_value=0;
    reg product_cfg_we=0; reg [3:0] product_cfg_index=0; reg product_cfg_valid=0; reg [15:0] product_cfg_key=0; reg [7:0] product_cfg_value=0;
    reg cfg_valid=0; wire cfg_ready; reg [7:0] cfg_account_id=0,cfg_product_id=0; reg cfg_enabled=0;
    reg [63:0] cfg_margin_budget=0,cfg_margin_per_contract=0; reg [15:0] cfg_long_position=0,cfg_short_position=0,cfg_pending_open_long=0,cfg_pending_open_short=0,cfg_reserved_close_long=0,cfg_reserved_close_short=0;
    wire cfg_done,cfg_ok; wire [7:0] cfg_reason_code;
    reg exec_commit_valid=0; wire exec_commit_ready; reg [7:0] exec_commit_msg_type=0,exec_commit_status_code=0,exec_commit_exec_type=0; reg [31:0] exec_commit_order_id=0; reg exec_commit_side=0; reg [7:0] exec_commit_position_effect=0; reg [31:0] exec_commit_order_price=0; reg [15:0] exec_commit_last_qty=0,exec_commit_leaves_qty=0,exec_commit_before_qty=0;
    wire exec_result_valid; reg exec_result_ready=1; wire exec_result_ok; wire [1:0] exec_result_reason_source; wire [7:0] exec_result_reason_code; wire [31:0] exec_result_order_id; wire [15:0] exec_result_remaining_qty;
    wire risk_reject_valid; reg risk_reject_ready=1; wire [31:0] risk_reject_order_id; wire [1:0] risk_reject_reason_source; wire [7:0] risk_reject_reason_code;
    reg [31:0] msg_epoch_s=32'h12345678; reg [15:0] msg_ms=16'h0203,fcm_id=16'h1111,session_id=16'h2222,cm_id=16'h3333,body_fcm_id=16'h4444; reg [63:0] user_define=64'h0102030405060708; reg [159:0] symbol_text=0; reg [7:0] order_source=8'h31; reg [23:0] info_source=24'h414243; reg [31:0] r01_msg_seq_num=1; reg network_ready=1;
    wire [63:0] tx_data; wire [7:0] tx_keep; wire tx_valid; reg tx_ready=1; wire tx_last; wire [15:0] tx_payload_len; wire tx_complete; wire [7:0] tx_message_type; wire [31:0] encoder_accepted_order_count,encoder_sent_r01_count;

    hft_rmic_r01_path_v1 dut (.*);
    task fail(input [8*100-1:0] msg); begin $display("TEST_FAIL %0s",msg); $fatal(1); end endtask
    function automatic [255:0] mk_order(input [31:0] oid,input [7:0] side,input [7:0] pe);
        reg [255:0] d; begin d=0; d[`HFT_RMIC_PRICE_LSB +:32]=32'd100; d[`HFT_RMIC_QTY_LSB +:16]=16'd1; d[`HFT_RMIC_SIDE_LSB +:8]=side; d[`HFT_RMIC_TIF_LSB +:8]=`HFT_RMIC_TAIFEX_TIF_ROD; d[`HFT_RMIC_POS_EFFECT_LSB +:8]=pe; d[`HFT_RMIC_INV_ACNO_LSB +:32]=32'h11112222; d[`HFT_RMIC_ORDER_ID_LSB +:32]=oid; d[`HFT_RMIC_SYMBOL_SLOT_LSB +:16]=0; d[`HFT_RMIC_ORD_TYPE_LSB +:8]=`HFT_RMIC_TAIFEX_ORD_LIMIT; mk_order=d; end
    endfunction
    task setup;
        begin
            repeat(4) @(posedge clk); @(negedge clk); rst_n=1; while(!store_init_done) @(posedge clk);
            @(negedge clk); account_cfg_we=1; account_cfg_valid=1; account_cfg_key=32'h11112222; account_cfg_value=1; product_cfg_we=1; product_cfg_valid=1; product_cfg_key=0; product_cfg_value=1;
            @(posedge clk); @(negedge clk); account_cfg_we=0; product_cfg_we=0;
            cfg_account_id=1; cfg_product_id=1; cfg_enabled=1; cfg_margin_budget=100000; cfg_margin_per_contract=1000; cfg_valid=1;
            while(!cfg_ready) @(posedge clk); @(posedge clk); @(negedge clk); cfg_valid=0;
        end
    endtask
    task send_legacy(input [255:0] d);
        begin @(negedge clk); legacy_order_data=d; legacy_order_valid=1; while(!legacy_order_ready) @(posedge clk); @(posedge clk); @(negedge clk); legacy_order_valid=0; end
    endtask
    task send_prebuild(input [255:0] d);
        begin @(negedge clk); prebuild_order_data=d; prebuild_order_valid=1; while(!prebuild_order_accept) @(posedge clk); @(posedge clk); @(negedge clk); prebuild_order_valid=0; end
    endtask
    task wait_r01(input [31:0] expected_count);
        integer g; begin g=0; while(encoder_sent_r01_count<expected_count) begin @(posedge clk); g=g+1; if(g>400) fail("R01 timeout"); end if(tx_message_type!=0 && tx_message_type!=101) fail("unexpected message type"); end
    endtask

    initial begin
        order_type_allow_mask[`HFT_RMIC_TAIFEX_ORD_LIMIT]=1; tif_allow_mask[`HFT_RMIC_TAIFEX_TIF_ROD]=1; position_effect_allow_mask[`HFT_RMIC_TAIFEX_POS_OPEN]=1; position_effect_allow_mask[`HFT_RMIC_TAIFEX_POS_CLOSE]=1;
        setup();
        send_legacy(mk_order(200,`HFT_RMIC_TMP_SIDE_BUY,`HFT_RMIC_TAIFEX_POS_OPEN)); wait_r01(1);
        $display("I4_LEGACY_RISK_TO_ENCODER_PASS");
        send_prebuild(mk_order(201,`HFT_RMIC_TMP_SIDE_BUY,`HFT_RMIC_TAIFEX_POS_OPEN)); wait_r01(2);
        $display("I4_PREBUILD_RISK_TO_ENCODER_PASS");

        // Both producers valid: frozen prebuild priority must prevent legacy handoff.
        @(negedge clk); legacy_order_data=mk_order(202,1,`HFT_RMIC_TAIFEX_POS_OPEN); prebuild_order_data=mk_order(203,1,`HFT_RMIC_TAIFEX_POS_OPEN); legacy_order_valid=1; prebuild_order_valid=1;
        while(!prebuild_order_accept) @(posedge clk); #1; if(legacy_order_ready) fail("legacy ready asserted during prebuild priority");
        @(posedge clk); @(negedge clk); prebuild_order_valid=0;
        while(!legacy_order_ready) @(posedge clk); @(posedge clk); @(negedge clk); legacy_order_valid=0;
        wait_r01(4); $display("I4_PREBUILD_PRIORITY_PASS");

        // Kill-switch reject must never reach the encoder.
        global_kill=1; send_prebuild(mk_order(204,1,`HFT_RMIC_TAIFEX_POS_OPEN));
        while(!risk_reject_valid) @(posedge clk); #1;
        if(risk_reject_order_id!=204 || risk_reject_reason_code!=`HFT_RMIC_POLICY_REASON_KILL_SWITCH) fail("reject telemetry mismatch");
        repeat(20) @(posedge clk); if(encoder_sent_r01_count!=4) fail("rejected order leaked to R01");
        $display("I4_RISK_REJECT_SUPPRESSES_R01_PASS");
        if(recovery_required) fail("unexpected recovery state");
        $display("HFT_RMIC_R01_PATH_STUB_V1_TB_PASS"); $finish;
    end
endmodule
