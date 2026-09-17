`timescale 1ns/1ps
`include "hft_rmic_accounting_defs.svh"
`include "hft_rmic_contract.svh"
`include "hft_rmic_policy_defs.svh"
`include "taifex_tmp_v2187_defs.svh"

module tb_hft_rmic_futures_state_manager_v1;
    localparam integer NUM_ACCOUNTS = 4;
    localparam integer NUM_PRODUCTS = 3;
    localparam integer ACCOUNT_ID_W = 3;
    localparam integer PRODUCT_ID_W = 2;
    localparam integer QTY_W = 16;
    localparam integer MARGIN_W = 32;

    reg clk = 1'b0;
    always #5 clk = ~clk;
    reg rst_n = 1'b0;

    reg cfg_valid;
    wire cfg_ready;
    reg [ACCOUNT_ID_W-1:0] cfg_account_id;
    reg [PRODUCT_ID_W-1:0] cfg_product_id;
    reg cfg_enabled;
    reg [MARGIN_W-1:0] cfg_margin_budget, cfg_margin_per_contract;
    reg [QTY_W-1:0] cfg_long_position, cfg_short_position;
    reg [QTY_W-1:0] cfg_pending_open_long, cfg_pending_open_short;
    reg [QTY_W-1:0] cfg_reserved_close_long, cfg_reserved_close_short;
    wire cfg_done, cfg_ok;
    wire [7:0] cfg_reason_code;

    reg req_valid;
    wire req_ready;
    reg [ACCOUNT_ID_W-1:0] req_account_id;
    reg [PRODUCT_ID_W-1:0] req_product_id;
    reg [2:0] req_event_kind;
    reg req_side;
    reg [7:0] req_position_effect;
    reg [QTY_W-1:0] req_order_qty, req_fill_qty, req_release_qty;

    wire rsp_valid;
    reg rsp_ready;
    wire rsp_ok;
    wire [1:0] rsp_reason_source;
    wire [7:0] rsp_reason_code;
    wire [ACCOUNT_ID_W-1:0] rsp_account_id;
    wire [PRODUCT_ID_W-1:0] rsp_product_id;
    wire rsp_entry_enabled;
    wire [QTY_W-1:0] rsp_long_position, rsp_short_position;
    wire [QTY_W-1:0] rsp_pending_open_long, rsp_pending_open_short;
    wire [QTY_W-1:0] rsp_reserved_close_long, rsp_reserved_close_short;
    wire [MARGIN_W-1:0] rsp_required_margin_before, rsp_required_margin_after;

    hft_rmic_futures_state_manager_v1 #(
        .NUM_ACCOUNTS(NUM_ACCOUNTS), .NUM_PRODUCTS(NUM_PRODUCTS),
        .ACCOUNT_ID_W(ACCOUNT_ID_W), .PRODUCT_ID_W(PRODUCT_ID_W),
        .QTY_W(QTY_W), .MARGIN_W(MARGIN_W)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .cfg_valid(cfg_valid), .cfg_ready(cfg_ready),
        .cfg_account_id(cfg_account_id), .cfg_product_id(cfg_product_id),
        .cfg_enabled(cfg_enabled), .cfg_margin_budget(cfg_margin_budget),
        .cfg_margin_per_contract(cfg_margin_per_contract),
        .cfg_long_position(cfg_long_position), .cfg_short_position(cfg_short_position),
        .cfg_pending_open_long(cfg_pending_open_long), .cfg_pending_open_short(cfg_pending_open_short),
        .cfg_reserved_close_long(cfg_reserved_close_long), .cfg_reserved_close_short(cfg_reserved_close_short),
        .cfg_done(cfg_done), .cfg_ok(cfg_ok), .cfg_reason_code(cfg_reason_code),
        .req_valid(req_valid), .req_ready(req_ready),
        .req_account_id(req_account_id), .req_product_id(req_product_id),
        .req_event_kind(req_event_kind), .req_side(req_side),
        .req_position_effect(req_position_effect), .req_order_qty(req_order_qty),
        .req_fill_qty(req_fill_qty), .req_release_qty(req_release_qty),
        .rsp_valid(rsp_valid), .rsp_ready(rsp_ready), .rsp_ok(rsp_ok),
        .rsp_reason_source(rsp_reason_source), .rsp_reason_code(rsp_reason_code),
        .rsp_account_id(rsp_account_id), .rsp_product_id(rsp_product_id),
        .rsp_entry_enabled(rsp_entry_enabled),
        .rsp_long_position(rsp_long_position), .rsp_short_position(rsp_short_position),
        .rsp_pending_open_long(rsp_pending_open_long), .rsp_pending_open_short(rsp_pending_open_short),
        .rsp_reserved_close_long(rsp_reserved_close_long), .rsp_reserved_close_short(rsp_reserved_close_short),
        .rsp_required_margin_before(rsp_required_margin_before),
        .rsp_required_margin_after(rsp_required_margin_after)
    );

    task fail;
        input [8*120-1:0] msg;
        begin $display("TEST_FAIL %0s", msg); $fatal(1); end
    endtask

    task cfg_entry;
        input [ACCOUNT_ID_W-1:0] a;
        input [PRODUCT_ID_W-1:0] p;
        input en;
        input [MARGIN_W-1:0] budget;
        input [MARGIN_W-1:0] per_contract;
        input [QTY_W-1:0] lp, sp, pol, pos, rcl, rcs;
        reg accepted;
        begin
            @(negedge clk);
            cfg_account_id = a; cfg_product_id = p; cfg_enabled = en;
            cfg_margin_budget = budget; cfg_margin_per_contract = per_contract;
            cfg_long_position = lp; cfg_short_position = sp;
            cfg_pending_open_long = pol; cfg_pending_open_short = pos;
            cfg_reserved_close_long = rcl; cfg_reserved_close_short = rcs;
            cfg_valid = 1'b1;
            accepted = 1'b0;
            while (!accepted) begin
                @(posedge clk);
                if (cfg_ready) accepted = 1'b1;
            end
            @(negedge clk);
            if (!cfg_done || !cfg_ok || cfg_reason_code != `HFT_RMIC_POLICY_REASON_PASS)
                fail("configuration write failed");
            cfg_valid = 1'b0;
        end
    endtask

    task start_req;
        input [ACCOUNT_ID_W-1:0] a;
        input [PRODUCT_ID_W-1:0] p;
        input [2:0] ev;
        input side;
        input [7:0] pe;
        input [QTY_W-1:0] oq, fq, rq;
        reg accepted;
        begin
            @(negedge clk);
            req_account_id = a; req_product_id = p; req_event_kind = ev;
            req_side = side; req_position_effect = pe;
            req_order_qty = oq; req_fill_qty = fq; req_release_qty = rq;
            req_valid = 1'b1;
            accepted = 1'b0;
            while (!accepted) begin
                @(posedge clk);
                if (req_ready) accepted = 1'b1;
            end
            @(negedge clk);
            req_valid = 1'b0;
            while (!rsp_valid) @(posedge clk);
            #1;
        end
    endtask

    task finish_rsp;
        begin
            @(negedge clk); rsp_ready = 1'b1;
            @(posedge clk);
            @(negedge clk); rsp_ready = 1'b0;
        end
    endtask

    task expect_rsp;
        input exp_ok;
        input [7:0] exp_reason;
        input exp_enabled;
        input [QTY_W-1:0] lp, sp, pol, pos, rcl, rcs;
        input [MARGIN_W-1:0] mbefore, mafter;
        begin
            if (rsp_ok !== exp_ok) fail("rsp_ok mismatch");
            if (rsp_reason_source !== `HFT_RMIC_REASON_SRC_POLICY) fail("reason source mismatch");
            if (rsp_reason_code !== exp_reason) fail("reason code mismatch");
            if (rsp_entry_enabled !== exp_enabled) fail("entry enabled mismatch");
            if (rsp_long_position !== lp) fail("long position mismatch");
            if (rsp_short_position !== sp) fail("short position mismatch");
            if (rsp_pending_open_long !== pol) fail("pending open long mismatch");
            if (rsp_pending_open_short !== pos) fail("pending open short mismatch");
            if (rsp_reserved_close_long !== rcl) fail("reserved close long mismatch");
            if (rsp_reserved_close_short !== rcs) fail("reserved close short mismatch");
            if (rsp_required_margin_before !== mbefore) fail("margin before mismatch");
            if (rsp_required_margin_after !== mafter) fail("margin after mismatch");
            finish_rsp();
        end
    endtask

    task query_expect;
        input [ACCOUNT_ID_W-1:0] a;
        input [PRODUCT_ID_W-1:0] p;
        input exp_ok;
        input [7:0] exp_reason;
        input exp_enabled;
        input [QTY_W-1:0] lp, sp, pol, pos, rcl, rcs;
        input [MARGIN_W-1:0] margin;
        begin
            start_req(a,p,`HFT_RMIC_ACCT_EVENT_QUERY,1'b0,`HFT_RMIC_TAIFEX_POS_OPEN,0,0,0);
            expect_rsp(exp_ok, exp_reason, exp_enabled, lp, sp, pol, pos, rcl, rcs, margin, margin);
        end
    endtask

    initial begin
        cfg_valid=0; cfg_account_id=0; cfg_product_id=0; cfg_enabled=0;
        cfg_margin_budget=0; cfg_margin_per_contract=0;
        cfg_long_position=0; cfg_short_position=0;
        cfg_pending_open_long=0; cfg_pending_open_short=0;
        cfg_reserved_close_long=0; cfg_reserved_close_short=0;
        req_valid=0; req_account_id=0; req_product_id=0;
        req_event_kind=`HFT_RMIC_ACCT_EVENT_QUERY; req_side=0;
        req_position_effect=`HFT_RMIC_TAIFEX_POS_OPEN;
        req_order_qty=0; req_fill_qty=0; req_release_qty=0;
        rsp_ready=0;

        repeat(4) @(posedge clk);
        @(negedge clk); rst_n=1;

        cfg_entry(1,1,1,10000,1000,0,0,0,0,0,0);
        cfg_entry(2,1,1,10000,1000,0,0,0,0,0,0);
        cfg_entry(1,2,1,1000,1000,0,0,0,0,0,0);
        cfg_entry(3,1,0,10000,1000,0,0,0,0,0,0);

        query_expect(1,1,1,`HFT_RMIC_POLICY_REASON_PASS,1,0,0,0,0,0,0,0);

        // BUY OPEN A1/P1 reserve 3.
        start_req(1,1,`HFT_RMIC_ACCT_EVENT_RESERVE,`HFT_RMIC_RMIC_SIDE_BUY,
                  `HFT_RMIC_TAIFEX_POS_OPEN,3,0,0);
        expect_rsp(1,`HFT_RMIC_POLICY_REASON_PASS,1,0,0,3,0,0,0,0,3000);

        // Cross-key isolation.
        query_expect(2,1,1,`HFT_RMIC_POLICY_REASON_PASS,1,0,0,0,0,0,0,0);
        query_expect(1,2,1,`HFT_RMIC_POLICY_REASON_PASS,1,0,0,0,0,0,0,0);
        $display("HFT_RMIC_STATE_KEY_ISOLATION_PASS");

        // SELL OPEN A2/P1, then partial fill.
        start_req(2,1,`HFT_RMIC_ACCT_EVENT_RESERVE,`HFT_RMIC_RMIC_SIDE_SELL,
                  `HFT_RMIC_TAIFEX_POS_OPEN,2,0,0);
        expect_rsp(1,`HFT_RMIC_POLICY_REASON_PASS,1,0,0,0,2,0,0,0,2000);
        start_req(2,1,`HFT_RMIC_ACCT_EVENT_FILL,`HFT_RMIC_RMIC_SIDE_SELL,
                  `HFT_RMIC_TAIFEX_POS_OPEN,0,1,0);
        expect_rsp(1,`HFT_RMIC_POLICY_REASON_PASS,1,0,1,0,1,0,0,2000,2000);
        $display("HFT_RMIC_STATE_SHORT_OPEN_PASS");

        // A1/P1 partial BUY OPEN fill and release remainder.
        start_req(1,1,`HFT_RMIC_ACCT_EVENT_FILL,`HFT_RMIC_RMIC_SIDE_BUY,
                  `HFT_RMIC_TAIFEX_POS_OPEN,0,2,0);
        expect_rsp(1,`HFT_RMIC_POLICY_REASON_PASS,1,2,0,1,0,0,0,3000,3000);
        start_req(1,1,`HFT_RMIC_ACCT_EVENT_RELEASE,`HFT_RMIC_RMIC_SIDE_BUY,
                  `HFT_RMIC_TAIFEX_POS_OPEN,0,0,1);
        expect_rsp(1,`HFT_RMIC_POLICY_REASON_PASS,1,2,0,0,0,0,0,3000,2000);

        // SELL CLOSE one long contract.
        start_req(1,1,`HFT_RMIC_ACCT_EVENT_RESERVE,`HFT_RMIC_RMIC_SIDE_SELL,
                  `HFT_RMIC_TAIFEX_POS_CLOSE,1,0,0);
        expect_rsp(1,`HFT_RMIC_POLICY_REASON_PASS,1,2,0,0,0,1,0,2000,2000);
        start_req(1,1,`HFT_RMIC_ACCT_EVENT_FILL,`HFT_RMIC_RMIC_SIDE_SELL,
                  `HFT_RMIC_TAIFEX_POS_CLOSE,0,1,0);
        expect_rsp(1,`HFT_RMIC_POLICY_REASON_PASS,1,1,0,0,0,0,0,2000,1000);
        $display("HFT_RMIC_STATE_LONG_CLOSE_PASS");

        // BUY CLOSE with no short must reject without mutation.
        start_req(1,1,`HFT_RMIC_ACCT_EVENT_RESERVE,`HFT_RMIC_RMIC_SIDE_BUY,
                  `HFT_RMIC_TAIFEX_POS_CLOSE,1,0,0);
        expect_rsp(0,`HFT_RMIC_POLICY_REASON_CLOSE_SHORT_INSUFFICIENT,1,1,0,0,0,0,0,1000,1000);

        // Product-specific margin budget.
        start_req(1,2,`HFT_RMIC_ACCT_EVENT_RESERVE,`HFT_RMIC_RMIC_SIDE_BUY,
                  `HFT_RMIC_TAIFEX_POS_OPEN,2,0,0);
        expect_rsp(0,`HFT_RMIC_POLICY_REASON_MARGIN_LIMIT,1,0,0,0,0,0,0,0,0);
        $display("HFT_RMIC_STATE_MARGIN_REJECT_PASS");

        // Fail-closed key ownership.
        query_expect(7,0,0,`HFT_RMIC_POLICY_REASON_STATE_KEY_INVALID,0,0,0,0,0,0,0,0);
        query_expect(0,0,0,`HFT_RMIC_POLICY_REASON_STATE_UNCONFIGURED,0,0,0,0,0,0,0,0);
        query_expect(3,1,0,`HFT_RMIC_POLICY_REASON_STATE_DISABLED,0,0,0,0,0,0,0,0);
        $display("HFT_RMIC_STATE_FAIL_CLOSED_PASS");

        // Configuration priority: both valids asserted, only cfg may handshake.
        @(negedge clk);
        cfg_account_id=0; cfg_product_id=2; cfg_enabled=1;
        cfg_margin_budget=5000; cfg_margin_per_contract=500;
        cfg_long_position=0; cfg_short_position=0;
        cfg_pending_open_long=0; cfg_pending_open_short=0;
        cfg_reserved_close_long=0; cfg_reserved_close_short=0;
        cfg_valid=1;
        req_account_id=1; req_product_id=1; req_event_kind=`HFT_RMIC_ACCT_EVENT_QUERY;
        req_side=0; req_position_effect=`HFT_RMIC_TAIFEX_POS_OPEN;
        req_order_qty=0; req_fill_qty=0; req_release_qty=0; req_valid=1;
        #1;
        if (!cfg_ready || req_ready) fail("configuration priority contract failed");
        @(posedge clk); // cfg handshake
        @(negedge clk);
        if (!cfg_done || !cfg_ok) fail("priority configuration did not commit");
        cfg_valid=0;
        #1;
        if (!req_ready) fail("request did not become ready after configuration");
        @(posedge clk); // request handshake
        @(negedge clk); req_valid=0;
        while (!rsp_valid) @(posedge clk);
        #1;
        expect_rsp(1,`HFT_RMIC_POLICY_REASON_PASS,1,1,0,0,0,0,0,1000,1000);
        $display("HFT_RMIC_STATE_CFG_PRIORITY_PASS");

        // Reset invalidates all configured ownership and forces recovery.
        @(negedge clk); rst_n=0;
        repeat(3) @(posedge clk);
        @(negedge clk); rst_n=1;
        query_expect(1,1,0,`HFT_RMIC_POLICY_REASON_STATE_UNCONFIGURED,0,0,0,0,0,0,0,0);
        $display("HFT_RMIC_STATE_RESET_RECOVERY_PASS");

        $display("HFT_RMIC_FUTURES_STATE_MANAGER_TB_PASS");
        $finish;
    end

    initial begin
        #200000;
        fail("timeout");
    end
endmodule
