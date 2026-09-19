`timescale 1ns/1ps
`include "hft_rmic_accounting_defs.svh"
`include "hft_rmic_policy_defs.svh"

module tb_hft_rmic_prospective_cl_issue_v1;
    localparam [2:0] STORE_ST_OK = 3'd0;
    reg clk=0; always #5 clk=~clk;
    reg rst_n=0;

    reg order_valid=0; wire order_ready; reg [255:0] order_data=0;
    reg policy_pass=1;
    reg [1:0] policy_reason_source=`HFT_RMIC_REASON_SRC_POLICY;
    reg [7:0] policy_reason_code=`HFT_RMIC_POLICY_REASON_PASS;
    reg [31:0] order_id=32'h1001;
    reg [7:0] account_id=8'h11,product_id=8'h22;
    reg side=0; reg [7:0] position_effect=8'h4f,order_type=8'h32,tif=8'h30;
    reg [31:0] limit_price=32'd12345; reg [15:0] qty=16'd3;

    wire result_valid; reg result_ready=1; wire result_accepted;
    wire [1:0] result_reason_source; wire [7:0] result_reason_code;
    wire [31:0] result_order_id; wire [255:0] result_order_data;

    wire acct_req_valid; reg acct_req_ready=1; wire [7:0] acct_req_account_id,acct_req_product_id;
    wire [2:0] acct_req_event_kind; wire acct_req_side; wire [7:0] acct_req_position_effect;
    wire [15:0] acct_req_order_qty,acct_req_fill_qty,acct_req_release_qty;
    reg acct_rsp_valid=0,acct_rsp_ok=0; reg [1:0] acct_rsp_reason_source=`HFT_RMIC_REASON_SRC_POLICY;
    reg [7:0] acct_rsp_reason_code=`HFT_RMIC_POLICY_REASON_PASS; wire acct_rsp_ready;

    wire store_req_valid; reg store_req_ready=1; wire [1:0] store_req_op;
    wire [31:0] store_req_order_id; wire [7:0] store_req_account_id,store_req_product_id;
    wire store_req_side; wire [7:0] store_req_position_effect,store_req_order_type,store_req_tif;
    wire [31:0] store_req_limit_price; wire [15:0] store_req_remaining_qty;
    reg store_rsp_valid=0,store_rsp_ok=0,store_rsp_found=0; reg [2:0] store_rsp_status=STORE_ST_OK;
    wire store_rsp_ready;

    hft_rmic_cl2ex_parallel_admission_v1 #(
        .ENABLE_FAST_SUCCESS_BYPASS(1),
        .ENABLE_PROSPECTIVE_ISSUE(1)
    ) dut (
        .clk(clk),.rst_n(rst_n),
        .order_valid(order_valid),.order_ready(order_ready),.order_data(order_data),
        .policy_pass(policy_pass),.policy_reason_source(policy_reason_source),.policy_reason_code(policy_reason_code),
        .order_id(order_id),.account_id(account_id),.product_id(product_id),.side(side),
        .position_effect(position_effect),.order_type(order_type),.tif(tif),.limit_price(limit_price),.qty(qty),
        .result_valid(result_valid),.result_ready(result_ready),.result_accepted(result_accepted),
        .result_reason_source(result_reason_source),.result_reason_code(result_reason_code),
        .result_order_id(result_order_id),.result_order_data(result_order_data),
        .acct_req_valid(acct_req_valid),.acct_req_ready(acct_req_ready),
        .acct_req_account_id(acct_req_account_id),.acct_req_product_id(acct_req_product_id),
        .acct_req_event_kind(acct_req_event_kind),.acct_req_side(acct_req_side),
        .acct_req_position_effect(acct_req_position_effect),.acct_req_order_qty(acct_req_order_qty),
        .acct_req_fill_qty(acct_req_fill_qty),.acct_req_release_qty(acct_req_release_qty),
        .acct_rsp_valid(acct_rsp_valid),.acct_rsp_ready(acct_rsp_ready),.acct_rsp_ok(acct_rsp_ok),
        .acct_rsp_reason_source(acct_rsp_reason_source),.acct_rsp_reason_code(acct_rsp_reason_code),
        .store_req_valid(store_req_valid),.store_req_ready(store_req_ready),.store_req_op(store_req_op),
        .store_req_order_id(store_req_order_id),.store_req_account_id(store_req_account_id),
        .store_req_product_id(store_req_product_id),.store_req_side(store_req_side),
        .store_req_position_effect(store_req_position_effect),.store_req_order_type(store_req_order_type),
        .store_req_tif(store_req_tif),.store_req_limit_price(store_req_limit_price),
        .store_req_remaining_qty(store_req_remaining_qty),.store_rsp_valid(store_rsp_valid),
        .store_rsp_ready(store_rsp_ready),.store_rsp_ok(store_rsp_ok),.store_rsp_found(store_rsp_found),
        .store_rsp_status(store_rsp_status)
    );

    task fail; input [8*120-1:0] msg; begin $display("TEST_FAIL %0s",msg); $fatal(1); end endtask

    task drive_live_order(input [31:0] oid,input bit pass);
      begin
        @(negedge clk);
        order_id=oid; order_data={224'd0,oid}; policy_pass=pass; order_valid=1;
        #1;
      end
    endtask

    task clear_order;
      begin @(negedge clk); order_valid=0; end
    endtask

    task send_success_responses;
      begin
        while(!acct_rsp_ready || !store_rsp_ready) @(posedge clk);
        @(negedge clk);
        acct_rsp_ok=1; acct_rsp_valid=1;
        store_rsp_ok=1; store_rsp_status=STORE_ST_OK; store_rsp_valid=1;
        #1;
        if(!result_valid || !result_accepted) fail("fast success result missing");
        @(posedge clk);
        @(negedge clk); acct_rsp_valid=0; store_rsp_valid=0;
      end
    endtask

    initial begin
        repeat(4) @(posedge clk); @(negedge clk); rst_n=1;

        // Both legs ready: mutation requests must be visible before the order
        // acceptance edge, with fields taken from the live normalized order.
        drive_live_order(32'h1001,1);
        if(!order_ready) fail("order not ready in idle");
        if(!acct_req_valid || !store_req_valid) fail("prospective requests missing");
        if(acct_req_event_kind!=`HFT_RMIC_ACCT_EVENT_RESERVE) fail("prospective acct op not RESERVE");
        if(acct_req_account_id!=account_id || acct_req_product_id!=product_id || acct_req_order_qty!=qty)
            fail("prospective accounting fields mismatch");
        if(store_req_order_id!=order_id || store_req_account_id!=account_id ||
           store_req_product_id!=product_id || store_req_remaining_qty!=qty)
            fail("prospective store fields mismatch");
        $display("I5_PROSPECTIVE_CL_SAME_CYCLE_ISSUE_PASS");
        @(posedge clk); // order + both mutation requests accepted
        clear_order();
        #1;
        if(acct_req_valid || store_req_valid) fail("accepted prospective requests reissued");
        send_success_responses();
        #1;
        if(result_valid) fail("consumed result left controller busy");
        $display("I5_PROSPECTIVE_CL_NO_DUPLICATE_PASS");

        // Partial ready: account request may handshake prospectively while
        // blocked store request retries from S_PARALLEL without duplicating
        // the account mutation.
        store_req_ready=0;
        drive_live_order(32'h1002,1);
        if(!acct_req_valid || !store_req_valid) fail("partial-ready prospective issue missing");
        @(posedge clk);
        clear_order();
        #1;
        if(acct_req_valid) fail("prospectively accepted account request was duplicated");
        if(!store_req_valid) fail("blocked store request was not retried");
        store_req_ready=1;
        @(posedge clk); // store retry accepted
        @(negedge clk); #1;
        if(store_req_valid) fail("store retry duplicated after handshake");
        send_success_responses();
        $display("I5_PROSPECTIVE_CL_PARTIAL_READY_PASS");

        // Policy reject must never expose a mutation request in the idle/order
        // acceptance cycle.
        policy_reason_source=`HFT_RMIC_REASON_SRC_POLICY;
        policy_reason_code=`HFT_RMIC_POLICY_REASON_KILL_SWITCH;
        drive_live_order(32'h1003,0);
        if(acct_req_valid || store_req_valid) fail("policy reject issued prospective mutation");
        @(posedge clk);
        clear_order();
        #1;
        if(!result_valid || result_accepted || result_reason_code!=`HFT_RMIC_POLICY_REASON_KILL_SWITCH)
            fail("policy reject result mismatch");
        @(posedge clk);
        $display("I5_PROSPECTIVE_CL_POLICY_NO_MUTATION_PASS");

        $display("HFT_RMIC_I5_PROSPECTIVE_CL_ISSUE_TB_PASS");
        $finish;
    end

    initial begin #300000; fail("timeout"); end
endmodule
