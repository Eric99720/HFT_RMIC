`timescale 1ns/1ps
`include "hft_rmic_contract.svh"
`include "taifex_tmp_v2187_defs.svh"

module tb_hft_rmic_futures_order_store_v1;
    localparam [1:0] OP_LOOKUP = 2'd0;
    localparam [1:0] OP_INSERT = 2'd1;
    localparam [1:0] OP_DELETE = 2'd2;
    localparam [1:0] OP_UPDATE = 2'd3;
    localparam [2:0] ST_OK = 3'd0;
    localparam [2:0] ST_NOT_FOUND = 3'd1;
    localparam [2:0] ST_EXISTS = 3'd2;

    reg clk=0;
    always #5 clk=~clk;
    reg rst_n=0;

    reg req_valid;
    wire req_ready;
    reg [1:0] req_op;
    reg [31:0] req_order_id;
    reg [7:0] req_account_id, req_product_id;
    reg req_side;
    reg [7:0] req_position_effect, req_order_type, req_tif;
    reg [31:0] req_limit_price;
    reg [15:0] req_remaining_qty;

    wire rsp_valid;
    reg rsp_ready;
    wire rsp_ok, rsp_found;
    wire [2:0] rsp_status;
    wire [7:0] rsp_account_id, rsp_product_id;
    wire rsp_side;
    wire [7:0] rsp_position_effect, rsp_order_type, rsp_tif;
    wire [31:0] rsp_limit_price;
    wire [15:0] rsp_remaining_qty;
    wire [2:0] rsp_bank;
    wire rsp_in_stash, init_done;

    hft_rmic_futures_order_store_v1 #(
        .TABLE_SIZE(64), .BANKS(8), .STASH_SIZE(4),
        .ORDER_ID_W(32), .ACCOUNT_ID_W(8), .PRODUCT_ID_W(8),
        .PRICE_W(32), .QTY_W(16), .AMU_VALUE_W(96)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .req_valid(req_valid), .req_ready(req_ready), .req_op(req_op),
        .req_order_id(req_order_id), .req_account_id(req_account_id),
        .req_product_id(req_product_id), .req_side(req_side),
        .req_position_effect(req_position_effect), .req_order_type(req_order_type),
        .req_tif(req_tif), .req_limit_price(req_limit_price),
        .req_remaining_qty(req_remaining_qty),
        .rsp_valid(rsp_valid), .rsp_ready(rsp_ready), .rsp_ok(rsp_ok),
        .rsp_found(rsp_found), .rsp_status(rsp_status),
        .rsp_account_id(rsp_account_id), .rsp_product_id(rsp_product_id),
        .rsp_side(rsp_side), .rsp_position_effect(rsp_position_effect),
        .rsp_order_type(rsp_order_type), .rsp_tif(rsp_tif),
        .rsp_limit_price(rsp_limit_price), .rsp_remaining_qty(rsp_remaining_qty),
        .rsp_bank(rsp_bank), .rsp_in_stash(rsp_in_stash), .init_done(init_done)
    );

    task fail;
        input [8*120-1:0] msg;
        begin $display("TEST_FAIL %0s",msg); $fatal(1); end
    endtask

    task send_req;
        input [1:0] op;
        input [31:0] oid;
        input [7:0] acc;
        input [7:0] prod;
        input side;
        input [7:0] pe;
        input [7:0] ordtype;
        input [7:0] tif;
        input [31:0] px;
        input [15:0] qty;
        reg accepted;
        begin
            @(negedge clk);
            req_op=op; req_order_id=oid; req_account_id=acc; req_product_id=prod;
            req_side=side; req_position_effect=pe; req_order_type=ordtype;
            req_tif=tif; req_limit_price=px; req_remaining_qty=qty;
            req_valid=1;
            accepted=0;
            while(!accepted) begin
                @(posedge clk);
                if(req_ready) accepted=1;
            end
            @(negedge clk); req_valid=0;
            while(!rsp_valid) @(posedge clk);
            #1;
        end
    endtask

    task ack_rsp;
        begin
            @(negedge clk); rsp_ready=1;
            @(posedge clk);
            @(negedge clk); rsp_ready=0;
        end
    endtask

    task expect_insert_ok;
        begin
            // Frozen AMU new-key INSERT: ok=1/status=OK/found=0.  Payload is
            // not returned by the INSERT response; verify it with LOOKUP.
            if(!rsp_ok || rsp_status!==ST_OK || rsp_found)
                fail("new insert response contract mismatch");
            ack_rsp();
        end
    endtask

    task expect_found;
        input exp_ok;
        input [2:0] exp_status;
        input [7:0] acc;
        input [7:0] prod;
        input side;
        input [7:0] pe;
        input [7:0] ordtype;
        input [7:0] tif;
        input [31:0] px;
        input [15:0] qty;
        begin
            if(rsp_ok!==exp_ok) fail("rsp_ok mismatch");
            if(rsp_status!==exp_status) fail("rsp_status mismatch");
            if(exp_status==ST_OK) begin
                if(!rsp_found) fail("expected found");
                if(rsp_account_id!==acc || rsp_product_id!==prod) fail("account/product payload mismatch");
                if(rsp_side!==side) fail("side payload mismatch");
                if(rsp_position_effect!==pe) fail("PositionEffect payload mismatch");
                if(rsp_order_type!==ordtype || rsp_tif!==tif) fail("OrdType/TIF payload mismatch");
                if(rsp_limit_price!==px || rsp_remaining_qty!==qty) fail("price/qty payload mismatch");
            end
            ack_rsp();
        end
    endtask

    initial begin
        req_valid=0; req_op=0; req_order_id=0; req_account_id=0; req_product_id=0;
        req_side=0; req_position_effect=0; req_order_type=0; req_tif=0;
        req_limit_price=0; req_remaining_qty=0; rsp_ready=0;
        repeat(3) @(posedge clk);
        @(negedge clk); rst_n=1;
        while(!init_done) @(posedge clk);

        // IDs 5 and 69 are a historical direct-map collision pair. The CI stub
        // verifies the wrapper contract; actual collision behavior remains the
        // frozen AMU's responsibility and is exercised by local pinned-AMU runs.
        send_req(OP_INSERT,32'd5,8'd1,8'd2,`HFT_RMIC_RMIC_SIDE_BUY,
                 `HFT_RMIC_TAIFEX_POS_OPEN,`HFT_RMIC_TAIFEX_ORD_LIMIT,
                 `HFT_RMIC_TAIFEX_TIF_ROD,32'd20000,16'd10);
        expect_insert_ok();

        send_req(OP_INSERT,32'd69,8'd3,8'd1,`HFT_RMIC_RMIC_SIDE_SELL,
                 `HFT_RMIC_TAIFEX_POS_CLOSE,`HFT_RMIC_TAIFEX_ORD_LIMIT,
                 `HFT_RMIC_TAIFEX_TIF_IOC,32'd19950,16'd4);
        expect_insert_ok();

        send_req(OP_LOOKUP,32'd5,0,0,0,0,0,0,0,0);
        expect_found(1,ST_OK,1,2,`HFT_RMIC_RMIC_SIDE_BUY,
                     `HFT_RMIC_TAIFEX_POS_OPEN,`HFT_RMIC_TAIFEX_ORD_LIMIT,
                     `HFT_RMIC_TAIFEX_TIF_ROD,20000,10);
        send_req(OP_LOOKUP,32'd69,0,0,0,0,0,0,0,0);
        expect_found(1,ST_OK,3,1,`HFT_RMIC_RMIC_SIDE_SELL,
                     `HFT_RMIC_TAIFEX_POS_CLOSE,`HFT_RMIC_TAIFEX_ORD_LIMIT,
                     `HFT_RMIC_TAIFEX_TIF_IOC,19950,4);
        $display("HFT_RMIC_FUTURES_ORDER_CONTEXT_PACKING_PASS");

        // UPDATE success returns the previous matched value in the frozen AMU;
        // the new payload is verified by the following LOOKUP instead.
        send_req(OP_UPDATE,32'd5,8'd1,8'd2,`HFT_RMIC_RMIC_SIDE_BUY,
                 `HFT_RMIC_TAIFEX_POS_OPEN,`HFT_RMIC_TAIFEX_ORD_LIMIT,
                 `HFT_RMIC_TAIFEX_TIF_ROD,32'd20000,16'd7);
        if(!rsp_ok || rsp_status!==ST_OK || !rsp_found) fail("update response contract mismatch");
        ack_rsp();
        send_req(OP_LOOKUP,32'd5,0,0,0,0,0,0,0,0);
        expect_found(1,ST_OK,1,2,`HFT_RMIC_RMIC_SIDE_BUY,
                     `HFT_RMIC_TAIFEX_POS_OPEN,`HFT_RMIC_TAIFEX_ORD_LIMIT,
                     `HFT_RMIC_TAIFEX_TIF_ROD,20000,7);
        $display("HFT_RMIC_FUTURES_ORDER_CONTEXT_UPDATE_PASS");

        send_req(OP_INSERT,32'd5,8'd7,8'd7,1,`HFT_RMIC_TAIFEX_POS_CLOSE,
                 `HFT_RMIC_TAIFEX_ORD_MARKET,`HFT_RMIC_TAIFEX_TIF_FOK,1,1);
        if(rsp_ok || rsp_status!==ST_EXISTS || !rsp_found) fail("duplicate insert contract mismatch");
        ack_rsp();
        send_req(OP_LOOKUP,32'd5,0,0,0,0,0,0,0,0);
        expect_found(1,ST_OK,1,2,`HFT_RMIC_RMIC_SIDE_BUY,
                     `HFT_RMIC_TAIFEX_POS_OPEN,`HFT_RMIC_TAIFEX_ORD_LIMIT,
                     `HFT_RMIC_TAIFEX_TIF_ROD,20000,7);
        $display("HFT_RMIC_FUTURES_ORDER_CONTEXT_DUPLICATE_PASS");

        send_req(OP_DELETE,32'd69,0,0,0,0,0,0,0,0);
        if(!rsp_ok || rsp_status!==ST_OK || !rsp_found) fail("delete failed");
        ack_rsp();
        send_req(OP_LOOKUP,32'd69,0,0,0,0,0,0,0,0);
        if(rsp_ok || rsp_found || rsp_status!==ST_NOT_FOUND) fail("deleted key still found");
        ack_rsp();
        $display("HFT_RMIC_FUTURES_ORDER_CONTEXT_DELETE_PASS");

        $display("HFT_RMIC_FUTURES_ORDER_STORE_TB_PASS");
        $finish;
    end

    initial begin #100000; fail("timeout"); end
endmodule
