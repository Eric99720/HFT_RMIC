`timescale 1ns/1ps
`include "taifex_tmp_v2187_defs.svh"

module tb_hft_tmp_exec_position_tap;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg tap_valid = 1'b0;
    reg [63:0] tap_data = 64'd0;
    reg [7:0] tap_keep = 8'hff;
    reg tap_last = 1'b0;

    wire metadata_valid;
    wire [7:0] last_msg_type;
    wire [7:0] last_position_effect;

    integer capture_count = 0;
    reg [7:0] captured_msg_type = 0;
    reg [7:0] captured_position_effect = 0;

    hft_tmp_exec_position_tap dut (.*);

    always #5 clk = ~clk;

    always @(posedge clk) begin
        if (metadata_valid) begin
            capture_count <= capture_count + 1;
            captured_msg_type <= last_msg_type;
            captured_position_effect <= last_position_effect;
        end
    end

    task fail;
        input [8*96-1:0] msg;
        begin
            $display("TEST_FAIL %0s", msg);
            $fatal(1);
        end
    endtask

    task send_packet;
        input [7:0] msg_type;
        input [7:0] position_effect;
        input integer last_beat;
        integer i;
        begin
            for (i = 0; i <= last_beat; i = i + 1) begin
                @(negedge clk);
                tap_valid = 1'b1;
                tap_data = 64'd0;
                tap_keep = 8'hff;
                tap_last = (i == last_beat);

                // MessageType at absolute byte 12 = beat 1 / d4.
                if (i == 1)
                    tap_data[31:24] = msg_type;

                // R02 PositionEffect at byte 75 = beat 9 / d3.
                if ((msg_type == 8'd102) && (i == 9))
                    tap_data[39:32] = position_effect;

                // R32 PositionEffect at byte 95 = beat 11 / d7.
                if ((msg_type == 8'd132) && (i == 11))
                    tap_data[7:0] = position_effect;
            end

            @(negedge clk);
            tap_valid = 1'b0;
            tap_data = 64'd0;
            tap_last = 1'b0;
            repeat (2) @(posedge clk);
        end
    endtask

    initial begin
        repeat (3) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        send_packet(8'd102, `HFT_RMIC_TAIFEX_POS_OPEN, 16);
        if (capture_count != 1 || captured_msg_type != 8'd102 ||
            captured_position_effect != `HFT_RMIC_TAIFEX_POS_OPEN)
            fail("R02 PositionEffect offset/capture");
        $display("HFT_RMIC_R02_POSITION_EFFECT_TAP_PASS");

        send_packet(8'd132, `HFT_RMIC_TAIFEX_POS_CLOSE, 20);
        if (capture_count != 2 || captured_msg_type != 8'd132 ||
            captured_position_effect != `HFT_RMIC_TAIFEX_POS_CLOSE)
            fail("R32 PositionEffect offset/capture");
        $display("HFT_RMIC_R32_POSITION_EFFECT_TAP_PASS");

        // Unsupported report types must not produce accounting metadata.
        send_packet(8'd103, `HFT_RMIC_TAIFEX_POS_OPEN, 10);
        if (capture_count != 2)
            fail("unsupported message emitted metadata");
        $display("HFT_RMIC_EXEC_TAP_UNSUPPORTED_DROP_PASS");

        $display("HFT_RMIC_EXEC_POSITION_TAP_TB_PASS");
        $finish;
    end
endmodule
