`timescale 1ns/1ps
`include "taifex_tmp_v2187_defs.svh"

module tb_hft_tmp_exec_position_tap;
    reg clk=0; always #5 clk=~clk;
    reg rst_n=0;
    reg tap_valid=0;
    reg [63:0] tap_data=0;
    reg [7:0] tap_keep=8'hff;
    reg tap_last=0;

    wire metadata_valid;
    wire [7:0] last_msg_type;
    wire [7:0] last_position_effect;
    wire [15:0] last_before_qty;

    integer capture_count=0;
    reg [7:0] captured_msg_type=0;
    reg [7:0] captured_position_effect=0;
    reg [15:0] captured_before_qty=0;

    hft_tmp_exec_position_tap dut(.*);

    always @(posedge clk) begin
        if(metadata_valid) begin
            capture_count<=capture_count+1;
            captured_msg_type<=last_msg_type;
            captured_position_effect<=last_position_effect;
            captured_before_qty<=last_before_qty;
        end
    end

    task fail; input [8*96-1:0] msg; begin $display("TEST_FAIL %0s",msg); $fatal(1); end endtask

    task send_packet;
        input [7:0] msg_type;
        input [7:0] position_effect;
        input [15:0] before_qty;
        input integer last_beat;
        integer i;
        begin
            for(i=0;i<=last_beat;i=i+1) begin
                @(negedge clk);
                tap_valid=1;tap_data=0;tap_keep=8'hff;tap_last=(i==last_beat);
                if(i==1) tap_data[31:24]=msg_type; // byte 12 / d4
                if((msg_type==`HFT_RMIC_TAIFEX_MSG_R02)&&(i==9)) tap_data[39:32]=position_effect;
                if((msg_type==`HFT_RMIC_TAIFEX_MSG_R02)&&(i==11)) begin
                    tap_data[15:8]=before_qty[15:8]; tap_data[7:0]=before_qty[7:0];
                end
                if((msg_type==`HFT_RMIC_TAIFEX_MSG_R32)&&(i==11)) tap_data[7:0]=position_effect;
                if((msg_type==`HFT_RMIC_TAIFEX_MSG_R32)&&(i==14)) begin
                    tap_data[47:40]=before_qty[15:8]; tap_data[39:32]=before_qty[7:0];
                end
            end
            @(negedge clk);tap_valid=0;tap_data=0;tap_last=0;
            repeat(2) @(posedge clk);
        end
    endtask

    initial begin
        repeat(3) @(posedge clk);rst_n=1;repeat(2) @(posedge clk);

        send_packet(`HFT_RMIC_TAIFEX_MSG_R02,`HFT_RMIC_TAIFEX_POS_OPEN,16'd37,16);
        if(capture_count!=1 || captured_msg_type!=`HFT_RMIC_TAIFEX_MSG_R02 ||
           captured_position_effect!=`HFT_RMIC_TAIFEX_POS_OPEN || captured_before_qty!=16'd37)
            fail("R02 metadata offset/capture");
        $display("HFT_RMIC_R02_EXEC_META_TAP_PASS");

        send_packet(`HFT_RMIC_TAIFEX_MSG_R32,`HFT_RMIC_TAIFEX_POS_CLOSE,16'd91,20);
        if(capture_count!=2 || captured_msg_type!=`HFT_RMIC_TAIFEX_MSG_R32 ||
           captured_position_effect!=`HFT_RMIC_TAIFEX_POS_CLOSE || captured_before_qty!=16'd91)
            fail("R32 metadata offset/capture");
        $display("HFT_RMIC_R32_EXEC_META_TAP_PASS");

        send_packet(`HFT_RMIC_TAIFEX_MSG_R03,`HFT_RMIC_TAIFEX_POS_OPEN,16'd11,10);
        if(capture_count!=2) fail("unsupported message emitted metadata");
        $display("HFT_RMIC_EXEC_META_TAP_UNSUPPORTED_DROP_PASS");
        $display("HFT_RMIC_EXEC_POSITION_TAP_TB_PASS");
        $finish;
    end
endmodule
