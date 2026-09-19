`timescale 1ns/1ps
`include "hft_rmic_accounting_defs.svh"
`include "hft_rmic_policy_defs.svh"
`include "hft_rmic_contract.svh"
`include "taifex_tmp_v2187_defs.svh"

module tb_hft_rmic_state_l0_fast_v1;
    localparam integer QTY_W=16, MARGIN_W=32;
    reg clk=0; always #5 clk=~clk;
    integer cycle=0; always @(posedge clk) cycle <= cycle+1;
    reg rst_n=0;

    reg cfg_valid=0; wire cfg_ready;
    reg [7:0] cfg_account_id=0,cfg_product_id=0; reg cfg_enabled=1;
    reg [31:0] cfg_margin_budget=10000,cfg_margin_per_contract=1000;
    reg [15:0] cfg_long_position=0,cfg_short_position=0,cfg_pending_open_long=0,cfg_pending_open_short=0,cfg_reserved_close_long=0,cfg_reserved_close_short=0;
    wire cfg_done,cfg_ok; wire [7:0] cfg_reason_code;

    reg req_valid=0; wire req_ready;
    reg [7:0] req_account_id=0,req_product_id=0; reg [2:0] req_event_kind=0; reg req_side=0;
    reg [7:0] req_position_effect=`HFT_RMIC_TAIFEX_POS_OPEN;
    reg [15:0] req_order_qty=0,req_fill_qty=0,req_release_qty=0;

    wire rsp_valid; reg rsp_ready=0; wire rsp_ok; wire [1:0] rsp_reason_source; wire [7:0] rsp_reason_code;
    wire [7:0] rsp_account_id,rsp_product_id; wire rsp_entry_enabled;
    wire [15:0] rsp_long_position,rsp_short_position,rsp_pending_open_long,rsp_pending_open_short,rsp_reserved_close_long,rsp_reserved_close_short;
    wire [31:0] rsp_required_margin_before,rsp_required_margin_after;

    hft_rmic_futures_state_manager_v1 #(
        .NUM_ACCOUNTS(4),.NUM_PRODUCTS(4),.ACCOUNT_ID_W(8),.PRODUCT_ID_W(8),
        .QTY_W(QTY_W),.MARGIN_W(MARGIN_W),.ENABLE_L0_FAST_CACHE(1)
    ) dut (
        .clk(clk),.rst_n(rst_n),
        .cfg_valid(cfg_valid),.cfg_ready(cfg_ready),.cfg_account_id(cfg_account_id),.cfg_product_id(cfg_product_id),
        .cfg_enabled(cfg_enabled),.cfg_margin_budget(cfg_margin_budget),.cfg_margin_per_contract(cfg_margin_per_contract),
        .cfg_long_position(cfg_long_position),.cfg_short_position(cfg_short_position),
        .cfg_pending_open_long(cfg_pending_open_long),.cfg_pending_open_short(cfg_pending_open_short),
        .cfg_reserved_close_long(cfg_reserved_close_long),.cfg_reserved_close_short(cfg_reserved_close_short),
        .cfg_done(cfg_done),.cfg_ok(cfg_ok),.cfg_reason_code(cfg_reason_code),
        .req_valid(req_valid),.req_ready(req_ready),.req_account_id(req_account_id),.req_product_id(req_product_id),
        .req_event_kind(req_event_kind),.req_side(req_side),.req_position_effect(req_position_effect),
        .req_order_qty(req_order_qty),.req_fill_qty(req_fill_qty),.req_release_qty(req_release_qty),
        .rsp_valid(rsp_valid),.rsp_ready(rsp_ready),.rsp_ok(rsp_ok),.rsp_reason_source(rsp_reason_source),
        .rsp_reason_code(rsp_reason_code),.rsp_account_id(rsp_account_id),.rsp_product_id(rsp_product_id),
        .rsp_entry_enabled(rsp_entry_enabled),.rsp_long_position(rsp_long_position),.rsp_short_position(rsp_short_position),
        .rsp_pending_open_long(rsp_pending_open_long),.rsp_pending_open_short(rsp_pending_open_short),
        .rsp_reserved_close_long(rsp_reserved_close_long),.rsp_reserved_close_short(rsp_reserved_close_short),
        .rsp_required_margin_before(rsp_required_margin_before),.rsp_required_margin_after(rsp_required_margin_after)
    );

    task fail; input [8*120-1:0] msg; begin $display("TEST_FAIL %0s",msg); $fatal(1); end endtask

    task cfg_entry(input [7:0] a,input [7:0] p);
      begin
        @(negedge clk); cfg_account_id=a; cfg_product_id=p; cfg_valid=1;
        while(!cfg_ready) @(posedge clk);
        @(posedge clk); @(negedge clk); cfg_valid=0;
        if(!cfg_done||!cfg_ok) fail("configuration failed");
      end
    endtask

    task request_measure(
        input [7:0] a,input [7:0] p,input [2:0] ev,input [15:0] oq,
        output integer latency_cycles
    );
      integer fire_cycle;
      begin
        @(negedge clk);
        req_account_id=a; req_product_id=p; req_event_kind=ev; req_order_qty=oq;
        req_fill_qty=0; req_release_qty=0; req_side=`HFT_RMIC_RMIC_SIDE_BUY;
        req_position_effect=`HFT_RMIC_TAIFEX_POS_OPEN; req_valid=1;
        while(!req_ready) @(posedge clk);
        @(posedge clk); #1; fire_cycle=cycle;
        @(negedge clk); req_valid=0;
        while(!rsp_valid) begin @(posedge clk); #1; end
        latency_cycles=cycle-fire_cycle;
      end
    endtask

    task consume; begin @(negedge clk); rsp_ready=1; @(posedge clk); @(negedge clk); rsp_ready=0; end endtask

    integer cold_cycles,hot_cycles,reserve_cycles;
    initial begin
        repeat(4) @(posedge clk); @(negedge clk); rst_n=1;

        // Configure A1/P1, then configure another key so A1/P1 is no longer L0.
        cfg_entry(1,1);
        cfg_entry(2,1);

        request_measure(1,1,`HFT_RMIC_ACCT_EVENT_QUERY,0,cold_cycles);
        if(!rsp_ok) fail("cold query failed");
        consume();

        request_measure(1,1,`HFT_RMIC_ACCT_EVENT_QUERY,0,hot_cycles);
        if(!rsp_ok) fail("hot query failed");
        if(!(hot_cycles < cold_cycles)) fail("L0 hit did not reduce response latency");
        if(hot_cycles > 2) fail("L0 hit exceeded two-cycle target");
        $display("I5_L0_STATE_CACHE_HIT_LATENCY_PASS cold_cycles=%0d hot_cycles=%0d",cold_cycles,hot_cycles);
        consume();

        request_measure(1,1,`HFT_RMIC_ACCT_EVENT_RESERVE,2,reserve_cycles);
        if(!rsp_ok || rsp_pending_open_long!=2 || rsp_required_margin_after!=2000)
            fail("hot reserve semantics mismatch");
        if(reserve_cycles > 2) fail("hot reserve exceeded two-cycle target");
        $display("I5_L0_STATE_CACHE_RESERVE_PASS cycles=%0d",reserve_cycles);
        consume();

        // Write-through coherence: immediately query the same key.
        request_measure(1,1,`HFT_RMIC_ACCT_EVENT_QUERY,0,hot_cycles);
        if(!rsp_ok || rsp_pending_open_long!=2 || rsp_required_margin_after!=2000)
            fail("write-through cache coherence mismatch");
        $display("I5_L0_STATE_CACHE_COHERENCE_PASS");
        consume();

        // Reset must invalidate cache and configured ownership.
        @(negedge clk); rst_n=0; repeat(3) @(posedge clk); @(negedge clk); rst_n=1;
        request_measure(1,1,`HFT_RMIC_ACCT_EVENT_QUERY,0,cold_cycles);
        if(rsp_ok || rsp_reason_code!=`HFT_RMIC_POLICY_REASON_STATE_UNCONFIGURED)
            fail("reset did not fail closed");
        $display("I5_L0_STATE_CACHE_RESET_FAIL_CLOSED_PASS");
        consume();

        $display("HFT_RMIC_I5_L0_STATE_CACHE_TB_PASS");
        $finish;
    end

    initial begin #300000; fail("timeout"); end
endmodule
