`timescale 1ns/1ps
`include "hft_rmic_contract.svh"
`include "hft_rmic_accounting_defs.svh"
`include "hft_rmic_policy_defs.svh"
`include "taifex_tmp_v2187_defs.svh"

module tb_hft_rmic_order_gate_v1;
    localparam QTY_W=16;
    reg clk=0; always #5 clk=~clk;
    reg rst_n=0;

    reg integration_ready, accounting_ready, global_kill;
    reg [255:0] order_type_allow_mask, tif_allow_mask, position_effect_allow_mask;
    reg account_cfg_we, account_cfg_valid;
    reg [1:0] account_cfg_index;
    reg [31:0] account_cfg_key;
    reg [7:0] account_cfg_value;
    reg product_cfg_we, product_cfg_valid;
    reg [1:0] product_cfg_index;
    reg [15:0] product_cfg_key;
    reg [7:0] product_cfg_value;

    reg order_valid;
    wire order_ready;
    reg [255:0] order_data;
    wire result_valid;
    reg result_ready;
    wire result_accepted;
    wire [1:0] result_reason_source;
    wire [7:0] result_reason_code;
    wire [31:0] result_order_id;
    wire [255:0] result_order_data;

    wire g_acct_req_valid, g_acct_req_ready;
    wire [7:0] g_acct_req_account_id,g_acct_req_product_id;
    wire [2:0] g_acct_req_event_kind;
    wire g_acct_req_side;
    wire [7:0] g_acct_req_position_effect;
    wire [QTY_W-1:0] g_acct_req_order_qty,g_acct_req_fill_qty,g_acct_req_release_qty;
    wire g_acct_rsp_valid,g_acct_rsp_ready,g_acct_rsp_ok;
    wire [1:0] g_acct_rsp_reason_source;
    wire [7:0] g_acct_rsp_reason_code;

    wire g_store_req_valid,g_store_req_ready;
    wire [1:0] g_store_req_op;
    wire [31:0] g_store_req_order_id;
    wire [7:0] g_store_req_account_id,g_store_req_product_id;
    wire g_store_req_side;
    wire [7:0] g_store_req_position_effect,g_store_req_order_type,g_store_req_tif;
    wire [31:0] g_store_req_limit_price;
    wire [QTY_W-1:0] g_store_req_remaining_qty;
    wire g_store_rsp_valid,g_store_rsp_ready,g_store_rsp_ok,g_store_rsp_found;
    wire [2:0] g_store_rsp_status;

    hft_rmic_order_gate_v1 #(.ACCOUNT_MAP_ENTRIES(4),.PRODUCT_MAP_ENTRIES(4),.QTY_W(QTY_W)) dut (
        .clk(clk),.rst_n(rst_n),.integration_ready(integration_ready),.accounting_ready(accounting_ready),
        .global_kill(global_kill),.order_type_allow_mask(order_type_allow_mask),.tif_allow_mask(tif_allow_mask),
        .position_effect_allow_mask(position_effect_allow_mask),
        .account_cfg_we(account_cfg_we),.account_cfg_index(account_cfg_index),.account_cfg_valid(account_cfg_valid),
        .account_cfg_key(account_cfg_key),.account_cfg_value(account_cfg_value),
        .product_cfg_we(product_cfg_we),.product_cfg_index(product_cfg_index),.product_cfg_valid(product_cfg_valid),
        .product_cfg_key(product_cfg_key),.product_cfg_value(product_cfg_value),
        .order_valid(order_valid),.order_ready(order_ready),.order_data(order_data),
        .result_valid(result_valid),.result_ready(result_ready),.result_accepted(result_accepted),
        .result_reason_source(result_reason_source),.result_reason_code(result_reason_code),
        .result_order_id(result_order_id),.result_order_data(result_order_data),
        .acct_req_valid(g_acct_req_valid),.acct_req_ready(g_acct_req_ready),
        .acct_req_account_id(g_acct_req_account_id),.acct_req_product_id(g_acct_req_product_id),
        .acct_req_event_kind(g_acct_req_event_kind),.acct_req_side(g_acct_req_side),
        .acct_req_position_effect(g_acct_req_position_effect),.acct_req_order_qty(g_acct_req_order_qty),
        .acct_req_fill_qty(g_acct_req_fill_qty),.acct_req_release_qty(g_acct_req_release_qty),
        .acct_rsp_valid(g_acct_rsp_valid),.acct_rsp_ready(g_acct_rsp_ready),.acct_rsp_ok(g_acct_rsp_ok),
        .acct_rsp_reason_source(g_acct_rsp_reason_source),.acct_rsp_reason_code(g_acct_rsp_reason_code),
        .store_req_valid(g_store_req_valid),.store_req_ready(g_store_req_ready),.store_req_op(g_store_req_op),
        .store_req_order_id(g_store_req_order_id),.store_req_account_id(g_store_req_account_id),
        .store_req_product_id(g_store_req_product_id),.store_req_side(g_store_req_side),
        .store_req_position_effect(g_store_req_position_effect),.store_req_order_type(g_store_req_order_type),
        .store_req_tif(g_store_req_tif),.store_req_limit_price(g_store_req_limit_price),
        .store_req_remaining_qty(g_store_req_remaining_qty),.store_rsp_valid(g_store_rsp_valid),
        .store_rsp_ready(g_store_rsp_ready),.store_rsp_ok(g_store_rsp_ok),.store_rsp_found(g_store_rsp_found),
        .store_rsp_status(g_store_rsp_status)
    );

    reg state_cfg_valid;
    wire state_cfg_ready,state_cfg_done,state_cfg_ok;
    wire [7:0] state_cfg_reason;
    hft_rmic_futures_state_manager_v1 #(.NUM_ACCOUNTS(4),.NUM_PRODUCTS(4),.QTY_W(QTY_W),.MARGIN_W(64)) u_state (
        .clk(clk),.rst_n(rst_n),.cfg_valid(state_cfg_valid),.cfg_ready(state_cfg_ready),
        .cfg_account_id(8'd1),.cfg_product_id(8'd2),.cfg_enabled(1'b1),
        .cfg_margin_budget(64'd100000),.cfg_margin_per_contract(64'd1000),
        .cfg_long_position(0),.cfg_short_position(0),.cfg_pending_open_long(0),.cfg_pending_open_short(0),
        .cfg_reserved_close_long(0),.cfg_reserved_close_short(0),.cfg_done(state_cfg_done),.cfg_ok(state_cfg_ok),
        .cfg_reason_code(state_cfg_reason),.req_valid(g_acct_req_valid),.req_ready(g_acct_req_ready),
        .req_account_id(g_acct_req_account_id),.req_product_id(g_acct_req_product_id),
        .req_event_kind(g_acct_req_event_kind),.req_side(g_acct_req_side),
        .req_position_effect(g_acct_req_position_effect),.req_order_qty(g_acct_req_order_qty),
        .req_fill_qty(g_acct_req_fill_qty),.req_release_qty(g_acct_req_release_qty),
        .rsp_valid(g_acct_rsp_valid),.rsp_ready(g_acct_rsp_ready),.rsp_ok(g_acct_rsp_ok),
        .rsp_reason_source(g_acct_rsp_reason_source),.rsp_reason_code(g_acct_rsp_reason_code),
        .rsp_account_id(),.rsp_product_id(),.rsp_entry_enabled(),.rsp_long_position(),.rsp_short_position(),
        .rsp_pending_open_long(),.rsp_pending_open_short(),.rsp_reserved_close_long(),.rsp_reserved_close_short(),
        .rsp_required_margin_before(),.rsp_required_margin_after()
    );

    // Store debug mux to inspect normalized context written by the gate.
    reg dbg_store_mode,dbg_store_valid;
    reg [31:0] dbg_store_order_id;
    wire store_req_valid = dbg_store_mode ? dbg_store_valid : g_store_req_valid;
    wire [1:0] store_req_op = dbg_store_mode ? 2'd0 : g_store_req_op;
    wire [31:0] store_req_order_id = dbg_store_mode ? dbg_store_order_id : g_store_req_order_id;
    wire store_rsp_ready = dbg_store_mode ? 1'b1 : g_store_rsp_ready;
    wire store_req_ready_i,store_rsp_valid_i,store_rsp_ok_i,store_rsp_found_i;
    wire [2:0] store_rsp_status_i;
    wire [7:0] store_rsp_account_id_i,store_rsp_product_id_i;
    wire store_rsp_side_i;
    wire [7:0] store_rsp_position_effect_i,store_rsp_order_type_i,store_rsp_tif_i;
    wire [QTY_W-1:0] store_rsp_remaining_qty_i;
    assign g_store_req_ready = dbg_store_mode ? 1'b0 : store_req_ready_i;
    assign g_store_rsp_valid = dbg_store_mode ? 1'b0 : store_rsp_valid_i;
    assign g_store_rsp_ok=store_rsp_ok_i; assign g_store_rsp_found=store_rsp_found_i; assign g_store_rsp_status=store_rsp_status_i;

    hft_rmic_futures_order_store_v1 #(.TABLE_SIZE(16),.QTY_W(QTY_W)) u_store (
        .clk(clk),.rst_n(rst_n),.req_valid(store_req_valid),.req_ready(store_req_ready_i),
        .req_op(store_req_op),.req_order_id(store_req_order_id),
        .req_account_id(dbg_store_mode?0:g_store_req_account_id),.req_product_id(dbg_store_mode?0:g_store_req_product_id),
        .req_side(dbg_store_mode?0:g_store_req_side),.req_position_effect(dbg_store_mode?0:g_store_req_position_effect),
        .req_order_type(dbg_store_mode?0:g_store_req_order_type),.req_tif(dbg_store_mode?0:g_store_req_tif),
        .req_limit_price(dbg_store_mode?0:g_store_req_limit_price),.req_remaining_qty(dbg_store_mode?0:g_store_req_remaining_qty),
        .rsp_valid(store_rsp_valid_i),.rsp_ready(store_rsp_ready),.rsp_ok(store_rsp_ok_i),.rsp_found(store_rsp_found_i),
        .rsp_status(store_rsp_status_i),.rsp_account_id(store_rsp_account_id_i),.rsp_product_id(store_rsp_product_id_i),
        .rsp_side(store_rsp_side_i),.rsp_position_effect(store_rsp_position_effect_i),
        .rsp_order_type(store_rsp_order_type_i),.rsp_tif(store_rsp_tif_i),.rsp_limit_price(),
        .rsp_remaining_qty(store_rsp_remaining_qty_i),.rsp_bank(),.rsp_in_stash(),.init_done()
    );

    function automatic [255:0] make_order;
        input [31:0] price;
        input [15:0] q;
        input [7:0] s;
        input [7:0] ftif;
        input [7:0] pe;
        input [31:0] investor;
        input [31:0] oid;
        input [15:0] symbol;
        input [7:0] otype;
        reg [255:0] x;
        begin
            x=0;
            x[`HFT_RMIC_PRICE_LSB +:32]=price;
            x[`HFT_RMIC_QTY_LSB +:16]=q;
            x[`HFT_RMIC_SIDE_LSB +:8]=s;
            x[`HFT_RMIC_TIF_LSB +:8]=ftif;
            x[`HFT_RMIC_POS_EFFECT_LSB +:8]=pe;
            x[`HFT_RMIC_INV_ACNO_LSB +:32]=investor;
            x[`HFT_RMIC_ORDER_ID_LSB +:32]=oid;
            x[`HFT_RMIC_SYMBOL_SLOT_LSB +:16]=symbol;
            x[`HFT_RMIC_ORD_TYPE_LSB +:8]=otype;
            make_order=x;
        end
    endfunction

    task fail(input [8*120-1:0] msg); begin $display("TEST_FAIL %0s",msg); $fatal(1); end endtask

    task map_account(input [1:0] idx,input [31:0] key,input [7:0] val);
        begin @(negedge clk); account_cfg_index=idx;account_cfg_key=key;account_cfg_value=val;account_cfg_valid=1;account_cfg_we=1;
        @(posedge clk); @(negedge clk); account_cfg_we=0; end
    endtask
    task map_product(input [1:0] idx,input [15:0] key,input [7:0] val);
        begin @(negedge clk); product_cfg_index=idx;product_cfg_key=key;product_cfg_value=val;product_cfg_valid=1;product_cfg_we=1;
        @(posedge clk); @(negedge clk); product_cfg_we=0; end
    endtask
    task configure_state;
        begin @(negedge clk);state_cfg_valid=1; while(!state_cfg_ready)@(posedge clk); @(posedge clk); @(negedge clk);state_cfg_valid=0;
        if(!state_cfg_done||!state_cfg_ok)fail("state config failed"); end
    endtask

    task send(input [255:0] x);
        begin @(negedge clk);order_data=x;order_valid=1;while(!order_ready)@(posedge clk);@(posedge clk);@(negedge clk);order_valid=0;
        while(!result_valid)@(posedge clk);#1;if(result_order_data!==x)fail("payload not byte-identical"); end
    endtask
    task consume; begin @(negedge clk);result_ready=1;@(posedge clk);@(negedge clk);result_ready=0; end endtask

    task lookup_expect(input [31:0] oid,input exp_found,input [7:0] acc,input [7:0] prod,input exp_side,input [7:0] pe,input [15:0] q);
        begin dbg_store_mode=1;dbg_store_order_id=oid;@(negedge clk);dbg_store_valid=1;while(!store_req_ready_i)@(posedge clk);@(posedge clk);@(negedge clk);dbg_store_valid=0;
        while(!store_rsp_valid_i)@(posedge clk);#1;
        if(store_rsp_found_i!==exp_found)fail("store found mismatch");
        if(exp_found && (!store_rsp_ok_i||store_rsp_account_id_i!==acc||store_rsp_product_id_i!==prod||store_rsp_side_i!==exp_side||store_rsp_position_effect_i!==pe||store_rsp_remaining_qty_i!==q))fail("stored normalized context mismatch");
        @(posedge clk);#1;dbg_store_mode=0; end
    endtask

    initial begin
        integration_ready=0;accounting_ready=0;global_kill=0;
        order_type_allow_mask=0;tif_allow_mask=0;position_effect_allow_mask=0;
        account_cfg_we=0;account_cfg_index=0;account_cfg_valid=0;account_cfg_key=0;account_cfg_value=0;
        product_cfg_we=0;product_cfg_index=0;product_cfg_valid=0;product_cfg_key=0;product_cfg_value=0;
        order_valid=0;order_data=0;result_ready=0;state_cfg_valid=0;dbg_store_mode=0;dbg_store_valid=0;dbg_store_order_id=0;
        order_type_allow_mask[`HFT_RMIC_TAIFEX_ORD_LIMIT]=1'b1;
        tif_allow_mask[`HFT_RMIC_TAIFEX_TIF_ROD]=1'b1;
        position_effect_allow_mask[`HFT_RMIC_TAIFEX_POS_OPEN]=1'b1;
        position_effect_allow_mask[`HFT_RMIC_TAIFEX_POS_CLOSE]=1'b1;

        repeat(4)@(posedge clk);@(negedge clk);rst_n=1;
        map_account(0,32'h12345678,8'd1);map_product(0,16'd2,8'd2);configure_state();
        integration_ready=1;accounting_ready=1;repeat(2)@(posedge clk);

        // Gate must not accept an order in the same cycle maps are being written.
        @(negedge clk);account_cfg_we=1;order_valid=1;order_data=make_order(100,1,8'h01,0,8'h4f,32'h12345678,9,2,2);#1;
        if(order_ready)fail("order_ready must be low during map config");
        account_cfg_we=0;order_valid=0;

        send(make_order(32'd100,16'd2,`HFT_RMIC_TMP_SIDE_BUY,`HFT_RMIC_TAIFEX_TIF_ROD,`HFT_RMIC_TAIFEX_POS_OPEN,32'h12345678,32'd10,16'd2,`HFT_RMIC_TAIFEX_ORD_LIMIT));
        if(!result_accepted||result_order_id!=10)fail("mapped BUY OPEN should pass");consume();
        lookup_expect(10,1,1,2,`HFT_RMIC_RMIC_SIDE_BUY,`HFT_RMIC_TAIFEX_POS_OPEN,2);
        $display("I3_GATE_MAPPING_PAYLOAD_PASS");

        send(make_order(100,1,`HFT_RMIC_TMP_SIDE_SELL,0,`HFT_RMIC_TAIFEX_POS_OPEN,32'h12345678,11,2,`HFT_RMIC_TAIFEX_ORD_LIMIT));
        if(!result_accepted)fail("mapped SELL OPEN should pass");consume();
        lookup_expect(11,1,1,2,`HFT_RMIC_RMIC_SIDE_SELL,`HFT_RMIC_TAIFEX_POS_OPEN,1);
        $display("I3_GATE_SIDE_TRANSLATION_PASS");

        send(make_order(100,1,`HFT_RMIC_TMP_SIDE_BUY,0,`HFT_RMIC_TAIFEX_POS_OPEN,32'hdeadbeef,12,2,`HFT_RMIC_TAIFEX_ORD_LIMIT));
        if(result_accepted||result_reason_source!=`HFT_RMIC_REASON_SRC_ADAPTER||result_reason_code!=`HFT_RMIC_ADAPTER_REASON_ACCOUNT_UNMAPPED)fail("account miss reason");consume();lookup_expect(12,0,0,0,0,0,0);
        $display("I3_GATE_MAP_MISS_PASS");

        send(make_order(100,1,8'h03,0,`HFT_RMIC_TAIFEX_POS_OPEN,32'h12345678,13,2,`HFT_RMIC_TAIFEX_ORD_LIMIT));
        if(result_accepted||result_reason_code!=`HFT_RMIC_ADAPTER_REASON_SIDE_INVALID)fail("invalid side reason");consume();lookup_expect(13,0,0,0,0,0,0);

        global_kill=1;
        send(make_order(100,1,`HFT_RMIC_TMP_SIDE_BUY,0,`HFT_RMIC_TAIFEX_POS_OPEN,32'h12345678,14,2,`HFT_RMIC_TAIFEX_ORD_LIMIT));
        if(result_accepted||result_reason_code!=`HFT_RMIC_POLICY_REASON_KILL_SWITCH)fail("kill reason");consume();lookup_expect(14,0,0,0,0,0,0);global_kill=0;
        $display("I3_GATE_POLICY_REJECT_PASS");

        // Deliberately create duplicate account mapping; must fail ambiguous.
        map_account(1,32'h12345678,8'd3);
        send(make_order(100,1,`HFT_RMIC_TMP_SIDE_BUY,0,`HFT_RMIC_TAIFEX_POS_OPEN,32'h12345678,15,2,`HFT_RMIC_TAIFEX_ORD_LIMIT));
        if(result_accepted||result_reason_code!=`HFT_RMIC_ADAPTER_REASON_ACCOUNT_AMBIGUOUS)fail("ambiguous mapping reason");consume();lookup_expect(15,0,0,0,0,0,0);
        $display("I3_GATE_AMBIGUOUS_FAIL_CLOSED_PASS");

        $display("HFT_RMIC_ORDER_GATE_V1_TB_PASS");$finish;
    end
endmodule
