`timescale 1ns/1ps
module tb_hft_rmic_exec_commit_fifo_v1;
reg clk=0; always #5 clk=~clk; reg rst_n=0,flush=0,s_valid=0,m_ready=0;
reg [7:0] s_msg_type=0,s_status_code=0,s_exec_type=0,s_position_effect=0; reg [31:0] s_order_id=0,s_order_price=0; reg s_side=0; reg [15:0] s_last_qty=0,s_leaves_qty=0,s_before_qty=0;
wire s_ready,m_valid,m_side,overflow_sticky; wire [7:0] m_msg_type,m_status_code,m_exec_type,m_position_effect; wire [31:0] m_order_id,m_order_price; wire [15:0] m_last_qty,m_leaves_qty,m_before_qty; wire [2:0] occupancy;
hft_rmic_exec_commit_fifo_v1 #(.DEPTH(4),.PTR_W(2)) dut(.*);
task fail; input [8*120-1:0] msg; begin $display("TEST_FAIL %0s",msg); $fatal(1); end endtask
task push; input [31:0] oid; begin @(negedge clk); s_order_id=oid;s_msg_type=8'd102;s_before_qty=oid[15:0];s_valid=1; while(!s_ready) @(posedge clk); @(posedge clk); @(negedge clk);s_valid=0; end endtask
task pop_expect; input [31:0] oid; begin while(!m_valid) @(posedge clk); #1; if(m_order_id!==oid || m_before_qty!==oid[15:0]) fail("FIFO ordering mismatch"); @(negedge clk);m_ready=1;@(posedge clk);@(negedge clk);m_ready=0; end endtask
initial begin
 repeat(3) @(posedge clk); @(negedge clk);rst_n=1;
 push(1);push(2);push(3); if(occupancy!==3) fail("occupancy mismatch");
 pop_expect(1);pop_expect(2);pop_expect(3); $display("I5_EXEC_FIFO_ORDER_PASS");
 push(10);push(11);push(12);push(13); if(s_ready) fail("FIFO should be full");
 @(negedge clk);s_order_id=14;s_valid=1;@(posedge clk);@(negedge clk);s_valid=0; if(!overflow_sticky) fail("overflow sticky missing");
 $display("I5_EXEC_FIFO_OVERFLOW_FAIL_CLOSED_PASS");
 @(negedge clk);flush=1;@(posedge clk);@(negedge clk);flush=0; if(occupancy!==0 || overflow_sticky) fail("flush failed");
 $display("I5_EXEC_FIFO_RECOVERY_FLUSH_PASS");
 $display("HFT_RMIC_I5_EXEC_COMMIT_FIFO_TB_PASS");$finish;
end
initial begin #100000;fail("timeout");end
endmodule
