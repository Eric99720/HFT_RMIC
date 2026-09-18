`timescale 1ns/1ps
module tb_hft_rmic_order_ingress_slice_v1;
    reg clk=0; always #5 clk=~clk;
    reg rst_n=0, clear=0, s_valid=0, s_source_prebuild=0, m_ready=0;
    reg [31:0] s_data=0;
    wire s_ready, m_valid, m_source_prebuild;
    wire [31:0] m_data;
    hft_rmic_order_ingress_slice_v1 #(.ORDER_WIDTH(32)) dut(
        .clk(clk),.rst_n(rst_n),.clear(clear),.s_valid(s_valid),.s_ready(s_ready),
        .s_data(s_data),.s_source_prebuild(s_source_prebuild),
        .m_valid(m_valid),.m_ready(m_ready),.m_data(m_data),.m_source_prebuild(m_source_prebuild));
    task fail; input [8*120-1:0] msg; begin $display("TEST_FAIL %0s",msg); $fatal(1); end endtask
    initial begin
        repeat(3) @(posedge clk); @(negedge clk); rst_n=1;
        s_valid=1; s_data=32'h11223344; s_source_prebuild=1; m_ready=1;
        #1; if(!s_ready || m_valid) fail("slice is not registered");
        @(posedge clk); #1;
        if(!m_valid || m_data!==32'h11223344 || !m_source_prebuild) fail("first capture mismatch");
        @(negedge clk); s_data=32'ha5a55a5a; s_source_prebuild=0; s_valid=1; m_ready=1;
        @(posedge clk); #1;
        if(!m_valid || m_data!==32'ha5a55a5a || m_source_prebuild) fail("replace-on-pop mismatch");
        @(negedge clk); s_valid=0; m_ready=0; #1;
        if(s_ready) fail("full slice advertised ready under backpressure");
        repeat(2) @(posedge clk); #1;
        if(!m_valid || m_data!==32'ha5a55a5a) fail("backpressure corrupted payload");
        @(negedge clk); m_ready=1; @(posedge clk); #1;
        if(m_valid) fail("drain did not empty slice");
        @(negedge clk); m_ready=0; s_valid=1; s_data=32'hdeadbeef;
        @(posedge clk); #1;
        @(negedge clk); s_valid=0; clear=1; @(posedge clk); #1;
        if(m_valid) fail("clear did not flush slice");
        $display("HFT_RMIC_I5_ORDER_INGRESS_SLICE_TB_PASS");
        $finish;
    end
    initial begin #100000; fail("timeout"); end
endmodule
