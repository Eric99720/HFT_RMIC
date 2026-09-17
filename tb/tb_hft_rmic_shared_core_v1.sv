`timescale 1ns/1ps
`include "hft_rmic_contract.svh"
`include "hft_rmic_policy_defs.svh"
`include "taifex_tmp_v2187_defs.svh"

module tb_hft_rmic_shared_core_v1;
    reg clk=0; always #5 clk=~clk;
    reg rst_n=0;
    reg integration_ready=1, accounting_ready=1, global_kill=0, recovery_clear=0;
    wire recovery_required, store_init_done; wire [1:0] transaction_owner;
    reg [255:0] order_type_allow_mask, tif_allow_mask, position_effect_allow_mask;

    reg account_cfg_we=0; reg [3:0] account_cfg_index=0; reg account_cfg_valid=0;
    reg [31:0] account_cfg_key=0; reg [7:0] account_cfg_value=0;
    reg product_cfg_we=0; reg [3:0] product_cfg_index=0; reg product_cfg_valid=0;
    reg [15:0] product_cfg_key=0; reg [7:0] product_cfg_value=0;

    reg cfg_valid=0; wire cfg_ready; reg [7:0] cfg_account_id=0,cfg_product_id=0; reg cfg_enabled=0;
    reg [63:0] cfg_margin_budget=0,cfg_margin_per_contract=0;
    reg [15:0] cfg_long_position=0,cfg_short_position=0,cfg_pending_open_long=0,cfg_pending_open_short=0;
    reg [15:0] cfg_reserved_close_long=0,cfg_reserved_close_short=0;
    wire cfg_done,cfg_ok; wire [7:0] cfg_reason_code;

    reg order_valid=0; wire order_ready; reg [255:0] order_data=0;
    wire accepted_order_valid; reg accepted_order_ready=1; wire [255:0] accepted_order_data; wire [31:0] accepted_order_id;
    wire reject_valid; reg reject_ready=1; wire [31:0] reject_order_id; wire [1:0] reject_reason_source; wire [7:0] reject_reason_code;

    reg exec_commit_valid=0; wire exec_commit_ready; reg [7:0] exec_commit_msg_type=0,exec_commit_status_code=0,exec_commit_exec_type=0;
    reg [31:0] exec_commit_order_id=0; reg exec_commit_side=0; reg [7:0] exec_commit_position_effect=0;
    reg [31:0] exec_commit_order_price=0; reg [15:0] exec_commit_last_qty=0,exec_commit_leaves_qty=0,exec_commit_before_qty=0;
    wire exec_result_valid; reg exec_result_ready=1; wire exec_result_ok; wire [1:0] exec_result_reason_source;
    wire [7:0] exec_result_reason_code; wire [31:0] exec_result_order_id; wire [15:0] exec_result_remaining_qty;

    hft_rmic_shared_core_v1 dut (.*);

    task fail(input [8*120-1:0] msg); begin $display("TEST_FAIL %0s",msg); $fatal(1); end endtask

    function automatic [255:0] mk_order;
        input [31:0] oid; input [31:0] price; input [15:0] qty;
        input [7:0] side_byte; input [7:0] pe;
        reg [255:0] d;
        begin
            d=0;
            d[`HFT_RMIC_PRICE_LSB +:32]=price;
            d[`HFT_RMIC_QTY_LSB +:16]=qty;
            d[`HFT_RMIC_SIDE_LSB +:8]=side_byte;
            d[`HFT_RMIC_TIF_LSB +:8]=`HFT_RMIC_TAIFEX_TIF_ROD;
            d[`HFT_RMIC_POS_EFFECT_LSB +:8]=pe;
            d[`HFT_RMIC_INV_ACNO_LSB +:32]=32'h11112222;
            d[`HFT_RMIC_ORDER_ID_LSB +:32]=oid;
            d[`HFT_RMIC_SYMBOL_SLOT_LSB +:16]=16'd0;
            d[`HFT_RMIC_ORD_TYPE_LSB +:8]=`HFT_RMIC_TAIFEX_ORD_LIMIT;
            mk_order=d;
        end
    endfunction

    task map_cfg;
        begin
            @(negedge clk); account_cfg_we=1; account_cfg_valid=1; account_cfg_key=32'h11112222; account_cfg_value=8'd1;
            product_cfg_we=1; product_cfg_valid=1; product_cfg_key=16'd0; product_cfg_value=8'd1;
            @(posedge clk); @(negedge clk); account_cfg_we=0; product_cfg_we=0;
        end
    endtask

    task state_cfg;
        begin
            @(negedge clk);
            cfg_account_id=1; cfg_product_id=1; cfg_enabled=1;
            cfg_margin_budget=64'd100000; cfg_margin_per_contract=64'd1000;
            cfg_long_position=0; cfg_short_position=0; cfg_pending_open_long=0; cfg_pending_open_short=0;
            cfg_reserved_close_long=0; cfg_reserved_close_short=0; cfg_valid=1;
            while(!cfg_ready) @(posedge clk);
            @(posedge clk); @(negedge clk); cfg_valid=0;
            if(!cfg_done || !cfg_ok) fail("state config failed");
        end
    endtask

    task send_order(input [255:0] d, input exp_accept);
        integer guard;
        begin
            @(negedge clk); order_data=d; order_valid=1; guard=0;
            while(!(order_valid&&order_ready)) begin @(posedge clk); guard=guard+1; if(guard>200) fail("order handshake timeout"); end
            @(negedge clk); order_valid=0;
            guard=0;
            while(!accepted_order_valid && !reject_valid) begin @(posedge clk); guard=guard+1; if(guard>300) fail("order result timeout"); end
            #1;
            if(exp_accept && !accepted_order_valid) fail("expected accept");
            if(!exp_accept && !reject_valid) fail("expected reject");
            if(exp_accept && accepted_order_data!==d) fail("accepted payload changed");
            @(posedge clk);
        end
    endtask

    task send_exec(input [31:0] oid,input [7:0] exectype,input side,input [7:0] pe,input [15:0] lastq,input [15:0] leaves,input [15:0] beforeq);
        integer guard;
        begin
            @(negedge clk);
            exec_commit_msg_type=`HFT_RMIC_TAIFEX_MSG_R02; exec_commit_status_code=0; exec_commit_exec_type=exectype;
            exec_commit_order_id=oid; exec_commit_side=side; exec_commit_position_effect=pe;
            exec_commit_order_price=32'd100; exec_commit_last_qty=lastq; exec_commit_leaves_qty=leaves; exec_commit_before_qty=beforeq;
            exec_commit_valid=1; guard=0;
            while(!(exec_commit_valid&&exec_commit_ready)) begin @(posedge clk); guard=guard+1; if(guard>200) fail("exec handshake timeout"); end
            @(negedge clk); exec_commit_valid=0; guard=0;
            while(!exec_result_valid) begin @(posedge clk); guard=guard+1; if(guard>400) fail("exec result timeout"); end
            #1; if(!exec_result_ok) fail("exec expected success");
            @(posedge clk);
        end
    endtask

    initial begin
        order_type_allow_mask=0; tif_allow_mask=0; position_effect_allow_mask=0;
        order_type_allow_mask[`HFT_RMIC_TAIFEX_ORD_LIMIT]=1'b1;
        tif_allow_mask[`HFT_RMIC_TAIFEX_TIF_ROD]=1'b1;
        position_effect_allow_mask[`HFT_RMIC_TAIFEX_POS_OPEN]=1'b1;
        position_effect_allow_mask[`HFT_RMIC_TAIFEX_POS_CLOSE]=1'b1;
        repeat(4) @(posedge clk); @(negedge clk); rst_n=1;
        while(!store_init_done) @(posedge clk);
        map_cfg(); state_cfg();

        // BUY OPEN two contracts: reserve + context insert.
        send_order(mk_order(100,100,2,`HFT_RMIC_TMP_SIDE_BUY,`HFT_RMIC_TAIFEX_POS_OPEN),1);
        if(accepted_order_id!=100) fail("accepted order id mismatch");
        $display("I4_SHARED_CL_ACCEPT_PASS");

        // Full committed fill updates long position and deletes context.
        send_exec(100,`HFT_RMIC_TAIFEX_EXEC_TRADE,`HFT_RMIC_RMIC_SIDE_BUY,`HFT_RMIC_TAIFEX_POS_OPEN,2,0,2);
        $display("I4_SHARED_EXEC_FILL_PASS");

        // SELL CLOSE can only pass if the committed fill above updated the same
        // shared futures-state owner to long_position=2.
        send_order(mk_order(101,100,2,`HFT_RMIC_TMP_SIDE_SELL,`HFT_RMIC_TAIFEX_POS_CLOSE),1);
        $display("I4_SHARED_STATE_CLOSED_LOOP_PASS");

        // Create an outstanding OPEN order that will be cancelled while a new
        // order is presented. Execution must win owner acquisition.
        send_order(mk_order(102,100,1,`HFT_RMIC_TMP_SIDE_BUY,`HFT_RMIC_TAIFEX_POS_OPEN),1);
        @(negedge clk);
        order_data=mk_order(103,100,1,`HFT_RMIC_TMP_SIDE_BUY,`HFT_RMIC_TAIFEX_POS_OPEN); order_valid=1;
        exec_commit_msg_type=`HFT_RMIC_TAIFEX_MSG_R02; exec_commit_status_code=0;
        exec_commit_exec_type=`HFT_RMIC_TAIFEX_EXEC_CANCEL; exec_commit_order_id=102;
        exec_commit_side=`HFT_RMIC_RMIC_SIDE_BUY; exec_commit_position_effect=`HFT_RMIC_TAIFEX_POS_OPEN;
        exec_commit_order_price=100; exec_commit_last_qty=0; exec_commit_leaves_qty=0; exec_commit_before_qty=1;
        exec_commit_valid=1;
        #1; if(order_ready) fail("CL must be backpressured while EX competes");
        while(!exec_commit_ready) @(posedge clk);
        @(posedge clk); @(negedge clk); exec_commit_valid=0;
        while(!exec_result_valid) @(posedge clk);
        if(!exec_result_ok) fail("priority cancel failed");
        while(!order_ready) @(posedge clk);
        @(posedge clk); @(negedge clk); order_valid=0;
        while(!accepted_order_valid) @(posedge clk);
        if(accepted_order_id!=103) fail("deferred CL order failed");
        @(posedge clk);
        $display("I4_EXEC_PRIORITY_AND_OWNER_LOCK_PASS");

        global_kill=1;
        send_order(mk_order(104,100,1,`HFT_RMIC_TMP_SIDE_BUY,`HFT_RMIC_TAIFEX_POS_OPEN),0);
        if(reject_reason_source!=`HFT_RMIC_REASON_SRC_POLICY || reject_reason_code!=`HFT_RMIC_POLICY_REASON_KILL_SWITCH)
            fail("kill reject reason mismatch");
        $display("I4_SHARED_FAIL_CLOSED_PASS");

        if(recovery_required) fail("unexpected recovery_required");
        $display("HFT_RMIC_SHARED_CORE_V1_TB_PASS");
        $finish;
    end
endmodule
