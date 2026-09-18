`timescale 1ns/1ps

module tb_hft_rmic_spec_order_dedupe_v1;
    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg rst_n = 1'b0;
    reg clear = 1'b0;
    reg s_valid = 1'b0;
    reg [15:0] s_symbol = 16'h5458;
    reg s_side = 1'b0;
    reg [31:0] s_price = 32'd1041;
    reg [31:0] s_qty = 32'd1;
    reg [3:0] s_type = 4'd2;
    reg [7:0] s_tif = 8'd0;
    reg [7:0] s_position_effect = 8'h4f;
    reg downstream_ready = 1'b0;

    wire m_valid;
    wire duplicate_blocked;
    wire m_accept = m_valid && downstream_ready;

    hft_rmic_spec_order_dedupe_v1 dut (
        .clk(clk), .rst_n(rst_n), .clear(clear),
        .s_valid(s_valid), .s_symbol(s_symbol), .s_side(s_side),
        .s_price(s_price), .s_qty(s_qty), .s_type(s_type),
        .s_tif(s_tif), .s_position_effect(s_position_effect),
        .m_valid(m_valid), .m_accept(m_accept),
        .duplicate_blocked(duplicate_blocked)
    );

    task fail;
        input [8*120-1:0] msg;
        begin
            $display("TEST_FAIL %0s", msg);
            $fatal(1);
        end
    endtask

    initial begin
        repeat (3) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;

        // Backpressure must not teach the guard a key before handoff.
        s_valid = 1'b1;
        downstream_ready = 1'b0;
        #1;
        if (!m_valid || duplicate_blocked) fail("first request hidden under backpressure");
        repeat (2) @(posedge clk);
        #1;
        if (!m_valid || duplicate_blocked) fail("unaccepted request incorrectly remembered");

        // First accepted key is forwarded.
        @(negedge clk);
        downstream_ready = 1'b1;
        @(posedge clk);
        #1;
        @(negedge clk);
        s_valid = 1'b0;
        downstream_ready = 1'b0;

        // Exact consecutive duplicate must be suppressed.
        @(negedge clk);
        s_valid = 1'b1;
        downstream_ready = 1'b1;
        #1;
        if (m_valid || !duplicate_blocked) fail("exact duplicate was not blocked");
        @(negedge clk);
        s_valid = 1'b0;

        // PositionEffect is part of the key: CLOSE is not a duplicate of OPEN.
        @(negedge clk);
        s_position_effect = 8'h43;
        s_valid = 1'b1;
        #1;
        if (!m_valid || duplicate_blocked) fail("OPEN/CLOSE distinction was lost");
        @(posedge clk);
        #1;
        @(negedge clk);
        s_valid = 1'b0;

        // The newly accepted CLOSE key is now the duplicate.
        @(negedge clk);
        s_valid = 1'b1;
        #1;
        if (m_valid || !duplicate_blocked) fail("second accepted key did not become duplicate history");
        @(negedge clk);
        s_valid = 1'b0;

        // Recovery clears history so the same key can be admitted again.
        clear = 1'b1;
        @(posedge clk);
        #1;
        @(negedge clk);
        clear = 1'b0;
        s_valid = 1'b1;
        #1;
        if (!m_valid || duplicate_blocked) fail("recovery clear did not release duplicate history");

        $display("HFT_RMIC_I5_SPEC_ORDER_DEDUPE_TB_PASS");
        $finish;
    end

    initial begin
        #100000;
        fail("timeout");
    end
endmodule
