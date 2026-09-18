`timescale 1ns/1ps
`include "taifex_tmp_v2187_defs.svh"
module tb_hft_rmic_committed_exec_event_adapter_v1;
reg clk=0; always #5 clk=~clk; reg rst_n=0;
reg live_meta_valid=0; reg [7:0] live_meta_msg_type=0; reg [31:0] live_meta_order_id=0, live_meta_report_seq=0; reg [7:0] live_meta_position_effect=0; reg [15:0] live_meta_before_qty=0;
reg replay_meta_valid=0; reg [7:0] replay_meta_msg_type=0; reg [31:0] replay_meta_order_id=0,replay_meta_report_seq=0; reg [7:0] replay_meta_position_effect=0; reg [15:0] replay_meta_before_qty=0;
reg committed_valid=0, committed_from_replay=0, committed_side=0; reg [7:0] committed_msg_type=0,committed_status_code=0,committed_exec_type=0; reg [31:0] committed_order_id=0,committed_order_price=0,committed_report_seq=0; reg [15:0] committed_last_qty=0,committed_leaves_qty=0;
wire risk_commit_valid; wire [7:0] risk_commit_msg_type,risk_commit_status_code,risk_commit_exec_type; wire [31:0] risk_commit_order_id; wire risk_commit_side; wire [7:0] risk_commit_position_effect; wire [31:0] risk_commit_order_price; wire [15:0] risk_commit_last_qty,risk_commit_leaves_qty,risk_commit_before_qty; wire [31:0] risk_commit_report_seq; wire risk_commit_is_replay,metadata_error;
hft_rmic_committed_exec_event_adapter_v1 dut(.*);
task fail; input [8*120-1:0] msg; begin $display("TEST_FAIL %0s",msg); $fatal(1); end endtask
initial begin
 repeat(3) @(posedge clk); @(negedge clk); rst_n=1;
 // Cache live R02 metadata, then commit matching report later.
 @(negedge clk); live_meta_msg_type=`HFT_RMIC_TAIFEX_MSG_R02; live_meta_order_id=32'd100; live_meta_report_seq=32'd7; live_meta_position_effect=8'h4f; live_meta_before_qty=16'd10; live_meta_valid=1;
 @(posedge clk); @(negedge clk); live_meta_valid=0;
 committed_msg_type=`HFT_RMIC_TAIFEX_MSG_R02; committed_order_id=100; committed_report_seq=7; committed_status_code=0; committed_exec_type=8'h46; committed_side=0; committed_order_price=1000; committed_last_qty=3; committed_leaves_qty=7; committed_from_replay=0; committed_valid=1; #1;
 if(!risk_commit_valid || metadata_error || risk_commit_position_effect!==8'h4f || risk_commit_before_qty!==16'd10) fail("live R02 commit mismatch");
 $display("I5_LIVE_COMMITTED_METADATA_PASS");
 @(posedge clk); @(negedge clk); committed_valid=0;

 // Mismatched identity must fail closed.
 @(negedge clk); live_meta_msg_type=`HFT_RMIC_TAIFEX_MSG_R02; live_meta_order_id=200; live_meta_report_seq=8; live_meta_position_effect=8'h4f; live_meta_before_qty=5; live_meta_valid=1;
 @(posedge clk); @(negedge clk); live_meta_valid=0; committed_msg_type=`HFT_RMIC_TAIFEX_MSG_R02; committed_order_id=201; committed_report_seq=8; committed_valid=1; #1;
 if(risk_commit_valid || !metadata_error) fail("metadata mismatch did not fail closed");
 $display("I5_COMMITTED_METADATA_MISMATCH_PASS");
 @(posedge clk); @(negedge clk); committed_valid=0;
 // A production mismatch escalates recovery-required. Reset here so the
 // remaining unit scenarios exercise independent cache states.
 rst_n=0; repeat(2) @(posedge clk); @(negedge clk); rst_n=1;

 // Replay R32 uses replay metadata rather than stale live metadata.
 @(negedge clk); replay_meta_msg_type=`HFT_RMIC_TAIFEX_MSG_R32; replay_meta_order_id=300; replay_meta_report_seq=99; replay_meta_position_effect=8'h43; replay_meta_before_qty=4; replay_meta_valid=1;
 @(posedge clk); @(negedge clk); replay_meta_valid=0; committed_msg_type=`HFT_RMIC_TAIFEX_MSG_R32; committed_order_id=300; committed_report_seq=99; committed_from_replay=1; committed_last_qty=1; committed_leaves_qty=3; committed_valid=1; #1;
 if(!risk_commit_valid || metadata_error || !risk_commit_is_replay || risk_commit_position_effect!==8'h43 || risk_commit_before_qty!==4) fail("replay R32 metadata mismatch");
 $display("I5_REPLAY_COMMITTED_METADATA_PASS");
 @(posedge clk); @(negedge clk); committed_valid=0;

 // A second metadata packet before the cached event is consumed must fail closed
 // and must not overwrite the original cached identity/payload.
 @(negedge clk); live_meta_msg_type=`HFT_RMIC_TAIFEX_MSG_R02; live_meta_order_id=500; live_meta_report_seq=10; live_meta_position_effect=8'h4f; live_meta_before_qty=6; live_meta_valid=1;
 @(posedge clk); @(negedge clk); live_meta_valid=0;
 @(negedge clk); live_meta_order_id=501; live_meta_report_seq=11; live_meta_position_effect=8'h43; live_meta_before_qty=2; live_meta_valid=1; #1;
 if(!metadata_error) fail("metadata cache overrun did not fail closed");
 $display("I5_COMMITTED_METADATA_OVERRUN_PASS");
 @(posedge clk); @(negedge clk); live_meta_valid=0;
 committed_msg_type=`HFT_RMIC_TAIFEX_MSG_R02; committed_order_id=500; committed_report_seq=10; committed_from_replay=0; committed_valid=1; #1;
 if(!risk_commit_valid || metadata_error || risk_commit_position_effect!==8'h4f || risk_commit_before_qty!==6) fail("overrun corrupted cached metadata");
 @(posedge clk); @(negedge clk); committed_valid=0;

 // Consuming the old cache and receiving the next metadata on the same cycle is
 // a legal atomic replace. The committed event must see the old payload and the
 // next commit must see the newly cached payload.
 @(negedge clk); live_meta_msg_type=`HFT_RMIC_TAIFEX_MSG_R02; live_meta_order_id=600; live_meta_report_seq=12; live_meta_position_effect=8'h4f; live_meta_before_qty=9; live_meta_valid=1;
 @(posedge clk); @(negedge clk); live_meta_valid=0;
 @(negedge clk);
 committed_msg_type=`HFT_RMIC_TAIFEX_MSG_R02; committed_order_id=600; committed_report_seq=12; committed_from_replay=0; committed_valid=1;
 live_meta_msg_type=`HFT_RMIC_TAIFEX_MSG_R02; live_meta_order_id=601; live_meta_report_seq=13; live_meta_position_effect=8'h43; live_meta_before_qty=4; live_meta_valid=1; #1;
 if(!risk_commit_valid || metadata_error || risk_commit_position_effect!==8'h4f || risk_commit_before_qty!==9) fail("atomic metadata replace old event mismatch");
 @(posedge clk); @(negedge clk); committed_valid=0; live_meta_valid=0;
 committed_order_id=601; committed_report_seq=13; committed_valid=1; #1;
 if(!risk_commit_valid || metadata_error || risk_commit_position_effect!==8'h43 || risk_commit_before_qty!==4) fail("atomic metadata replace next event mismatch");
 $display("I5_COMMITTED_METADATA_ATOMIC_REPLACE_PASS");
 @(posedge clk); @(negedge clk); committed_valid=0;

 // R03 is committed directly; stored order context owns side/PE release semantics.
 @(negedge clk); committed_msg_type=`HFT_RMIC_TAIFEX_MSG_R03; committed_order_id=400; committed_report_seq=0; committed_from_replay=0; committed_valid=1; #1;
 if(!risk_commit_valid || metadata_error || risk_commit_position_effect!==0 || risk_commit_before_qty!==0) fail("R03 direct commit mismatch");
 $display("I5_R03_COMMITTED_EVENT_PASS");
 $display("HFT_RMIC_I5_COMMITTED_EXEC_EVENT_ADAPTER_TB_PASS");
 $finish;
end
initial begin #100000; fail("timeout"); end
endmodule
