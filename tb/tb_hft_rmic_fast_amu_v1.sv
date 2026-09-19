`timescale 1ns/1ps
module tb_hft_rmic_fast_amu_v1;
    localparam [1:0] OP_LOOKUP=2'd0, OP_INSERT=2'd1, OP_DELETE=2'd2, OP_UPDATE=2'd3;
    localparam [2:0] ST_OK=3'd0, ST_EXISTS=3'd2;
    reg clk=0; always #5 clk=~clk;
    integer cycle=0; always @(posedge clk) cycle <= cycle+1;
    reg rst_n=0;
    reg req_valid=0; wire req_ready;
    reg [1:0] req_op=0; reg [31:0] req_key=0, req_value=0;
    wire rsp_valid; reg rsp_ready=1; wire rsp_ok,rsp_found; wire [2:0] rsp_status; wire [31:0] rsp_value; wire [1:0] rsp_bank; wire rsp_in_stash; wire init_done;

    hft_rmic_amu_banked_double_hash_fast_v1 #(
        .TABLE_SIZE(32),.BANKS(4),.STASH_SIZE(2),.KEY_W(32),.VALUE_W(32)
    ) dut(
        .clk(clk),.rst_n(rst_n),.req_valid(req_valid),.req_ready(req_ready),
        .req_op(req_op),.req_key(req_key),.req_value(req_value),
        .rsp_valid(rsp_valid),.rsp_ready(rsp_ready),.rsp_ok(rsp_ok),
        .rsp_found(rsp_found),.rsp_status(rsp_status),.rsp_value(rsp_value),
        .rsp_bank(rsp_bank),.rsp_in_stash(rsp_in_stash),.init_done(init_done));

    task fail; input [8*120-1:0] msg; begin $display("TEST_FAIL %0s",msg); $fatal(1); end endtask

    task issue(input [1:0] op,input [31:0] key,input [31:0] value,output integer latency);
        integer fire_cycle;
        begin
            @(negedge clk); req_op=op; req_key=key; req_value=value; req_valid=1;
            while(!req_ready) @(posedge clk);
            @(posedge clk); #1; fire_cycle=cycle;
            @(negedge clk); req_valid=0;
            while(!rsp_valid) begin @(posedge clk); #1; end
            latency=cycle-fire_cycle;
        end
    endtask

    integer lat;
    initial begin
        repeat(4) @(posedge clk); @(negedge clk); rst_n=1;
        while(!init_done) @(posedge clk);

        issue(OP_INSERT,32'h11,32'hdeadbeef,lat);
        if(!rsp_ok || rsp_found || rsp_status!=ST_OK) fail("insert failed");
        if(lat>3) fail("fast AMU insert latency exceeded three-cycle target");
        $display("I5_FAST_AMU_INSERT_PASS cycles=%0d",lat);

        issue(OP_LOOKUP,32'h11,0,lat);
        if(!rsp_ok || !rsp_found || rsp_value!=32'hdeadbeef) fail("lookup failed");
        if(lat>3) fail("fast AMU lookup latency exceeded target");
        $display("I5_FAST_AMU_LOOKUP_PASS cycles=%0d",lat);

        issue(OP_INSERT,32'h11,32'h11111111,lat);
        if(rsp_ok || !rsp_found || rsp_status!=ST_EXISTS || rsp_value!=32'hdeadbeef) fail("duplicate semantics mismatch");
        $display("I5_FAST_AMU_DUPLICATE_PASS");

        issue(OP_UPDATE,32'h11,32'hcafef00d,lat);
        if(!rsp_ok || !rsp_found) fail("update failed");
        issue(OP_LOOKUP,32'h11,0,lat);
        if(!rsp_ok || !rsp_found || rsp_value!=32'hcafef00d) fail("updated lookup mismatch");
        $display("I5_FAST_AMU_UPDATE_PASS");

        issue(OP_DELETE,32'h11,0,lat);
        if(!rsp_ok || !rsp_found) fail("delete failed");
        issue(OP_LOOKUP,32'h11,0,lat);
        if(rsp_ok || rsp_found) fail("deleted key still found");
        $display("I5_FAST_AMU_DELETE_PASS");

        $display("HFT_RMIC_I5_FAST_AMU_TB_PASS");
        $finish;
    end
    initial begin #500000; fail("timeout"); end
endmodule
