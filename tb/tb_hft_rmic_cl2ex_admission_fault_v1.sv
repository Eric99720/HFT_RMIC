`timescale 1ns/1ps
`include "hft_rmic_accounting_defs.svh"
`include "hft_rmic_policy_defs.svh"

module tb_hft_rmic_cl2ex_admission_fault_v1;
    reg clk=0; always #5 clk=~clk;
    reg rst_n=0;

    reg order_valid; wire order_ready;
    reg [255:0] order_data;
    reg policy_pass; reg [1:0] policy_reason_source; reg [7:0] policy_reason_code;
    reg [31:0] order_id; reg [7:0] account_id,product_id; reg side;
    reg [7:0] position_effect,order_type,tif; reg [31:0] limit_price; reg [15:0] qty;
    wire result_valid; reg result_ready; wire result_accepted;
    wire [1:0] result_reason_source; wire [7:0] result_reason_code;
    wire [31:0] result_order_id; wire [255:0] result_order_data;

    wire acct_req_valid; reg acct_req_ready;
    wire [7:0] acct_req_account_id,acct_req_product_id; wire [2:0] acct_req_event_kind;
    wire acct_req_side; wire [7:0] acct_req_position_effect;
    wire [15:0] acct_req_order_qty,acct_req_fill_qty,acct_req_release_qty;
    reg acct_rsp_valid; wire acct_rsp_ready; reg acct_rsp_ok;
    reg [1:0] acct_rsp_reason_source; reg [7:0] acct_rsp_reason_code;

    wire store_req_valid; reg store_req_ready; wire [1:0] store_req_op;
    wire [31:0] store_req_order_id; wire [7:0] store_req_account_id,store_req_product_id;
    wire store_req_side; wire [7:0] store_req_position_effect,store_req_order_type,store_req_tif;
    wire [31:0] store_req_limit_price; wire [15:0] store_req_remaining_qty;
    reg store_rsp_valid; wire store_rsp_ready; reg store_rsp_ok,store_rsp_found;
    reg [2:0] store_rsp_status;

    hft_rmic_cl2ex_admission_v1 dut (.*);

    reg force_rollback_fail;
    reg [2:0] next_store_status;
    integer reserve_count,release_count,store_count;

    // One-cycle-later scripted account responder. Reserve always succeeds;
    // RELEASE can be deliberately failed to prove fail-closed recovery output.
    reg acct_pending;
    reg [2:0] acct_pending_kind;
    always @(posedge clk) begin
        if(!rst_n) begin
            acct_rsp_valid<=0; acct_rsp_ok<=0; acct_rsp_reason_source<=`HFT_RMIC_REASON_SRC_POLICY;
            acct_rsp_reason_code<=0; acct_pending<=0; reserve_count<=0; release_count<=0;
        end else begin
            if(acct_rsp_valid && acct_rsp_ready) acct_rsp_valid<=0;
            if(acct_pending && !acct_rsp_valid) begin
                acct_rsp_valid<=1;
                acct_rsp_reason_source<=`HFT_RMIC_REASON_SRC_POLICY;
                if(acct_pending_kind==`HFT_RMIC_ACCT_EVENT_RELEASE && force_rollback_fail) begin
                    acct_rsp_ok<=0;
                    acct_rsp_reason_code<=`HFT_RMIC_POLICY_REASON_ACCOUNTING_STATE;
                end else begin
                    acct_rsp_ok<=1;
                    acct_rsp_reason_code<=`HFT_RMIC_POLICY_REASON_PASS;
                end
                acct_pending<=0;
            end
            if(acct_req_valid && acct_req_ready) begin
                acct_pending<=1; acct_pending_kind<=acct_req_event_kind;
                if(acct_req_event_kind==`HFT_RMIC_ACCT_EVENT_RESERVE) reserve_count<=reserve_count+1;
                if(acct_req_event_kind==`HFT_RMIC_ACCT_EVENT_RELEASE) release_count<=release_count+1;
            end
        end
    end

    reg store_pending;
    always @(posedge clk) begin
        if(!rst_n) begin
            store_rsp_valid<=0;store_rsp_ok<=0;store_rsp_found<=0;store_rsp_status<=0;
            store_pending<=0;store_count<=0;
        end else begin
            if(store_rsp_valid && store_rsp_ready) store_rsp_valid<=0;
            if(store_pending && !store_rsp_valid) begin
                store_rsp_valid<=1;
                store_rsp_status<=next_store_status;
                store_rsp_ok<=(next_store_status==3'd0);
                store_rsp_found<=(next_store_status==3'd0 || next_store_status==3'd2);
                store_pending<=0;
            end
            if(store_req_valid && store_req_ready) begin
                store_pending<=1;store_count<=store_count+1;
            end
        end
    end

    task fail(input [8*120-1:0] msg); begin $display("TEST_FAIL %0s",msg);$fatal(1);end endtask
    task issue(input [31:0] oid,input [2:0] st,input rb_fail);
        begin
            next_store_status=st;force_rollback_fail=rb_fail;
            @(negedge clk);order_id=oid;order_data={224'd0,oid};order_valid=1;
            while(!order_ready)@(posedge clk);@(posedge clk);@(negedge clk);order_valid=0;
            while(!result_valid)@(posedge clk);#1;
        end
    endtask
    task consume;begin @(negedge clk);result_ready=1;@(posedge clk);@(negedge clk);result_ready=0;end endtask

    initial begin
        order_valid=0;order_data=0;policy_pass=1;policy_reason_source=`HFT_RMIC_REASON_SRC_POLICY;
        policy_reason_code=0;order_id=0;account_id=1;product_id=1;side=0;position_effect=8'h4f;
        order_type=2;tif=0;limit_price=100;qty=2;result_ready=0;
        acct_req_ready=1;acct_rsp_valid=0;acct_rsp_ok=0;acct_rsp_reason_source=0;acct_rsp_reason_code=0;
        store_req_ready=1;store_rsp_valid=0;store_rsp_ok=0;store_rsp_found=0;store_rsp_status=0;
        force_rollback_fail=0;next_store_status=0;acct_pending=0;store_pending=0;
        repeat(4)@(posedge clk);@(negedge clk);rst_n=1;

        // Recoverable store failure: rollback succeeds and original store reason is returned.
        issue(1,3'd2,1'b0);
        if(result_accepted || result_reason_code!=`HFT_RMIC_SYSTEM_REASON_ORDER_CONTEXT_EXISTS)fail("recoverable duplicate result");
        if(reserve_count!=1||release_count!=1||store_count!=1)fail("recoverable transaction counts");
        consume();
        $display("I3_FAULT_RECOVERABLE_ROLLBACK_PASS");

        // Catastrophic rollback failure: never downgrade to an ordinary reject.
        issue(2,3'd3,1'b1);
        if(result_accepted)fail("rollback failure must never accept");
        if(result_reason_source!=`HFT_RMIC_REASON_SRC_SYSTEM ||
           result_reason_code!=`HFT_RMIC_SYSTEM_REASON_ADMISSION_ROLLBACK_FAILED)fail("rollback failure reason");
        if(reserve_count!=2||release_count!=2||store_count!=2)fail("rollback failure transaction counts");
        consume();
        $display("I3_FAULT_ROLLBACK_FAILURE_FAIL_CLOSED_PASS");

        $display("HFT_RMIC_CL2EX_ADMISSION_FAULT_V1_TB_PASS");
        $finish;
    end
endmodule
