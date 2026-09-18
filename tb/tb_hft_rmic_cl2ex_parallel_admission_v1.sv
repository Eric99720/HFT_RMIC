`timescale 1ns/1ps
`include "hft_rmic_accounting_defs.svh"
`include "hft_rmic_policy_defs.svh"

module tb_hft_rmic_cl2ex_parallel_admission_v1;
    localparam [2:0] STORE_ST_OK = 3'd0;
    localparam [2:0] STORE_ST_FULL = 3'd3;
    localparam [1:0] STORE_DELETE = 2'd2;

    reg clk=0; always #5 clk=~clk;
    reg rst_n=0;

    reg order_valid=0;
    wire order_ready;
    reg [255:0] order_data=0;
    reg policy_pass=1;
    reg [1:0] policy_reason_source=`HFT_RMIC_REASON_SRC_POLICY;
    reg [7:0] policy_reason_code=`HFT_RMIC_POLICY_REASON_PASS;
    reg [31:0] order_id=32'h1234;
    reg [7:0] account_id=8'h1, product_id=8'h2;
    reg side=0;
    reg [7:0] position_effect=8'h4f, order_type=8'h32, tif=8'h30;
    reg [31:0] limit_price=32'd1000;
    reg [15:0] qty=16'd2;

    wire result_valid;
    reg result_ready=0;
    wire result_accepted;
    wire [1:0] result_reason_source;
    wire [7:0] result_reason_code;
    wire [31:0] result_order_id;
    wire [255:0] result_order_data;

    wire acct_req_valid;
    reg acct_req_ready=1;
    wire [7:0] acct_req_account_id, acct_req_product_id;
    wire [2:0] acct_req_event_kind;
    wire acct_req_side;
    wire [7:0] acct_req_position_effect;
    wire [15:0] acct_req_order_qty, acct_req_fill_qty, acct_req_release_qty;
    reg acct_rsp_valid=0, acct_rsp_ok=0;
    reg [1:0] acct_rsp_reason_source=`HFT_RMIC_REASON_SRC_POLICY;
    reg [7:0] acct_rsp_reason_code=`HFT_RMIC_POLICY_REASON_PASS;
    wire acct_rsp_ready;

    wire store_req_valid;
    reg store_req_ready=1;
    wire [1:0] store_req_op;
    wire [31:0] store_req_order_id;
    wire [7:0] store_req_account_id, store_req_product_id;
    wire store_req_side;
    wire [7:0] store_req_position_effect, store_req_order_type, store_req_tif;
    wire [31:0] store_req_limit_price;
    wire [15:0] store_req_remaining_qty;
    reg store_rsp_valid=0, store_rsp_ok=0, store_rsp_found=0;
    reg [2:0] store_rsp_status=STORE_ST_OK;
    wire store_rsp_ready;

    hft_rmic_cl2ex_parallel_admission_v1 dut(
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

    task fire_order(input bit pass);
        begin
            @(negedge clk);
            policy_pass=pass;
            order_data={224'd0,order_id};
            order_valid=1;
            while(!order_ready) @(posedge clk);
            @(posedge clk);
            @(negedge clk);
            order_valid=0;
        end
    endtask

    task expect_parallel_issue;
        begin
            #1;
            if(!acct_req_valid || !store_req_valid)
                fail("reserve and insert were not issued in parallel");
            if(acct_req_event_kind != `HFT_RMIC_ACCT_EVENT_RESERVE)
                fail("parallel accounting op is not RESERVE");
            if(store_req_op != 2'd1)
                fail("parallel store op is not INSERT");
            @(posedge clk);
            @(negedge clk);
        end
    endtask

    task send_acct_rsp(input bit ok,input [1:0] src,input [7:0] code);
        begin
            while(!acct_rsp_ready) @(posedge clk);
            @(negedge clk);
            acct_rsp_ok=ok; acct_rsp_reason_source=src; acct_rsp_reason_code=code; acct_rsp_valid=1;
            @(posedge clk);
            @(negedge clk);
            acct_rsp_valid=0;
        end
    endtask

    task send_store_rsp(input bit ok,input [2:0] status);
        begin
            while(!store_rsp_ready) @(posedge clk);
            @(negedge clk);
            store_rsp_ok=ok; store_rsp_status=status; store_rsp_found=(status!=STORE_ST_OK); store_rsp_valid=1;
            @(posedge clk);
            @(negedge clk);
            store_rsp_valid=0;
        end
    endtask

    task wait_result(input bit exp_accept);
        integer guard;
        begin
            guard=0;
            while(!result_valid && guard<40) begin @(posedge clk); #1; guard=guard+1; end
            if(!result_valid) fail("result timeout");
            if(result_accepted !== exp_accept) fail("result accepted mismatch");
        end
    endtask

    task consume_result;
        begin
            @(negedge clk); result_ready=1;
            @(posedge clk);
            @(negedge clk); result_ready=0;
        end
    endtask

    initial begin
        repeat(4) @(posedge clk);
        @(negedge clk); rst_n=1;

        // Success: staggered responses prove acceptance waits for both.
        fire_order(1);
        expect_parallel_issue();
        send_store_rsp(1,STORE_ST_OK);
        if(result_valid) fail("accepted before accounting response");
        send_acct_rsp(1,`HFT_RMIC_REASON_SRC_POLICY,`HFT_RMIC_POLICY_REASON_PASS);
        wait_result(1);
        if(result_order_id!==order_id || result_order_data!={224'd0,order_id}) fail("success payload changed");
        $display("I5_PARALLEL_ADMISSION_SUCCESS_PASS");
        consume_result();

        // Store failure after reserve success -> accounting RELEASE rollback.
        order_id=32'h2001;
        fire_order(1);
        expect_parallel_issue();
        send_acct_rsp(1,`HFT_RMIC_REASON_SRC_POLICY,`HFT_RMIC_POLICY_REASON_PASS);
        send_store_rsp(0,STORE_ST_FULL);
        #1;
        if(!acct_req_valid || acct_req_event_kind!=`HFT_RMIC_ACCT_EVENT_RELEASE || acct_req_release_qty!=qty)
            fail("missing accounting rollback after store failure");
        @(posedge clk); @(negedge clk);
        send_acct_rsp(1,`HFT_RMIC_REASON_SRC_POLICY,`HFT_RMIC_POLICY_REASON_PASS);
        wait_result(0);
        if(result_reason_source!=`HFT_RMIC_REASON_SRC_SYSTEM ||
           result_reason_code!=`HFT_RMIC_SYSTEM_REASON_ORDER_CONTEXT_FULL)
            fail("store-failure reject reason mismatch");
        $display("I5_PARALLEL_ADMISSION_ACCOUNT_ROLLBACK_PASS");
        consume_result();

        // Accounting failure after store success -> DELETE rollback.
        order_id=32'h2002;
        fire_order(1);
        expect_parallel_issue();
        send_store_rsp(1,STORE_ST_OK);
        send_acct_rsp(0,`HFT_RMIC_REASON_SRC_POLICY,`HFT_RMIC_POLICY_REASON_MARGIN_LIMIT);
        #1;
        if(!store_req_valid || store_req_op!=STORE_DELETE || store_req_order_id!=order_id)
            fail("missing store DELETE rollback after accounting failure");
        @(posedge clk); @(negedge clk);
        send_store_rsp(1,STORE_ST_OK);
        wait_result(0);
        if(result_reason_source!=`HFT_RMIC_REASON_SRC_POLICY ||
           result_reason_code!=`HFT_RMIC_POLICY_REASON_MARGIN_LIMIT)
            fail("account-failure reject reason mismatch");
        $display("I5_PARALLEL_ADMISSION_STORE_ROLLBACK_PASS");
        consume_result();

        // Store rollback failure must escalate recovery-required reason.
        order_id=32'h2003;
        fire_order(1);
        expect_parallel_issue();
        send_store_rsp(1,STORE_ST_OK);
        send_acct_rsp(0,`HFT_RMIC_REASON_SRC_POLICY,`HFT_RMIC_POLICY_REASON_STATE_DISABLED);
        #1;
        if(!store_req_valid || store_req_op!=STORE_DELETE) fail("missing store rollback issue");
        @(posedge clk); @(negedge clk);
        send_store_rsp(0,STORE_ST_FULL);
        wait_result(0);
        if(result_reason_source!=`HFT_RMIC_REASON_SRC_SYSTEM ||
           result_reason_code!=`HFT_RMIC_SYSTEM_REASON_ADMISSION_ROLLBACK_FAILED)
            fail("store rollback failure did not fail closed");
        $display("I5_PARALLEL_ADMISSION_STORE_ROLLBACK_FAIL_CLOSED_PASS");
        consume_result();

        // Accounting rollback failure must also escalate.
        order_id=32'h2004;
        fire_order(1);
        expect_parallel_issue();
        send_acct_rsp(1,`HFT_RMIC_REASON_SRC_POLICY,`HFT_RMIC_POLICY_REASON_PASS);
        send_store_rsp(0,STORE_ST_FULL);
        #1;
        if(!acct_req_valid || acct_req_event_kind!=`HFT_RMIC_ACCT_EVENT_RELEASE)
            fail("missing accounting rollback issue");
        @(posedge clk); @(negedge clk);
        send_acct_rsp(0,`HFT_RMIC_REASON_SRC_POLICY,`HFT_RMIC_POLICY_REASON_ACCOUNTING_STATE);
        wait_result(0);
        if(result_reason_source!=`HFT_RMIC_REASON_SRC_SYSTEM ||
           result_reason_code!=`HFT_RMIC_SYSTEM_REASON_ADMISSION_ROLLBACK_FAILED)
            fail("account rollback failure did not fail closed");
        $display("I5_PARALLEL_ADMISSION_ACCOUNT_ROLLBACK_FAIL_CLOSED_PASS");
        consume_result();

        // Policy reject must not touch either mutable owner.
        order_id=32'h2005;
        policy_reason_source=`HFT_RMIC_REASON_SRC_POLICY;
        policy_reason_code=`HFT_RMIC_POLICY_REASON_KILL_SWITCH;
        fire_order(0);
        #1;
        if(acct_req_valid || store_req_valid) fail("policy reject mutated downstream state");
        wait_result(0);
        if(result_reason_code!=`HFT_RMIC_POLICY_REASON_KILL_SWITCH) fail("policy reject reason mismatch");
        $display("I5_PARALLEL_ADMISSION_POLICY_NO_MUTATION_PASS");

        // Result must remain stable under backpressure.
        repeat(3) begin
            reg [31:0] id_hold;
            reg [7:0] code_hold;
            id_hold=result_order_id; code_hold=result_reason_code;
            @(posedge clk); #1;
            if(!result_valid || result_order_id!=id_hold || result_reason_code!=code_hold)
                fail("result changed under backpressure");
        end
        $display("I5_PARALLEL_ADMISSION_RESULT_BACKPRESSURE_PASS");
        consume_result();

        $display("HFT_RMIC_CL2EX_PARALLEL_ADMISSION_V1_TB_PASS");
        $finish;
    end

    initial begin
        #500000;
        fail("timeout");
    end
endmodule
