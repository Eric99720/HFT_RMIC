`timescale 1ns/1ps
`include "hft_rmic_accounting_defs.svh"
`include "hft_rmic_policy_defs.svh"

module tb_hft_rmic_fast_success_join_v1;
    localparam [2:0] STORE_ST_OK = 3'd0;
    reg clk=0; always #5 clk=~clk;
    reg rst_n=0;

    reg order_valid=0;
    wire order_ready;
    reg [255:0] order_data=256'h0;
    reg policy_pass=1;
    reg [1:0] policy_reason_source=`HFT_RMIC_REASON_SRC_POLICY;
    reg [7:0] policy_reason_code=`HFT_RMIC_POLICY_REASON_PASS;
    reg [31:0] order_id=32'h1234;
    reg [7:0] account_id=1, product_id=2;
    reg side=0;
    reg [7:0] position_effect=8'h4f, order_type=8'h32, tif=8'h30;
    reg [31:0] limit_price=1000;
    reg [15:0] qty=2;

    wire result_valid;
    reg result_ready=0;
    wire result_accepted;
    wire [1:0] result_reason_source;
    wire [7:0] result_reason_code;
    wire [31:0] result_order_id;
    wire [255:0] result_order_data;

    wire acct_req_valid; reg acct_req_ready=1;
    wire [7:0] acct_req_account_id, acct_req_product_id;
    wire [2:0] acct_req_event_kind; wire acct_req_side;
    wire [7:0] acct_req_position_effect; wire [15:0] acct_req_order_qty,acct_req_fill_qty,acct_req_release_qty;
    reg acct_rsp_valid=0,acct_rsp_ok=0; reg [1:0] acct_rsp_reason_source=`HFT_RMIC_REASON_SRC_POLICY;
    reg [7:0] acct_rsp_reason_code=`HFT_RMIC_POLICY_REASON_PASS; wire acct_rsp_ready;

    wire store_req_valid; reg store_req_ready=1; wire [1:0] store_req_op;
    wire [31:0] store_req_order_id; wire [7:0] store_req_account_id,store_req_product_id;
    wire store_req_side; wire [7:0] store_req_position_effect,store_req_order_type,store_req_tif;
    wire [31:0] store_req_limit_price; wire [15:0] store_req_remaining_qty;
    reg store_rsp_valid=0,store_rsp_ok=0,store_rsp_found=0; reg [2:0] store_rsp_status=STORE_ST_OK;
    wire store_rsp_ready;

    hft_rmic_cl2ex_parallel_admission_v1 #(
        .ENABLE_FAST_SUCCESS_BYPASS(1)
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

    task start_order(input [31:0] oid);
      begin
        @(negedge clk);
        order_id=oid; order_data={224'd0,oid}; order_valid=1;
        while(!order_ready) @(posedge clk);
        @(posedge clk);
        @(negedge clk); order_valid=0;
        #1;
        if(!acct_req_valid || !store_req_valid) fail("parallel requests not issued");
        @(posedge clk); // request handshakes
        @(negedge clk);
        #1;
        if(!acct_rsp_ready || !store_rsp_ready) fail("responses not ready after issue");
      end
    endtask

    initial begin
        repeat(4) @(posedge clk);
        @(negedge clk); rst_n=1;

        // Ready consumer: result must be visible in the exact cycle in which
        // the final registered downstream responses are presented.
        start_order(32'h1001);
        result_ready=1;
        acct_rsp_ok=1; store_rsp_ok=1; store_rsp_status=STORE_ST_OK;
        acct_rsp_valid=1; store_rsp_valid=1;
        #1;
        if(!result_valid || !result_accepted) fail("same-cycle success bypass missing");
        if(result_order_id!=32'h1001 || result_order_data!={224'd0,32'h1001}) fail("fast result payload mismatch");
        $display("I5_FAST_SUCCESS_JOIN_COMBINATIONAL_PASS");
        @(posedge clk);
        @(negedge clk);
        acct_rsp_valid=0; store_rsp_valid=0; result_ready=0;
        #1;
        if(result_valid) fail("consumed fast result left a response bubble");
        if(!order_ready) fail("controller did not return directly to idle");
        $display("I5_FAST_SUCCESS_JOIN_ZERO_BUBBLE_PASS");

        // Backpressured consumer: same-cycle fast result appears, then falls
        // back to registered S_RESP and remains stable until consumed.
        start_order(32'h1002);
        result_ready=0;
        acct_rsp_ok=1; store_rsp_ok=1; store_rsp_status=STORE_ST_OK;
        acct_rsp_valid=1; store_rsp_valid=1;
        #1;
        if(!result_valid || !result_accepted) fail("backpressured fast result not exposed");
        @(posedge clk);
        @(negedge clk);
        acct_rsp_valid=0; store_rsp_valid=0;
        #1;
        if(!result_valid || !result_accepted || result_order_id!=32'h1002)
            fail("fast result was not retained under backpressure");
        repeat(2) begin
            @(posedge clk); #1;
            if(!result_valid || !result_accepted || result_order_id!=32'h1002)
                fail("registered result changed under backpressure");
        end
        @(negedge clk); result_ready=1;
        @(posedge clk);
        @(negedge clk); result_ready=0;
        #1;
        if(result_valid) fail("registered fallback did not drain");
        $display("I5_FAST_SUCCESS_JOIN_BACKPRESSURE_PASS");

        $display("HFT_RMIC_I5_FAST_SUCCESS_JOIN_TB_PASS");
        $finish;
    end

    initial begin #300000; fail("timeout"); end
endmodule
