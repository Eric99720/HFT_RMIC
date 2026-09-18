`timescale 1ns/1ps
module tb_hft_rmic_xgmii_tx_encoder_v1;
    localparam MAX_BYTES=128;
    reg clk=0; always #3.2 clk=~clk;
    reg rst_n=0, s_valid=0, s_last=0, s_user=0;
    reg [63:0] s_data=0; reg [7:0] s_keep=0;
    wire s_ready; wire [63:0] txd; wire [7:0] txc;
    wire frame_done, frame_error; wire [7:0] error_code;
    wire [15:0] frame_len; wire [31:0] fcs_value;
    byte unsigned payload[0:MAX_BYTES-1]; byte unsigned got[0:MAX_BYTES-1];
    integer got_len; reg collecting=0, done=0;

    hft_rmic_xgmii_tx_encoder_v1 #(.MAX_FRAME_BYTES(MAX_BYTES)) dut(
        .clk(clk),.rst_n(rst_n),.s_axis_tvalid(s_valid),.s_axis_tready(s_ready),
        .s_axis_tdata(s_data),.s_axis_tkeep(s_keep),.s_axis_tlast(s_last),.s_axis_tuser(s_user),
        .xgmii_txd(txd),.xgmii_txc(txc),.frame_done(frame_done),.frame_error(frame_error),
        .error_code(error_code),.frame_len(frame_len),.fcs_value(fcs_value));

    function automatic [31:0] crc_byte(input [31:0] crc,input [7:0] d);
        integer b; reg [31:0] c;
        begin c=crc^{24'd0,d}; for(b=0;b<8;b=b+1) c=c[0]?((c>>1)^32'hedb88320):(c>>1); crc_byte=c; end
    endfunction
    task fail; input [8*120-1:0] msg; begin $display("TEST_FAIL %0s",msg); $fatal(1); end endtask
    task send_frame(input integer len);
        integer idx,lane; reg [63:0] w; reg [7:0] k;
        begin
            for(idx=0;idx<MAX_BYTES;idx=idx+1) payload[idx]=0;
            for(idx=0;idx<len;idx=idx+1) payload[idx]=(8'h31+idx[7:0]);
            idx=0;
            while(idx<len) begin
                while(!s_ready) @(posedge clk);
                w=0; k=0;
                for(lane=0;lane<8;lane=lane+1) if(idx+lane<len) begin w[lane*8 +: 8]=payload[idx+lane]; k[lane]=1; end
                @(negedge clk); s_valid=1; s_data=w; s_keep=k; s_last=(idx+8>=len);
                @(posedge clk); @(negedge clk); s_valid=0; s_last=0; s_keep=0; s_data=0;
                idx=idx+8;
            end
        end
    endtask
    task check_frame(input integer len);
        integer n,padded; reg [31:0] crc;
        begin
            got_len=0; collecting=0; done=0; send_frame(len); wait(done); #1;
            padded=(len<60)?60:len;
            if(got_len!==padded+4) fail("wire length mismatch");
            for(n=0;n<len;n=n+1) if(got[n]!==payload[n]) fail("payload mismatch");
            for(n=len;n<padded;n=n+1) if(got[n]!==0) fail("padding mismatch");
            crc=32'hffff_ffff;
            for(n=0;n<padded;n=n+1) crc=crc_byte(crc,(n<len)?payload[n]:8'h00);
            crc=~crc;
            if(got[padded]!==crc[7:0] || got[padded+1]!==crc[15:8] ||
               got[padded+2]!==crc[23:16] || got[padded+3]!==crc[31:24]) fail("FCS mismatch");
            if(frame_error || frame_len!==padded) fail("frame status mismatch");
        end
    endtask
    always @(posedge clk) begin
        integer lane;
        if(!rst_n) begin collecting<=0; done<=0; got_len<=0; end
        else begin
            if(txc[0] && txd[7:0]==8'hfb) collecting<=1;
            else if(collecting) begin
                for(lane=0;lane<8;lane=lane+1) begin
                    if(!txc[lane]) begin got[got_len]=txd[lane*8 +:8]; got_len=got_len+1; end
                    else if(txd[lane*8 +:8]==8'hfd) begin collecting<=0; done<=1; end
                end
            end
        end
    end
    initial begin
        repeat(5) @(posedge clk); rst_n=1; repeat(2) @(posedge clk);
        check_frame(42); repeat(4) @(posedge clk);
        check_frame(54); repeat(4) @(posedge clk);
        check_frame(60); repeat(4) @(posedge clk);
        check_frame(64);
        $display("HFT_RMIC_I5_XGMII_TX_TIMING_DERIVATIVE_TB_PASS");
        $finish;
    end
    initial begin #500000; fail("timeout"); end
endmodule
