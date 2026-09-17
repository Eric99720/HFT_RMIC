`timescale 1ns/1ps
`include "hft_rmic_accounting_defs.svh"
`include "hft_rmic_contract.svh"
`include "hft_rmic_policy_defs.svh"
`include "taifex_tmp_v2187_defs.svh"

module tb_hft_rmic_committed_execution_bridge_v1;
    localparam integer QTY_W = 16;
    localparam integer MARGIN_W = 32;
    localparam [1:0] OP_LOOKUP=2'd0, OP_INSERT=2'd1, OP_DELETE=2'd2, OP_UPDATE=2'd3;

    reg clk=0; always #5 clk=~clk;
    reg rst_n=0;

    // Bridge event/result.
    reg commit_valid=0;
    wire commit_ready;
    reg [7:0] commit_msg_type=0, commit_status_code=0, commit_exec_type=0;
    reg [31:0] commit_order_id=0;
    reg commit_side=0;
    reg [7:0] commit_position_effect=0;
    reg [31:0] commit_order_price=0;
    reg [QTY_W-1:0] commit_last_qty=0, commit_leaves_qty=0, commit_before_qty=0;
    wire result_valid;
    reg result_ready=0;
    wire result_ok;
    wire [1:0] result_reason_source;
    wire [7:0] result_reason_code;
    wire [31:0] result_order_id;
    wire [QTY_W-1:0] result_remaining_qty;

    // Bridge -> store.
    wire br_store_req_valid, br_store_req_ready;
    wire [1:0] br_store_req_op;
    wire [31:0] br_store_req_order_id;
    wire [7:0] br_store_req_account_id, br_store_req_product_id;
    wire br_store_req_side;
    wire [7:0] br_store_req_position_effect, br_store_req_order_type, br_store_req_tif;
    wire [31:0] br_store_req_limit_price;
    wire [QTY_W-1:0] br_store_req_remaining_qty;
    wire br_store_rsp_valid, br_store_rsp_ready, br_store_rsp_ok, br_store_rsp_found;
    wire [2:0] br_store_rsp_status;
    wire [7:0] br_store_rsp_account_id, br_store_rsp_product_id;
    wire br_store_rsp_side;
    wire [7:0] br_store_rsp_position_effect, br_store_rsp_order_type, br_store_rsp_tif;
    wire [31:0] br_store_rsp_limit_price;
    wire [QTY_W-1:0] br_store_rsp_remaining_qty;

    // TB preload/query client for store.
    reg tb_store_owner=1;
    reg tb_store_req_valid=0;
    wire tb_store_req_ready;
    reg [1:0] tb_store_req_op=0;
    reg [31:0] tb_store_req_order_id=0;
    reg [7:0] tb_store_req_account_id=0, tb_store_req_product_id=0;
    reg tb_store_req_side=0;
    reg [7:0] tb_store_req_position_effect=0, tb_store_req_order_type=0, tb_store_req_tif=0;
    reg [31:0] tb_store_req_limit_price=0;
    reg [QTY_W-1:0] tb_store_req_remaining_qty=0;
    reg tb_store_rsp_ready=0;

    wire os_req_valid = tb_store_owner ? tb_store_req_valid : br_store_req_valid;
    wire [1:0] os_req_op = tb_store_owner ? tb_store_req_op : br_store_req_op;
    wire [31:0] os_req_order_id = tb_store_owner ? tb_store_req_order_id : br_store_req_order_id;
    wire [7:0] os_req_account_id = tb_store_owner ? tb_store_req_account_id : br_store_req_account_id;
    wire [7:0] os_req_product_id = tb_store_owner ? tb_store_req_product_id : br_store_req_product_id;
    wire os_req_side = tb_store_owner ? tb_store_req_side : br_store_req_side;
    wire [7:0] os_req_position_effect = tb_store_owner ? tb_store_req_position_effect : br_store_req_position_effect;
    wire [7:0] os_req_order_type = tb_store_owner ? tb_store_req_order_type : br_store_req_order_type;
    wire [7:0] os_req_tif = tb_store_owner ? tb_store_req_tif : br_store_req_tif;
    wire [31:0] os_req_limit_price = tb_store_owner ? tb_store_req_limit_price : br_store_req_limit_price;
    wire [QTY_W-1:0] os_req_remaining_qty = tb_store_owner ? tb_store_req_remaining_qty : br_store_req_remaining_qty;
    wire os_rsp_ready = tb_store_owner ? tb_store_rsp_ready : br_store_rsp_ready;
    wire os_req_ready, os_rsp_valid, os_rsp_ok, os_rsp_found;
    wire [2:0] os_rsp_status;
    wire [7:0] os_rsp_account_id, os_rsp_product_id;
    wire os_rsp_side;
    wire [7:0] os_rsp_position_effect, os_rsp_order_type, os_rsp_tif;
    wire [31:0] os_rsp_limit_price;
    wire [QTY_W-1:0] os_rsp_remaining_qty;
    wire [2:0] os_rsp_bank;
    wire os_rsp_in_stash, os_init_done;
    assign tb_store_req_ready = os_req_ready;
    assign br_store_req_ready = os_req_ready;
    assign br_store_rsp_valid = os_rsp_valid;
    assign br_store_rsp_ok = os_rsp_ok;
    assign br_store_rsp_found = os_rsp_found;
    assign br_store_rsp_status = os_rsp_status;
    assign br_store_rsp_account_id = os_rsp_account_id;
    assign br_store_rsp_product_id = os_rsp_product_id;
    assign br_store_rsp_side = os_rsp_side;
    assign br_store_rsp_position_effect = os_rsp_position_effect;
    assign br_store_rsp_order_type = os_rsp_order_type;
    assign br_store_rsp_tif = os_rsp_tif;
    assign br_store_rsp_limit_price = os_rsp_limit_price;
    assign br_store_rsp_remaining_qty = os_rsp_remaining_qty;

    hft_rmic_futures_order_store_v1 #(.TABLE_SIZE(64), .QTY_W(QTY_W)) u_store (
        .clk(clk),.rst_n(rst_n),
        .req_valid(os_req_valid),.req_ready(os_req_ready),.req_op(os_req_op),
        .req_order_id(os_req_order_id),.req_account_id(os_req_account_id),
        .req_product_id(os_req_product_id),.req_side(os_req_side),
        .req_position_effect(os_req_position_effect),.req_order_type(os_req_order_type),
        .req_tif(os_req_tif),.req_limit_price(os_req_limit_price),
        .req_remaining_qty(os_req_remaining_qty),
        .rsp_valid(os_rsp_valid),.rsp_ready(os_rsp_ready),.rsp_ok(os_rsp_ok),
        .rsp_found(os_rsp_found),.rsp_status(os_rsp_status),
        .rsp_account_id(os_rsp_account_id),.rsp_product_id(os_rsp_product_id),
        .rsp_side(os_rsp_side),.rsp_position_effect(os_rsp_position_effect),
        .rsp_order_type(os_rsp_order_type),.rsp_tif(os_rsp_tif),
        .rsp_limit_price(os_rsp_limit_price),.rsp_remaining_qty(os_rsp_remaining_qty),
        .rsp_bank(os_rsp_bank),.rsp_in_stash(os_rsp_in_stash),.init_done(os_init_done)
    );

    // State manager configuration.
    reg cfg_valid=0; wire cfg_ready;
    reg [7:0] cfg_account_id=0, cfg_product_id=0;
    reg cfg_enabled=0;
    reg [MARGIN_W-1:0] cfg_margin_budget=0,cfg_margin_per_contract=0;
    reg [QTY_W-1:0] cfg_long_position=0,cfg_short_position=0,
        cfg_pending_open_long=0,cfg_pending_open_short=0,
        cfg_reserved_close_long=0,cfg_reserved_close_short=0;
    wire cfg_done,cfg_ok; wire [7:0] cfg_reason_code;

    // Bridge -> accounting request.
    wire br_acct_req_valid, br_acct_req_ready;
    wire [7:0] br_acct_req_account_id, br_acct_req_product_id;
    wire [2:0] br_acct_req_event_kind;
    wire br_acct_req_side;
    wire [7:0] br_acct_req_position_effect;
    wire [QTY_W-1:0] br_acct_req_order_qty,br_acct_req_fill_qty,br_acct_req_release_qty;
    wire br_acct_rsp_valid, br_acct_rsp_ready, br_acct_rsp_ok;
    wire [1:0] br_acct_rsp_reason_source;
    wire [7:0] br_acct_rsp_reason_code;

    // TB query client for state manager.
    reg tb_acct_owner=0;
    reg tb_acct_req_valid=0; wire tb_acct_req_ready;
    reg [7:0] tb_acct_req_account_id=0,tb_acct_req_product_id=0;
    reg [2:0] tb_acct_req_event_kind=`HFT_RMIC_ACCT_EVENT_QUERY;
    reg tb_acct_req_side=0;
    reg [7:0] tb_acct_req_position_effect=`HFT_RMIC_TAIFEX_POS_OPEN;
    reg [QTY_W-1:0] tb_acct_req_order_qty=0,tb_acct_req_fill_qty=0,tb_acct_req_release_qty=0;
    reg tb_acct_rsp_ready=0;

    wire sm_req_valid = tb_acct_owner ? tb_acct_req_valid : br_acct_req_valid;
    wire [7:0] sm_req_account_id = tb_acct_owner ? tb_acct_req_account_id : br_acct_req_account_id;
    wire [7:0] sm_req_product_id = tb_acct_owner ? tb_acct_req_product_id : br_acct_req_product_id;
    wire [2:0] sm_req_event_kind = tb_acct_owner ? tb_acct_req_event_kind : br_acct_req_event_kind;
    wire sm_req_side = tb_acct_owner ? tb_acct_req_side : br_acct_req_side;
    wire [7:0] sm_req_position_effect = tb_acct_owner ? tb_acct_req_position_effect : br_acct_req_position_effect;
    wire [QTY_W-1:0] sm_req_order_qty = tb_acct_owner ? tb_acct_req_order_qty : br_acct_req_order_qty;
    wire [QTY_W-1:0] sm_req_fill_qty = tb_acct_owner ? tb_acct_req_fill_qty : br_acct_req_fill_qty;
    wire [QTY_W-1:0] sm_req_release_qty = tb_acct_owner ? tb_acct_req_release_qty : br_acct_req_release_qty;
    wire sm_rsp_ready = tb_acct_owner ? tb_acct_rsp_ready : br_acct_rsp_ready;
    wire sm_req_ready,sm_rsp_valid,sm_rsp_ok; wire [1:0] sm_rsp_reason_source; wire [7:0] sm_rsp_reason_code;
    wire sm_rsp_enabled; wire [QTY_W-1:0] sm_rsp_long,sm_rsp_short,sm_rsp_pol,sm_rsp_pos,sm_rsp_rcl,sm_rsp_rcs;
    wire [MARGIN_W-1:0] sm_rsp_mb,sm_rsp_ma;
    assign tb_acct_req_ready=sm_req_ready;
    assign br_acct_req_ready=sm_req_ready;
    assign br_acct_rsp_valid=sm_rsp_valid;
    assign br_acct_rsp_ok=sm_rsp_ok;
    assign br_acct_rsp_reason_source=sm_rsp_reason_source;
    assign br_acct_rsp_reason_code=sm_rsp_reason_code;

    hft_rmic_futures_state_manager_v1 #(
        .NUM_ACCOUNTS(4),.NUM_PRODUCTS(4),.ACCOUNT_ID_W(8),.PRODUCT_ID_W(8),
        .QTY_W(QTY_W),.MARGIN_W(MARGIN_W)
    ) u_state (
        .clk(clk),.rst_n(rst_n),
        .cfg_valid(cfg_valid),.cfg_ready(cfg_ready),.cfg_account_id(cfg_account_id),
        .cfg_product_id(cfg_product_id),.cfg_enabled(cfg_enabled),
        .cfg_margin_budget(cfg_margin_budget),.cfg_margin_per_contract(cfg_margin_per_contract),
        .cfg_long_position(cfg_long_position),.cfg_short_position(cfg_short_position),
        .cfg_pending_open_long(cfg_pending_open_long),.cfg_pending_open_short(cfg_pending_open_short),
        .cfg_reserved_close_long(cfg_reserved_close_long),.cfg_reserved_close_short(cfg_reserved_close_short),
        .cfg_done(cfg_done),.cfg_ok(cfg_ok),.cfg_reason_code(cfg_reason_code),
        .req_valid(sm_req_valid),.req_ready(sm_req_ready),.req_account_id(sm_req_account_id),
        .req_product_id(sm_req_product_id),.req_event_kind(sm_req_event_kind),.req_side(sm_req_side),
        .req_position_effect(sm_req_position_effect),.req_order_qty(sm_req_order_qty),
        .req_fill_qty(sm_req_fill_qty),.req_release_qty(sm_req_release_qty),
        .rsp_valid(sm_rsp_valid),.rsp_ready(sm_rsp_ready),.rsp_ok(sm_rsp_ok),
        .rsp_reason_source(sm_rsp_reason_source),.rsp_reason_code(sm_rsp_reason_code),
        .rsp_account_id(),.rsp_product_id(),.rsp_entry_enabled(sm_rsp_enabled),
        .rsp_long_position(sm_rsp_long),.rsp_short_position(sm_rsp_short),
        .rsp_pending_open_long(sm_rsp_pol),.rsp_pending_open_short(sm_rsp_pos),
        .rsp_reserved_close_long(sm_rsp_rcl),.rsp_reserved_close_short(sm_rsp_rcs),
        .rsp_required_margin_before(sm_rsp_mb),.rsp_required_margin_after(sm_rsp_ma)
    );

    hft_rmic_committed_execution_bridge_v1 #(.QTY_W(QTY_W)) dut (
        .clk(clk),.rst_n(rst_n),
        .commit_valid(commit_valid),.commit_ready(commit_ready),.commit_msg_type(commit_msg_type),
        .commit_status_code(commit_status_code),.commit_exec_type(commit_exec_type),
        .commit_order_id(commit_order_id),.commit_side(commit_side),
        .commit_position_effect(commit_position_effect),.commit_order_price(commit_order_price),
        .commit_last_qty(commit_last_qty),.commit_leaves_qty(commit_leaves_qty),
        .commit_before_qty(commit_before_qty),
        .result_valid(result_valid),.result_ready(result_ready),.result_ok(result_ok),
        .result_reason_source(result_reason_source),.result_reason_code(result_reason_code),
        .result_order_id(result_order_id),.result_remaining_qty(result_remaining_qty),
        .store_req_valid(br_store_req_valid),.store_req_ready(br_store_req_ready),
        .store_req_op(br_store_req_op),.store_req_order_id(br_store_req_order_id),
        .store_req_account_id(br_store_req_account_id),.store_req_product_id(br_store_req_product_id),
        .store_req_side(br_store_req_side),.store_req_position_effect(br_store_req_position_effect),
        .store_req_order_type(br_store_req_order_type),.store_req_tif(br_store_req_tif),
        .store_req_limit_price(br_store_req_limit_price),.store_req_remaining_qty(br_store_req_remaining_qty),
        .store_rsp_valid(br_store_rsp_valid),.store_rsp_ready(br_store_rsp_ready),
        .store_rsp_ok(br_store_rsp_ok),.store_rsp_found(br_store_rsp_found),
        .store_rsp_status(br_store_rsp_status),.store_rsp_account_id(br_store_rsp_account_id),
        .store_rsp_product_id(br_store_rsp_product_id),.store_rsp_side(br_store_rsp_side),
        .store_rsp_position_effect(br_store_rsp_position_effect),.store_rsp_order_type(br_store_rsp_order_type),
        .store_rsp_tif(br_store_rsp_tif),.store_rsp_limit_price(br_store_rsp_limit_price),
        .store_rsp_remaining_qty(br_store_rsp_remaining_qty),
        .acct_req_valid(br_acct_req_valid),.acct_req_ready(br_acct_req_ready),
        .acct_req_account_id(br_acct_req_account_id),.acct_req_product_id(br_acct_req_product_id),
        .acct_req_event_kind(br_acct_req_event_kind),.acct_req_side(br_acct_req_side),
        .acct_req_position_effect(br_acct_req_position_effect),.acct_req_order_qty(br_acct_req_order_qty),
        .acct_req_fill_qty(br_acct_req_fill_qty),.acct_req_release_qty(br_acct_req_release_qty),
        .acct_rsp_valid(br_acct_rsp_valid),.acct_rsp_ready(br_acct_rsp_ready),.acct_rsp_ok(br_acct_rsp_ok),
        .acct_rsp_reason_source(br_acct_rsp_reason_source),.acct_rsp_reason_code(br_acct_rsp_reason_code)
    );

    task fail; input [8*120-1:0] msg; begin $display("TEST_FAIL %0s",msg); $fatal(1); end endtask

    task cfg_state;
        input [QTY_W-1:0] lp,sp,pol,pos;
        begin
            @(negedge clk);
            cfg_account_id=1; cfg_product_id=1; cfg_enabled=1;
            cfg_margin_budget=32'd50000; cfg_margin_per_contract=32'd1000;
            cfg_long_position=lp; cfg_short_position=sp;
            cfg_pending_open_long=pol; cfg_pending_open_short=pos;
            cfg_reserved_close_long=0; cfg_reserved_close_short=0; cfg_valid=1;
            do @(posedge clk); while (!cfg_ready);
            #1; if (!cfg_done || !cfg_ok) fail("cfg state failed");
            @(negedge clk); cfg_valid=0;
        end
    endtask

    task store_issue;
        input [1:0] op; input [31:0] oid; input side;
        input [7:0] pe; input [QTY_W-1:0] rem;
        begin
            tb_store_owner=1;
            @(negedge clk);
            tb_store_req_op=op; tb_store_req_order_id=oid;
            tb_store_req_account_id=1; tb_store_req_product_id=1; tb_store_req_side=side;
            tb_store_req_position_effect=pe; tb_store_req_order_type=`HFT_RMIC_TAIFEX_ORD_LIMIT;
            tb_store_req_tif=`HFT_RMIC_TAIFEX_TIF_ROD; tb_store_req_limit_price=32'd1000;
            tb_store_req_remaining_qty=rem; tb_store_req_valid=1;
            do @(posedge clk); while (!tb_store_req_ready);
            @(negedge clk); tb_store_req_valid=0;
            while (!os_rsp_valid) @(posedge clk);
        end
    endtask

    task store_expect;
        input exp_ok; input exp_found; input [QTY_W-1:0] exp_rem;
        begin
            if (os_rsp_ok!==exp_ok || os_rsp_found!==exp_found) fail("store response mismatch");
            if (exp_found && os_rsp_remaining_qty!==exp_rem) fail("store remaining mismatch");
            @(negedge clk); tb_store_rsp_ready=1;
            @(posedge clk); @(negedge clk); tb_store_rsp_ready=0;
        end
    endtask

    task insert_ctx;
        input [31:0] oid; input side; input [7:0] pe; input [QTY_W-1:0] rem;
        begin store_issue(OP_INSERT,oid,side,pe,rem); store_expect(1,1,rem); end
    endtask

    task lookup_ctx;
        input [31:0] oid; input exp_found; input [QTY_W-1:0] exp_rem;
        begin
            store_issue(OP_LOOKUP,oid,0,0,0);
            store_expect(exp_found,exp_found,exp_rem);
        end
    endtask

    task query_state;
        input [QTY_W-1:0] lp,sp,pol,pos;
        begin
            tb_acct_owner=1;
            @(negedge clk);
            tb_acct_req_account_id=1; tb_acct_req_product_id=1;
            tb_acct_req_event_kind=`HFT_RMIC_ACCT_EVENT_QUERY;
            tb_acct_req_side=0; tb_acct_req_position_effect=`HFT_RMIC_TAIFEX_POS_OPEN;
            tb_acct_req_order_qty=0;tb_acct_req_fill_qty=0;tb_acct_req_release_qty=0;
            tb_acct_req_valid=1;
            do @(posedge clk); while (!tb_acct_req_ready);
            @(negedge clk);tb_acct_req_valid=0;
            while(!sm_rsp_valid) @(posedge clk);
            if(!sm_rsp_ok || sm_rsp_long!==lp || sm_rsp_short!==sp ||
               sm_rsp_pol!==pol || sm_rsp_pos!==pos) fail("account state mismatch");
            @(negedge clk);tb_acct_rsp_ready=1;
            @(posedge clk);@(negedge clk);tb_acct_rsp_ready=0;
            tb_acct_owner=0;
        end
    endtask

    task send_event;
        input [7:0] mt,st,et; input [31:0] oid; input side; input [7:0] pe;
        input [QTY_W-1:0] lastq,leaves,beforeq;
        input exp_ok; input [1:0] exp_src; input [7:0] exp_reason; input [QTY_W-1:0] exp_rem;
        begin
            tb_store_owner=0;tb_acct_owner=0;
            @(negedge clk);
            commit_msg_type=mt;commit_status_code=st;commit_exec_type=et;commit_order_id=oid;
            commit_side=side;commit_position_effect=pe;commit_order_price=32'd1100;
            commit_last_qty=lastq;commit_leaves_qty=leaves;commit_before_qty=beforeq;
            commit_valid=1;
            do @(posedge clk); while(!commit_ready);
            @(negedge clk);commit_valid=0;
            while(!result_valid) @(posedge clk);
            if(result_ok!==exp_ok || result_reason_source!==exp_src ||
               result_reason_code!==exp_reason || result_remaining_qty!==exp_rem)
                fail("bridge result mismatch");
            @(negedge clk);result_ready=1;
            @(posedge clk);@(negedge clk);result_ready=0;
        end
    endtask

    initial begin
        repeat(4) @(posedge clk); rst_n=1;
        while(!os_init_done) @(posedge clk);

        // Partial BUY OPEN fill 10 -> 7.
        cfg_state(0,0,10,0); insert_ctx(100,0,`HFT_RMIC_TAIFEX_POS_OPEN,10);
        send_event(`HFT_RMIC_TAIFEX_MSG_R02,0,`HFT_RMIC_TAIFEX_EXEC_TRADE,100,0,
                   `HFT_RMIC_TAIFEX_POS_OPEN,3,7,10,1,`HFT_RMIC_REASON_SRC_SYSTEM,
                   `HFT_RMIC_SYSTEM_REASON_PASS,7);
        query_state(3,0,7,0); lookup_ctx(100,1,7);
        $display("HFT_RMIC_EXEC_PARTIAL_FILL_PASS");

        // Even if an old committed report is accidentally redelivered, the
        // before_qty/context mismatch prevents double application.
        send_event(`HFT_RMIC_TAIFEX_MSG_R02,0,`HFT_RMIC_TAIFEX_EXEC_TRADE,100,0,
                   `HFT_RMIC_TAIFEX_POS_OPEN,3,7,10,0,`HFT_RMIC_REASON_SRC_SYSTEM,
                   `HFT_RMIC_SYSTEM_REASON_EXEC_METADATA_MISMATCH,7);
        query_state(3,0,7,0);
        $display("HFT_RMIC_EXEC_DUPLICATE_FAIL_CLOSED_PASS");

        // Gap/stale quantity likewise cannot mutate.
        send_event(`HFT_RMIC_TAIFEX_MSG_R32,0,`HFT_RMIC_TAIFEX_EXEC_TRADE,100,0,
                   `HFT_RMIC_TAIFEX_POS_OPEN,1,8,9,0,`HFT_RMIC_REASON_SRC_SYSTEM,
                   `HFT_RMIC_SYSTEM_REASON_EXEC_METADATA_MISMATCH,7);
        query_state(3,0,7,0);

        // Next valid/replayed-then-committed report mutates exactly once.
        send_event(`HFT_RMIC_TAIFEX_MSG_R32,0,`HFT_RMIC_TAIFEX_EXEC_TRADE,100,0,
                   `HFT_RMIC_TAIFEX_POS_OPEN,2,5,7,1,`HFT_RMIC_REASON_SRC_SYSTEM,
                   `HFT_RMIC_SYSTEM_REASON_PASS,5);
        query_state(5,0,5,0);
        $display("HFT_RMIC_EXEC_REPLAY_COMMIT_ONCE_PASS");

        // IOC-style terminal report: fill 2 and auto-release remaining 3.
        send_event(`HFT_RMIC_TAIFEX_MSG_R02,8'd47,`HFT_RMIC_TAIFEX_EXEC_TRADE,100,0,
                   `HFT_RMIC_TAIFEX_POS_OPEN,2,0,5,1,`HFT_RMIC_REASON_SRC_SYSTEM,
                   `HFT_RMIC_SYSTEM_REASON_PASS,0);
        query_state(7,0,0,0); lookup_ctx(100,0,0);
        send_event(`HFT_RMIC_TAIFEX_MSG_R02,8'd47,`HFT_RMIC_TAIFEX_EXEC_TRADE,100,0,
                   `HFT_RMIC_TAIFEX_POS_OPEN,2,0,5,0,`HFT_RMIC_REASON_SRC_SYSTEM,
                   `HFT_RMIC_SYSTEM_REASON_ORDER_CONTEXT_NOT_FOUND,0);
        query_state(7,0,0,0);
        $display("HFT_RMIC_EXEC_TERMINAL_FILL_RELEASE_PASS");

        // Cancel SELL OPEN releases all remaining pending short.
        cfg_state(7,0,0,4); insert_ctx(101,1,`HFT_RMIC_TAIFEX_POS_OPEN,4);
        send_event(`HFT_RMIC_TAIFEX_MSG_R02,0,`HFT_RMIC_TAIFEX_EXEC_CANCEL,101,1,
                   `HFT_RMIC_TAIFEX_POS_OPEN,0,0,4,1,`HFT_RMIC_REASON_SRC_SYSTEM,
                   `HFT_RMIC_SYSTEM_REASON_PASS,0);
        query_state(7,0,0,0); lookup_ctx(101,0,0);
        $display("HFT_RMIC_EXEC_CANCEL_RELEASE_PASS");

        // Reduce BUY OPEN 5 -> 2, then R03 releases the remaining 2 once.
        cfg_state(7,0,5,0); insert_ctx(102,0,`HFT_RMIC_TAIFEX_POS_OPEN,5);
        send_event(`HFT_RMIC_TAIFEX_MSG_R32,0,`HFT_RMIC_TAIFEX_EXEC_REDUCE,102,0,
                   `HFT_RMIC_TAIFEX_POS_OPEN,0,2,5,1,`HFT_RMIC_REASON_SRC_SYSTEM,
                   `HFT_RMIC_SYSTEM_REASON_PASS,2);
        query_state(7,0,2,0); lookup_ctx(102,1,2);
        send_event(`HFT_RMIC_TAIFEX_MSG_R03,8'd99,8'd0,102,0,8'd0,0,0,0,
                   1,`HFT_RMIC_REASON_SRC_SYSTEM,`HFT_RMIC_SYSTEM_REASON_PASS,0);
        query_state(7,0,0,0); lookup_ctx(102,0,0);
        send_event(`HFT_RMIC_TAIFEX_MSG_R03,8'd99,8'd0,102,0,8'd0,0,0,0,
                   0,`HFT_RMIC_REASON_SRC_SYSTEM,`HFT_RMIC_SYSTEM_REASON_ORDER_CONTEXT_NOT_FOUND,0);
        query_state(7,0,0,0);
        $display("HFT_RMIC_EXEC_R03_RELEASE_ONCE_PASS");

        $display("HFT_RMIC_COMMITTED_EXECUTION_BRIDGE_TB_PASS");
        $finish;
    end

    initial begin #500000; fail("timeout"); end
endmodule
