`timescale 1ns/1ps
module tb_hft_rmic_cached_exact_map_v1;
    reg clk=0; always #5 clk=~clk;
    reg rst_n=0, cfg_we=0, cfg_valid=0;
    reg [1:0] cfg_index=0;
    reg [31:0] cfg_key=0, hot_key=0, lookup_key=0;
    reg [7:0] cfg_value=0;
    wire cache_ready, lookup_hit, lookup_ambiguous;
    wire [7:0] lookup_value;
    hft_rmic_cached_exact_map_v1 #(.KEY_W(32),.VALUE_W(8),.ENTRIES(4),.INDEX_W(2)) dut(
        .clk(clk),.rst_n(rst_n),.cfg_we(cfg_we),.cfg_index(cfg_index),
        .cfg_valid(cfg_valid),.cfg_key(cfg_key),.cfg_value(cfg_value),
        .hot_key(hot_key),.lookup_key(lookup_key),.cache_ready(cache_ready),
        .lookup_hit(lookup_hit),.lookup_ambiguous(lookup_ambiguous),.lookup_value(lookup_value));
    task fail; input [8*120-1:0] msg; begin $display("TEST_FAIL %0s",msg); $fatal(1); end endtask
    task write_entry(input [1:0] idx,input valid,input [31:0] key,input [7:0] value);
      begin
        @(negedge clk); cfg_we=1; cfg_index=idx; cfg_valid=valid; cfg_key=key; cfg_value=value;
        @(posedge clk); #1; @(negedge clk); cfg_we=0;
      end
    endtask
    task wait_ready; integer guard; begin
      guard=0; while(!cache_ready && guard<8) begin @(posedge clk); #1; guard=guard+1; end
      if(!cache_ready) fail("cache did not become ready");
    end endtask
    initial begin
      repeat(3) @(posedge clk); @(negedge clk); rst_n=1;
      hot_key=32'h11112222; lookup_key=32'h11112222;
      write_entry(0,1,32'h11112222,8'h12); wait_ready();
      if(!lookup_hit||lookup_ambiguous||lookup_value!==8'h12) fail("initial resolution");
      lookup_key=32'h33334444; #1; if(lookup_hit||lookup_ambiguous) fail("mismatch reused cache");
      write_entry(1,1,32'h33334444,8'h34);
      hot_key=32'h33334444; lookup_key=32'h33334444; #1; if(cache_ready) fail("hot key did not invalidate");
      wait_ready(); if(!lookup_hit||lookup_ambiguous||lookup_value!==8'h34) fail("second resolution");
      write_entry(2,1,32'h33334444,8'h56); wait_ready();
      if(lookup_hit||!lookup_ambiguous) fail("duplicate not ambiguous");
      write_entry(2,0,32'h33334444,0); wait_ready();
      if(!lookup_hit||lookup_ambiguous||lookup_value!==8'h34) fail("duplicate removal recovery");
      $display("HFT_RMIC_I5_CACHED_EXACT_MAP_TB_PASS"); $finish;
    end
    initial begin #200000; fail("timeout"); end
endmodule
