`timescale 1ns/1ps
`include "hft_rmic_accounting_defs.svh"
`include "hft_rmic_policy_defs.svh"
`include "taifex_tmp_v2187_defs.svh"

module tb_hft_rmic_cl2ex_admission_v1;
    localparam QTY_W = 16;
    localparam ORDER_W = 256;

    reg clk=0; always #5 clk=~clk;
    reg rst_n=0;

    reg order_valid;
    wire order_ready;
    reg [ORDER_W-1:0] order_data;
    reg policy_pass;
    reg [1:0] policy_reason_source;
    reg [7:0] policy_reason_code;
    reg [31:0] order_id;
    reg [7:0] account_id, product_id;
    reg side;
    reg [7:0] position_effect, order_type, tif;
    reg [31:0] limit_price;
    reg [QTY_W-1:0] qty;
    wire result_valid;
    reg result_ready;
    wire result_accepted;
    wire [1:0] result_reason_source;
    wire [7:0] result_reason_code;
    wire [31:0] result_order_id;
    wire [ORDER_W-1:0] result_order_data;

    wire g_acct_req_valid, g_acct_req_ready;
    wire [7:0] g_acct_req_account_id, g_acct_req_product_id;
    wire [2:0] g_acct_req_event_kind;
    wire g_acct_req_side;
    wire [7:0] g_acct_req_position_effect;
    wire [QTY_W-1:0] g_acct_req_order_qty, g_acct_req_fill_qty, g_acct_req_release_qty;
    wire g_acct_rsp_valid, g_acct_rsp_ready, g_acct_rsp_ok;
    wire [1:0] g_acct_rsp_reason_source;
    wire [7:0] g_acct_rsp_reason_code;

    wire g_store_req_valid, g_store_req_ready;
    wire [1:0] g_store_req_op;
    wire [31:0] g_store_req_order_id;
    wire [7:0] g_store_req_account_id, g_store_req_product_id;
    wire g_store_req_side;
    wire [7:0] g_store_req_position_effect, g_store_req_order_type, g_store_req_tif;
    wire [31:0] g_store_req_limit_price;
    wire [QTY_W-1:0] g_store_req_remaining_qty;
    wire g_store_rsp_valid, g_store_rsp_ready, g_store_rsp_ok, g_store_rsp_found;
    wire [2:0] g_store_rsp_status;

    hft_rmic_cl2ex_admission_v1 #(.ORDER_WIDTH(ORDER_W),.QTY_W(QTY_W)) dut (
        .clk(clk),.rst_n(rst_n),.order_valid(order_valid),.order_ready(order_ready),
        .order_data(order_data),.policy_pass(policy_pass),
        .policy_reason_source(policy_reason_source),.policy_reason_code(policy_reason_code),
        .order_id(order_id),.account_id(account_id),.product_id(product_id),.side(side),
        .position_effect(position_effect),.order_type(order_type),.tif(tif),
        .limit_price(limit_price),.qty(qty),
        .result_valid(result_valid),.result_ready(result_ready),.result_accepted(result_accepted),
        .result_reason_source(result_reason_source),.result_reason_code(result_reason_code),
        .result_order_id(result_order_id),.result_order_data(result_order_data),
        .acct_req_valid(g_acct_req_valid),.acct_req_ready(g_acct_req_ready),
        .acct_req_account_id(g_acct_req_account_id),.acct_req_product_id(g_acct_req_product_id),
        .acct_req_event_kind(g_acct_req_event_kind),.acct_req_side(g_acct_req_side),
        .acct_req_position_effect(g_acct_req_position_effect),.acct_req_order_qty(g_acct_req_order_qty),
        .acct_req_fill_qty(g_acct_req_fill_qty),.acct_req_release_qty(g_acct_req_release_qty),
        .acct_rsp_valid(g_acct_rsp_valid),.acct_rsp_ready(g_acct_rsp_ready),
        .acct_rsp_ok(g_acct_rsp_ok),.acct_rsp_reason_source(g_acct_rsp_reason_source),
        .acct_rsp_reason_code(g_acct_rsp_reason_code),
        .store_req_valid(g_store_req_valid),.store_req_ready(g_store_req_ready),
        .store_req_op(g_store_req_op),.store_req_order_id(g_store_req_order_id),
        .store_req_account_id(g_store_req_account_id),.store_req_product_id(g_store_req_product_id),
        .store_req_side(g_store_req_side),.store_req_position_effect(g_store_req_position_effect),
        .store_req_order_type(g_store_req_order_type),.store_req_tif(g_store_req_tif),
        .store_req_limit_price(g_store_req_limit_price),.store_req_remaining_qty(g_store_req_remaining_qty),
        .store_rsp_valid(g_store_rsp_valid),.store_rsp_ready(g_store_rsp_ready),
        .store_rsp_ok(g_store_rsp_ok),.store_rsp_found(g_store_rsp_found),
        .store_rsp_status(g_store_rsp_status)
    );

    // Debug ownership mux lets the TB query committed state/context only while
    // the admission controller is idle.  It is not part of production RTL.
    reg dbg_acct_mode, dbg_acct_valid;
    wire dbg_acct_ready;
    reg [2:0] dbg_acct_kind;
    wire acct_req_valid = dbg_acct_mode ? dbg_acct_valid : g_acct_req_valid;
    wire [7:0] acct_req_account_id = dbg_acct_mode ? 8'd1 : g_acct_req_account_id;
    wire [7:0] acct_req_product_id = dbg_acct_mode ? 8'd1 : g_acct_req_product_id;
    wire [2:0] acct_req_event_kind = dbg_acct_mode ? dbg_acct_kind : g_acct_req_event_kind;
    wire acct_req_side = dbg_acct_mode ? 1'b0 : g_acct_req_side;
    wire [7:0] acct_req_position_effect = dbg_acct_mode ? `HFT_RMIC_TAIFEX_POS_OPEN : g_acct_req_position_effect;
    wire [QTY_W-1:0] acct_req_order_qty = dbg_acct_mode ? 0 : g_acct_req_order_qty;
    wire [QTY_W-1:0] acct_req_fill_qty = dbg_acct_mode ? 0 : g_acct_req_fill_qty;
    wire [QTY_W-1:0] acct_req_release_qty = dbg_acct_mode ? 0 : g_acct_req_release_qty;
    wire acct_rsp_ready = dbg_acct_mode ? 1'b1 : g_acct_rsp_ready;
    wire acct_req_ready_i, acct_rsp_valid_i, acct_rsp_ok_i;
    wire [1:0] acct_rsp_reason_source_i;
    wire [7:0] acct_rsp_reason_code_i;
    wire [QTY_W-1:0] acct_rsp_pending_long;
    assign g_acct_req_ready = dbg_acct_mode ? 1'b0 : acct_req_ready_i;
    assign g_acct_rsp_valid = dbg_acct_mode ? 1'b0 : acct_rsp_valid_i;
    assign g_acct_rsp_ok = acct_rsp_ok_i;
    assign g_acct_rsp_reason_source = acct_rsp_reason_source_i;
    assign g_acct_rsp_reason_code = acct_rsp_reason_code_i;
    assign dbg_acct_ready = dbg_acct_mode ? acct_req_ready_i : 1'b0;

    reg cfg_valid;
    wire cfg_ready, cfg_done, cfg_ok;
    wire [7:0] cfg_reason;
    hft_rmic_futures_state_manager_v1 #(.NUM_ACCOUNTS(4),.NUM_PRODUCTS(4),.QTY_W(QTY_W),.MARGIN_W(64)) u_state (
        .clk(clk),.rst_n(rst_n),.cfg_valid(cfg_valid),.cfg_ready(cfg_ready),
        .cfg_account_id(8'd1),.cfg_product_id(8'd1),.cfg_enabled(1'b1),
        .cfg_margin_budget(64'd100000),.cfg_margin_per_contract(64'd1000),
        .cfg_long_position(0),.cfg_short_position(0),.cfg_pending_open_long(0),
        .cfg_pending_open_short(0),.cfg_reserved_close_long(0),.cfg_reserved_close_short(0),
        .cfg_done(cfg_done),.cfg_ok(cfg_ok),.cfg_reason_code(cfg_reason),
        .req_valid(acct_req_valid),.req_ready(acct_req_ready_i),
        .req_account_id(acct_req_account_id),.req_product_id(acct_req_product_id),
        .req_event_kind(acct_req_event_kind),.req_side(acct_req_side),
        .req_position_effect(acct_req_position_effect),.req_order_qty(acct_req_order_qty),
        .req_fill_qty(acct_req_fill_qty),.req_release_qty(acct_req_release_qty),
        .rsp_valid(acct_rsp_valid_i),.rsp_ready(acct_rsp_ready),.rsp_ok(acct_rsp_ok_i),
        .rsp_reason_source(acct_rsp_reason_source_i),.rsp_reason_code(acct_rsp_reason_code_i),
        .rsp_account_id(),.rsp_product_id(),.rsp_entry_enabled(),.rsp_long_position(),.rsp_short_position(),
        .rsp_pending_open_long(acct_rsp_pending_long),.rsp_pending_open_short(),
        .rsp_reserved_close_long(),.rsp_reserved_close_short(),
        .rsp_required_margin_before(),.rsp_required_margin_after()
    );

    reg dbg_store_mode, dbg_store_valid;
    wire dbg_store_ready;
    reg [31:0] dbg_store_order_id;
    wire store_req_valid = dbg_store_mode ? dbg_store_valid : g_store_req_valid;
    wire [1:0] store_req_op = dbg_store_mode ? 2'd0 : g_store_req_op;
    wire [31:0] store_req_order_id = dbg_store_mode ? dbg_store_order_id : g_store_req_order_id;
    wire store_rsp_ready = dbg_store_mode ? 1'b1 : g_store_rsp_ready;
    wire store_req_ready_i, store_rsp_valid_i, store_rsp_ok_i, store_rsp_found_i;
    wire [2:0] store_rsp_status_i;
    wire [QTY_W-1:0] store_rsp_remaining_qty_i;
    assign g_store_req_ready = dbg_store_mode ? 1'b0 : store_req_ready_i;
    assign g_store_rsp_valid = dbg_store_mode ? 1'b0 : store_rsp_valid_i;
    assign g_store_rsp_ok = store_rsp_ok_i;
    assign g_store_rsp_found = store_rsp_found_i;
    assign g_store_rsp_status = store_rsp_status_i;
    assign dbg_store_ready = dbg_store_mode ? store_req_ready_i : 1'b0;

    hft_rmic_futures_order_store_v1 #(.TABLE_SIZE(3),.QTY_W(QTY_W)) u_store (
        .clk(clk),.rst_n(rst_n),.req_valid(store_req_valid),.req_ready(store_req_ready_i),
        .req_op(store_req_op),.req_order_id(store_req_order_id),
        .req_account_id(dbg_store_mode ? 8'd0 : g_store_req_account_id),
        .req_product_id(dbg_store_mode ? 8'd0 : g_store_req_product_id),
        .req_side(dbg_store_mode ? 1'b0 : g_store_req_side),
        .req_position_effect(dbg_store_mode ? 8'd0 : g_store_req_position_effect),
        .req_order_type(dbg_store_mode ? 8'd0 : g_store_req_order_type),
        .req_tif(dbg_store_mode ? 8'd0 : g_store_req_tif),
        .req_limit_price(dbg_store_mode ? 32'd0 : g_store_req_limit_price),
        .req_remaining_qty(dbg_store_mode ? {QTY_W{1'b0}} : g_store_req_remaining_qty),
        .rsp_valid(store_rsp_valid_i),.rsp_ready(store_rsp_ready),.rsp_ok(store_rsp_ok_i),
        .rsp_found(store_rsp_found_i),.rsp_status(store_rsp_status_i),.rsp_account_id(),.rsp_product_id(),
        .rsp_side(),.rsp_position_effect(),.rsp_order_type(),.rsp_tif(),.rsp_limit_price(),
        .rsp_remaining_qty(store_rsp_remaining_qty_i),.rsp_bank(),.rsp_in_stash(),.init_done()
    );

    task fail(input [8*120-1:0] msg); begin $display("TEST_FAIL %0s",msg); $fatal(1); end endtask

    task configure_state;
        begin
            @(negedge clk); cfg_valid=1;
            while (!cfg_ready) @(posedge clk);
            @(posedge clk);
            @(negedge clk); cfg_valid=0;
            if (!cfg_done || !cfg_ok) fail("state configuration failed");
        end
    endtask

    task send_order;
        input [31:0] oid;
        input [QTY_W-1:0] oqty;
        input ppass;
        input [7:0] preason;
        input [ORDER_W-1:0] payload;
        input hold_rsp;
        begin
            @(negedge clk);
            order_id=oid; qty=oqty; order_data=payload;
            policy_pass=ppass; policy_reason_source=`HFT_RMIC_REASON_SRC_POLICY; policy_reason_code=preason;
            order_valid=1;
            while (!order_ready) @(posedge clk);
            @(posedge clk);
            @(negedge clk); order_valid=0;
            while (!result_valid) @(posedge clk);
            #1;
            if (result_order_id!==oid || result_order_data!==payload) fail("result identity mismatch");
            if (hold_rsp) begin
                repeat(3) begin
                    @(posedge clk); #1;
                    if (!result_valid || result_order_id!==oid || result_order_data!==payload)
                        fail("result backpressure stability failed");
                end
            end
        end
    endtask

    task consume_result;
        begin
            @(negedge clk); result_ready=1;
            @(posedge clk);
            @(negedge clk); result_ready=0;
        end
    endtask

    task query_pending(input [QTY_W-1:0] exp);
        begin
            dbg_acct_mode=1; dbg_acct_kind=`HFT_RMIC_ACCT_EVENT_QUERY;
            @(negedge clk); dbg_acct_valid=1;
            while (!dbg_acct_ready) @(posedge clk);
            @(posedge clk);
            @(negedge clk); dbg_acct_valid=0;
            while (!acct_rsp_valid_i) @(posedge clk);
            #1;
            if (!acct_rsp_ok_i || acct_rsp_pending_long!==exp) fail("pending-long query mismatch");
            @(posedge clk); #1;
            dbg_acct_mode=0;
        end
    endtask

    task lookup_context(input [31:0] oid, input exp_found, input [QTY_W-1:0] exp_qty);
        begin
            dbg_store_mode=1; dbg_store_order_id=oid;
            @(negedge clk); dbg_store_valid=1;
            while (!dbg_store_ready) @(posedge clk);
            @(posedge clk);
            @(negedge clk); dbg_store_valid=0;
            while (!store_rsp_valid_i) @(posedge clk);
            #1;
            if (store_rsp_found_i!==exp_found) fail("context lookup found mismatch");
            if (exp_found && (!store_rsp_ok_i || store_rsp_remaining_qty_i!==exp_qty)) fail("context lookup qty mismatch");
            @(posedge clk); #1;
            dbg_store_mode=0;
        end
    endtask

    initial begin
        order_valid=0; order_data=0; policy_pass=0; policy_reason_source=`HFT_RMIC_REASON_SRC_POLICY;
        policy_reason_code=`HFT_RMIC_POLICY_REASON_PASS; order_id=0; account_id=1; product_id=1;
        side=`HFT_RMIC_RMIC_SIDE_BUY; position_effect=`HFT_RMIC_TAIFEX_POS_OPEN;
        order_type=`HFT_RMIC_TAIFEX_ORD_LIMIT; tif=`HFT_RMIC_TAIFEX_TIF_ROD; limit_price=32'd100;
        qty=0; result_ready=0; cfg_valid=0; dbg_acct_mode=0; dbg_acct_valid=0;
        dbg_acct_kind=`HFT_RMIC_ACCT_EVENT_QUERY; dbg_store_mode=0; dbg_store_valid=0; dbg_store_order_id=0;

        repeat(4) @(posedge clk); @(negedge clk); rst_n=1;
        configure_state();
        repeat(2) @(posedge clk);

        // Policy reject: no state or context mutation.
        send_order(32'd100,16'd5,1'b0,`HFT_RMIC_POLICY_REASON_KILL_SWITCH,256'h100,1'b0);
        if (result_accepted || result_reason_code!=`HFT_RMIC_POLICY_REASON_KILL_SWITCH) fail("policy reject response");
        consume_result(); query_pending(0); lookup_context(100,0,0);
        $display("I3_POLICY_NO_MUTATION_PASS");

        // First accepted order.
        send_order(32'd1,16'd2,1'b1,0,256'h1111,1'b0);
        if (!result_accepted) fail("first admission should pass");
        consume_result(); query_pending(2); lookup_context(1,1,2);
        $display("I3_ACCEPT_ATOMIC_PASS");

        // Duplicate ID reserves first, then INSERT fails and must roll back.
        send_order(32'd1,16'd3,1'b1,0,256'h2222,1'b0);
        if (result_accepted || result_reason_source!=`HFT_RMIC_REASON_SRC_SYSTEM ||
            result_reason_code!=`HFT_RMIC_SYSTEM_REASON_ORDER_CONTEXT_EXISTS) fail("duplicate reason");
        consume_result(); query_pending(2); lookup_context(1,1,2);
        $display("I3_DUPLICATE_ROLLBACK_PASS");

        // Accepted result must remain stable while downstream is stalled.
        send_order(32'd2,16'd1,1'b1,0,256'habcdef,1'b1);
        if (!result_accepted) fail("backpressured admission should pass");
        consume_result(); query_pending(3); lookup_context(2,1,1);
        $display("I3_RESULT_BACKPRESSURE_PASS");

        send_order(32'd3,16'd1,1'b1,0,256'h3333,1'b0);
        if (!result_accepted) fail("third admission should pass");
        consume_result(); query_pending(4); lookup_context(3,1,1);

        // Table full: reservation must be released before reject.
        send_order(32'd4,16'd4,1'b1,0,256'h4444,1'b0);
        if (result_accepted || result_reason_code!=`HFT_RMIC_SYSTEM_REASON_ORDER_CONTEXT_FULL) fail("full reason");
        consume_result(); query_pending(4); lookup_context(4,0,0);
        $display("I3_FULL_ROLLBACK_PASS");

        // Accounting rejection occurs before store insert.
        send_order(32'd5,16'd120,1'b1,0,256'h5555,1'b0);
        if (result_accepted || result_reason_code!=`HFT_RMIC_POLICY_REASON_MARGIN_LIMIT) fail("margin reject reason");
        consume_result(); query_pending(4); lookup_context(5,0,0);
        $display("I3_ACCOUNTING_NO_STORE_PASS");

        $display("HFT_RMIC_CL2EX_ADMISSION_V1_TB_PASS");
        $finish;
    end
endmodule
