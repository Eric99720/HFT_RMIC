`timescale 1ns/1ps
`include "taifex_tmp_v2187_defs.svh"

module tb_hft_tmp_exec_metadata_tap_v2;
    reg clk=0; always #5 clk=~clk;
    reg rst_n=0;
    reg tap_valid=0; reg [63:0] tap_data=0; reg [7:0] tap_keep=8'hff; reg tap_last=0;
    wire metadata_valid; wire [7:0] last_msg_type; wire [31:0] last_order_id;
    wire [31:0] last_report_seq; wire [7:0] last_position_effect; wire [15:0] last_before_qty;

    hft_tmp_exec_metadata_tap_v2 dut(
        .clk(clk),.rst_n(rst_n),.tap_valid(tap_valid),.tap_data(tap_data),
        .tap_keep(tap_keep),.tap_last(tap_last),.metadata_valid(metadata_valid),
        .last_msg_type(last_msg_type),.last_order_id(last_order_id),
        .last_report_seq(last_report_seq),.last_position_effect(last_position_effect),
        .last_before_qty(last_before_qty));

    task fail; input [8*120-1:0] msg; begin $display("TEST_FAIL %0s",msg); $fatal(1); end endtask
    task beat;
        input [7:0] d0,d1,d2,d3,d4,d5,d6,d7; input last;
        begin
            @(negedge clk); tap_valid=1; tap_data={d0,d1,d2,d3,d4,d5,d6,d7}; tap_last=last;
            @(posedge clk); #1;
            @(negedge clk); tap_valid=0; tap_last=0; tap_data=0;
        end
    endtask
    task zeros; input integer count; integer i; begin for(i=0;i<count;i=i+1) beat(0,0,0,0,0,0,0,0,0); end endtask

    initial begin
        repeat(3) @(posedge clk); @(negedge clk); rst_n=1;

        // R02: order_id=0x11223344, PE='O', before=0x1234, report_seq=0x89abcdef.
        beat(0,0,0,0,0,0,0,0,0); // beat0
        beat(0,0,0,0,`HFT_RMIC_TAIFEX_MSG_R02,0,0,0,0); // beat1
        beat(0,0,0,0,0,0,0,0,0); // beat2
        beat(0,0,0,0,8'h11,8'h22,8'h33,8'h44,0); // beat3 order id
        zeros(5); // beats4..8
        beat(0,0,0,8'h4f,0,0,0,0,0); // beat9 PE=O
        beat(0,0,0,0,0,0,0,0,0); // beat10
        beat(0,0,0,0,0,0,8'h12,8'h34,0); // beat11 before
        zeros(3); // beats12..14
        beat(0,0,0,0,0,0,0,8'h89,0); // beat15 seq high
        beat(8'hab,8'hcd,8'hef,0,0,0,0,0,0); // beat16 seq low
        beat(0,0,0,0,0,0,0,0,1); // beat17 last
        if(!metadata_valid) fail("R02 metadata_valid missing");
        if(last_msg_type!==`HFT_RMIC_TAIFEX_MSG_R02 || last_order_id!==32'h11223344 ||
           last_report_seq!==32'h89abcdef || last_position_effect!==8'h4f || last_before_qty!==16'h1234)
            fail("R02 metadata mismatch");
        $display("I5_R02_KEYED_METADATA_PASS");

        // R32: order_id=0xa1b2c3d4, PE='C', before=0x5678, report_seq=0x10203040.
        beat(0,0,0,0,0,0,0,0,0);
        beat(0,0,0,0,`HFT_RMIC_TAIFEX_MSG_R32,0,0,0,0);
        beat(0,0,0,0,0,0,0,0,0);
        beat(0,0,0,0,8'ha1,8'hb2,8'hc3,8'hd4,0);
        zeros(7); // beats4..10
        beat(0,0,0,0,0,0,0,8'h43,0); // beat11 PE=C
        zeros(2); // beats12..13
        beat(0,0,8'h56,8'h78,0,0,0,0,0); // beat14 before
        zeros(3); // beats15..17
        beat(0,0,0,8'h10,8'h20,8'h30,8'h40,0,0); // beat18 seq
        beat(0,0,0,0,0,0,0,0,1); // beat19 last
        if(!metadata_valid) fail("R32 metadata_valid missing");
        if(last_msg_type!==`HFT_RMIC_TAIFEX_MSG_R32 || last_order_id!==32'ha1b2c3d4 ||
           last_report_seq!==32'h10203040 || last_position_effect!==8'h43 || last_before_qty!==16'h5678)
            fail("R32 metadata mismatch");
        $display("I5_R32_KEYED_METADATA_PASS");

        $display("HFT_RMIC_I5_EXEC_METADATA_TAP_V2_TB_PASS");
        $finish;
    end
    initial begin #200000; fail("timeout"); end
endmodule
