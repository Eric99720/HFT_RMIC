`timescale 1ns/1ps
`include "hft_rmic_contract.svh"
`include "hft_rmic_policy_defs.svh"
`include "taifex_tmp_v2187_defs.svh"

// Local Vivado/XSim sign-off for the I4 R01 insertion boundary.
//
// One frozen financial_protocol_encoder is driven directly with the original
// 256-bit HFT order_data (baseline).  A second identical frozen encoder is
// driven only after the same payload passes the integration-owned futures risk
// gate.  Packet latency is intentionally allowed to differ; the complete 80
// byte R01 payload must be bit-for-bit identical.
module tb_hft_rmic_i4_r01_byte_parity;
    localparam integer ORDER_WIDTH = 256;
    localparam integer DATA_WIDTH = 64;

    reg clk = 1'b0;
    always #3.2 clk = ~clk; // 156.25 MHz
    reg rst_n = 1'b0;

    // Common frozen R01 metadata.
    reg [31:0] msg_epoch_s = 32'h12345678;
    reg [15:0] msg_ms = 16'h0203;
    reg [15:0] fcm_id = 16'h1111;
    reg [15:0] session_id = 16'h2222;
    reg [15:0] cm_id = 16'h3333;
    reg [15:0] body_fcm_id = 16'h4444;
    reg [63:0] user_define = 64'h0102030405060708;
    reg [159:0] symbol_text = 160'h2020202020202020202020202020202020465854;
    reg [7:0] order_source = 8'h31;
    reg [23:0] info_source = 24'h414243;
    reg [31:0] r01_msg_seq_num = 32'h10203040;
    reg network_ready = 1'b1;
    reg tx_ready = 1'b1;

    // Baseline frozen encoder input/output.
    reg baseline_order_valid = 1'b0;
    wire baseline_order_ready;
    reg [ORDER_WIDTH-1:0] baseline_order_data = 0;
    wire [63:0] baseline_tx_data;
    wire [7:0] baseline_tx_keep;
    wire baseline_tx_valid;
    wire baseline_tx_last;
    wire [15:0] baseline_tx_payload_len;
    wire baseline_tx_complete;

    // Integrated legacy/prebuild order producers.
    reg legacy_order_valid = 1'b0;
    wire legacy_order_ready;
    reg [ORDER_WIDTH-1:0] legacy_order_data = 0;
    reg prebuild_order_valid = 1'b0;
    wire prebuild_order_accept;
    reg [ORDER_WIDTH-1:0] prebuild_order_data = 0;

    reg integration_ready = 1'b1;
    reg accounting_ready = 1'b1;
    reg global_kill = 1'b0;
    reg recovery_clear = 1'b0;
    wire recovery_required;
    wire store_init_done;
    wire [1:0] transaction_owner;
    reg [255:0] order_type_allow_mask = 0;
    reg [255:0] tif_allow_mask = 0;
    reg [255:0] position_effect_allow_mask = 0;

    reg account_cfg_we = 1'b0;
    reg [3:0] account_cfg_index = 0;
    reg account_cfg_valid = 1'b0;
    reg [31:0] account_cfg_key = 0;
    reg [7:0] account_cfg_value = 0;
    reg product_cfg_we = 1'b0;
    reg [3:0] product_cfg_index = 0;
    reg product_cfg_valid = 1'b0;
    reg [15:0] product_cfg_key = 0;
    reg [7:0] product_cfg_value = 0;

    reg cfg_valid = 1'b0;
    wire cfg_ready;
    reg [7:0] cfg_account_id = 0;
    reg [7:0] cfg_product_id = 0;
    reg cfg_enabled = 1'b0;
    reg [63:0] cfg_margin_budget = 0;
    reg [63:0] cfg_margin_per_contract = 0;
    reg [15:0] cfg_long_position = 0;
    reg [15:0] cfg_short_position = 0;
    reg [15:0] cfg_pending_open_long = 0;
    reg [15:0] cfg_pending_open_short = 0;
    reg [15:0] cfg_reserved_close_long = 0;
    reg [15:0] cfg_reserved_close_short = 0;
    wire cfg_done, cfg_ok;
    wire [7:0] cfg_reason_code;

    reg exec_commit_valid = 1'b0;
    wire exec_commit_ready;
    reg [7:0] exec_commit_msg_type = 0;
    reg [7:0] exec_commit_status_code = 0;
    reg [7:0] exec_commit_exec_type = 0;
    reg [31:0] exec_commit_order_id = 0;
    reg exec_commit_side = 0;
    reg [7:0] exec_commit_position_effect = 0;
    reg [31:0] exec_commit_order_price = 0;
    reg [15:0] exec_commit_last_qty = 0;
    reg [15:0] exec_commit_leaves_qty = 0;
    reg [15:0] exec_commit_before_qty = 0;
    wire exec_result_valid;
    reg exec_result_ready = 1'b0;
    wire exec_result_ok;
    wire [1:0] exec_result_reason_source;
    wire [7:0] exec_result_reason_code;
    wire [31:0] exec_result_order_id;
    wire [15:0] exec_result_remaining_qty;

    wire risk_reject_valid;
    reg risk_reject_ready = 1'b0;
    wire [31:0] risk_reject_order_id;
    wire [1:0] risk_reject_reason_source;
    wire [7:0] risk_reject_reason_code;

    wire [63:0] integrated_tx_data;
    wire [7:0] integrated_tx_keep;
    wire integrated_tx_valid;
    wire integrated_tx_last;
    wire [15:0] integrated_tx_payload_len;
    wire integrated_tx_complete;
    wire [7:0] integrated_tx_message_type;
    wire [31:0] encoder_accepted_order_count;
    wire [31:0] encoder_sent_r01_count;

    wire baseline_manual_ready_unused, baseline_r04_ready_unused, baseline_local_r04_ready_unused;
    wire baseline_fifo_full_unused, baseline_fifo_empty_unused, baseline_busy_unused, baseline_payload_active_unused;
    wire baseline_error_unused;
    wire [31:0] baseline_accepted_unused, baseline_sent_unused, baseline_sent_r01_unused;
    wire [31:0] baseline_sent_r05_unused, baseline_sent_r04_unused, baseline_dropped_unused;
    wire [31:0] baseline_sum_unused; wire baseline_sum_valid_unused; wire [7:0] baseline_msg_type_unused;

    financial_protocol_encoder #(
        .ORDER_WIDTH(ORDER_WIDTH), .DATA_WIDTH(DATA_WIDTH),
        .ALLOW_STRATEGY_BYPASS_WITHOUT_TX_READY(1'b0),
        .ENABLE_TMP_MAINTENANCE(1'b0), .ENABLE_TMP_FLOW_CONTROL(1'b0)
    ) u_baseline_encoder (
        .clk(clk), .rst(~rst_n),
        .manual_order_valid(1'b0), .manual_order_ready(baseline_manual_ready_unused),
        .manual_order_data({ORDER_WIDTH{1'b0}}),
        .strategy_order_valid(baseline_order_valid), .strategy_order_ready(baseline_order_ready),
        .strategy_order_data(baseline_order_data),
        .r04_valid(1'b0), .r04_ready(baseline_r04_ready_unused),
        .local_r04_valid(1'b0), .local_r04_ready(baseline_local_r04_ready_unused),
        .ordinary_credit_available(1'b1),
        .msg_epoch_s(msg_epoch_s), .msg_ms(msg_ms), .fcm_id(fcm_id), .session_id(session_id),
        .cm_id(cm_id), .body_fcm_id(body_fcm_id), .user_define(user_define),
        .symbol_text(symbol_text), .order_source(order_source), .info_source(info_source),
        .r01_msg_seq_num(r01_msg_seq_num), .network_ready(network_ready),
        .tx_data(baseline_tx_data), .tx_keep(baseline_tx_keep), .tx_valid(baseline_tx_valid),
        .tx_ready(tx_ready), .tx_last(baseline_tx_last), .tx_payload_len(baseline_tx_payload_len),
        .tx_complete(baseline_tx_complete), .tx_message_type(baseline_msg_type_unused),
        .fifo_full(baseline_fifo_full_unused), .fifo_empty(baseline_fifo_empty_unused),
        .encoder_busy(baseline_busy_unused), .payload_active(baseline_payload_active_unused),
        .error_overflow(baseline_error_unused), .accepted_order_count(baseline_accepted_unused),
        .sent_order_count(baseline_sent_unused), .sent_r01_count(baseline_sent_r01_unused),
        .sent_r05_count(baseline_sent_r05_unused), .sent_r04_count(baseline_sent_r04_unused),
        .dropped_order_count(baseline_dropped_unused), .r01_tcp_payload_sum(baseline_sum_unused),
        .r01_tcp_payload_sum_valid(baseline_sum_valid_unused)
    );

    hft_rmic_r01_path_v1 u_integrated (
        .clk(clk), .rst_n(rst_n),
        .legacy_order_valid(legacy_order_valid), .legacy_order_ready(legacy_order_ready),
        .legacy_order_data(legacy_order_data), .prebuild_order_valid(prebuild_order_valid),
        .prebuild_order_accept(prebuild_order_accept), .prebuild_order_data(prebuild_order_data),
        .integration_ready(integration_ready), .accounting_ready(accounting_ready),
        .global_kill(global_kill), .recovery_clear(recovery_clear),
        .recovery_required(recovery_required), .store_init_done(store_init_done),
        .transaction_owner(transaction_owner), .order_type_allow_mask(order_type_allow_mask),
        .tif_allow_mask(tif_allow_mask), .position_effect_allow_mask(position_effect_allow_mask),
        .account_cfg_we(account_cfg_we), .account_cfg_index(account_cfg_index),
        .account_cfg_valid(account_cfg_valid), .account_cfg_key(account_cfg_key),
        .account_cfg_value(account_cfg_value), .product_cfg_we(product_cfg_we),
        .product_cfg_index(product_cfg_index), .product_cfg_valid(product_cfg_valid),
        .product_cfg_key(product_cfg_key), .product_cfg_value(product_cfg_value),
        .cfg_valid(cfg_valid), .cfg_ready(cfg_ready), .cfg_account_id(cfg_account_id),
        .cfg_product_id(cfg_product_id), .cfg_enabled(cfg_enabled),
        .cfg_margin_budget(cfg_margin_budget), .cfg_margin_per_contract(cfg_margin_per_contract),
        .cfg_long_position(cfg_long_position), .cfg_short_position(cfg_short_position),
        .cfg_pending_open_long(cfg_pending_open_long), .cfg_pending_open_short(cfg_pending_open_short),
        .cfg_reserved_close_long(cfg_reserved_close_long), .cfg_reserved_close_short(cfg_reserved_close_short),
        .cfg_done(cfg_done), .cfg_ok(cfg_ok), .cfg_reason_code(cfg_reason_code),
        .exec_commit_valid(exec_commit_valid), .exec_commit_ready(exec_commit_ready),
        .exec_commit_msg_type(exec_commit_msg_type), .exec_commit_status_code(exec_commit_status_code),
        .exec_commit_exec_type(exec_commit_exec_type), .exec_commit_order_id(exec_commit_order_id),
        .exec_commit_side(exec_commit_side), .exec_commit_position_effect(exec_commit_position_effect),
        .exec_commit_order_price(exec_commit_order_price), .exec_commit_last_qty(exec_commit_last_qty),
        .exec_commit_leaves_qty(exec_commit_leaves_qty), .exec_commit_before_qty(exec_commit_before_qty),
        .exec_result_valid(exec_result_valid), .exec_result_ready(exec_result_ready),
        .exec_result_ok(exec_result_ok), .exec_result_reason_source(exec_result_reason_source),
        .exec_result_reason_code(exec_result_reason_code), .exec_result_order_id(exec_result_order_id),
        .exec_result_remaining_qty(exec_result_remaining_qty),
        .risk_reject_valid(risk_reject_valid), .risk_reject_ready(risk_reject_ready),
        .risk_reject_order_id(risk_reject_order_id), .risk_reject_reason_source(risk_reject_reason_source),
        .risk_reject_reason_code(risk_reject_reason_code),
        .msg_epoch_s(msg_epoch_s), .msg_ms(msg_ms), .fcm_id(fcm_id), .session_id(session_id),
        .cm_id(cm_id), .body_fcm_id(body_fcm_id), .user_define(user_define),
        .symbol_text(symbol_text), .order_source(order_source), .info_source(info_source),
        .r01_msg_seq_num(r01_msg_seq_num), .network_ready(network_ready),
        .tx_data(integrated_tx_data), .tx_keep(integrated_tx_keep), .tx_valid(integrated_tx_valid),
        .tx_ready(tx_ready), .tx_last(integrated_tx_last), .tx_payload_len(integrated_tx_payload_len),
        .tx_complete(integrated_tx_complete), .tx_message_type(integrated_tx_message_type),
        .encoder_accepted_order_count(encoder_accepted_order_count),
        .encoder_sent_r01_count(encoder_sent_r01_count)
    );

    reg [7:0] baseline_bytes [0:79];
    reg [7:0] integrated_bytes [0:79];
    integer baseline_len = 0;
    integer integrated_len = 0;

    always @(posedge clk) begin : capture_packets
        integer i;
        if (baseline_tx_valid && tx_ready) begin
            for (i=0; i<8; i=i+1)
                if (baseline_tx_keep[i] && baseline_len < 80) begin
                    baseline_bytes[baseline_len] = baseline_tx_data[i*8 +: 8];
                    baseline_len = baseline_len + 1;
                end
        end
        if (integrated_tx_valid && tx_ready) begin
            for (i=0; i<8; i=i+1)
                if (integrated_tx_keep[i] && integrated_len < 80) begin
                    integrated_bytes[integrated_len] = integrated_tx_data[i*8 +: 8];
                    integrated_len = integrated_len + 1;
                end
        end
    end

    task fail(input [8*120-1:0] msg);
        begin $display("I4_R01_PARITY_FAIL %0s", msg); $fatal(1); end
    endtask

    function automatic [255:0] mk_order(input [31:0] oid, input [31:0] price, input [15:0] qty);
        reg [255:0] d;
        begin
            d = 0;
            d[`HFT_RMIC_PRICE_LSB +:32] = price;
            d[`HFT_RMIC_QTY_LSB +:16] = qty;
            d[`HFT_RMIC_SIDE_LSB +:8] = `HFT_RMIC_TMP_SIDE_BUY;
            d[`HFT_RMIC_TIF_LSB +:8] = `HFT_RMIC_TAIFEX_TIF_ROD;
            d[`HFT_RMIC_POS_EFFECT_LSB +:8] = `HFT_RMIC_TAIFEX_POS_OPEN;
            d[`HFT_RMIC_INV_ACNO_LSB +:32] = 32'h11112222;
            d[`HFT_RMIC_ORDER_ID_LSB +:32] = oid;
            d[`HFT_RMIC_SYMBOL_SLOT_LSB +:16] = 16'd0;
            d[`HFT_RMIC_ORD_TYPE_LSB +:8] = `HFT_RMIC_TAIFEX_ORD_LIMIT;
            d[183:144] = 40'h4130303031;
            mk_order = d;
        end
    endfunction

    task clear_capture;
        integer i;
        begin
            baseline_len = 0; integrated_len = 0;
            for (i=0; i<80; i=i+1) begin baseline_bytes[i]=0; integrated_bytes[i]=0; end
        end
    endtask

    task send_baseline(input [255:0] d);
        integer g;
        begin
            @(negedge clk); baseline_order_data=d; baseline_order_valid=1; #1; g=0;
            while(!baseline_order_ready) begin @(posedge clk); #1; g=g+1; if(g>200) fail("baseline ready timeout"); end
            @(posedge clk); @(negedge clk); baseline_order_valid=0;
        end
    endtask

    task send_integrated_legacy(input [255:0] d);
        integer g;
        begin
            @(negedge clk); legacy_order_data=d; legacy_order_valid=1; #1; g=0;
            while(!legacy_order_ready) begin @(posedge clk); #1; g=g+1; if(g>800) fail("legacy risk ready timeout"); end
            @(posedge clk); @(negedge clk); legacy_order_valid=0;
        end
    endtask

    task send_integrated_prebuild(input [255:0] d);
        integer g;
        begin
            @(negedge clk); prebuild_order_data=d; prebuild_order_valid=1; #1; g=0;
            while(!prebuild_order_accept) begin @(posedge clk); #1; g=g+1; if(g>800) fail("prebuild risk ready timeout"); end
            @(posedge clk); @(negedge clk); prebuild_order_valid=0;
        end
    endtask

    task wait_and_compare(input [8*40-1:0] label_name);
        integer g, i;
        begin
            g=0;
            while((baseline_len < 80) || (integrated_len < 80)) begin
                @(posedge clk); #1; g=g+1; if(g>1600) fail("R01 parity packet timeout");
            end
            if (baseline_tx_payload_len !== 16'd80 && baseline_tx_payload_len !== 16'd0) fail("baseline payload length mismatch");
            if (integrated_tx_payload_len !== 16'd80 && integrated_tx_payload_len !== 16'd0) fail("integrated payload length mismatch");
            for(i=0; i<80; i=i+1) begin
                if (baseline_bytes[i] !== integrated_bytes[i]) begin
                    $display("I4_R01_BYTE_MISMATCH label=%0s index=%0d baseline=0x%02x integrated=0x%02x", label_name, i, baseline_bytes[i], integrated_bytes[i]);
                    fail("R01 byte parity mismatch");
                end
            end
            $display("I4_R01_BYTE_PARITY_PASS label=%0s bytes=80", label_name);
        end
    endtask

    task configure_risk;
        integer g;
        begin
            g=0; while(!store_init_done) begin @(posedge clk); #1; g=g+1; if(g>1200) fail("AMU init timeout"); end
            @(negedge clk);
            account_cfg_we=1; account_cfg_valid=1; account_cfg_key=32'h11112222; account_cfg_value=8'd1;
            product_cfg_we=1; product_cfg_valid=1; product_cfg_key=16'd0; product_cfg_value=8'd1;
            @(posedge clk); @(negedge clk); account_cfg_we=0; product_cfg_we=0;
            cfg_account_id=8'd1; cfg_product_id=8'd1; cfg_enabled=1'b1;
            cfg_margin_budget=64'd1000000; cfg_margin_per_contract=64'd1000;
            cfg_valid=1; #1; g=0;
            while(!cfg_ready) begin @(posedge clk); #1; g=g+1; if(g>200) fail("state cfg timeout"); end
            @(posedge clk); @(negedge clk); cfg_valid=0;
            if(!cfg_done || !cfg_ok) fail("state cfg failed");
        end
    endtask

    initial begin : test_sequence
        integer g;
        reg [255:0] order_a, order_b, order_c;
        order_type_allow_mask[`HFT_RMIC_TAIFEX_ORD_LIMIT] = 1'b1;
        tif_allow_mask[`HFT_RMIC_TAIFEX_TIF_ROD] = 1'b1;
        position_effect_allow_mask[`HFT_RMIC_TAIFEX_POS_OPEN] = 1'b1;
        position_effect_allow_mask[`HFT_RMIC_TAIFEX_POS_CLOSE] = 1'b1;

        repeat(8) @(posedge clk);
        @(negedge clk); rst_n=1'b1;
        configure_risk();

        order_a = mk_order(32'd300,32'd101000,16'd2);
        clear_capture();
        send_baseline(order_a);
        send_integrated_legacy(order_a);
        wait_and_compare("legacy");

        order_b = mk_order(32'd301,32'd102000,16'd1);
        clear_capture();
        send_baseline(order_b);
        send_integrated_prebuild(order_b);
        wait_and_compare("prebuild");

        // Fail-closed: policy rejection produces no third integrated R01.
        order_c = mk_order(32'd302,32'd103000,16'd1);
        integrated_len = 0;
        global_kill = 1'b1;
        send_integrated_prebuild(order_c);
        g=0; while(!risk_reject_valid) begin @(posedge clk); #1; g=g+1; if(g>800) fail("kill reject timeout"); end
        if(risk_reject_order_id != 32'd302 || risk_reject_reason_code != `HFT_RMIC_POLICY_REASON_KILL_SWITCH)
            fail("kill reject telemetry mismatch");
        repeat(40) @(posedge clk);
        if(integrated_len != 0) fail("rejected order emitted R01 bytes");
        @(negedge clk); risk_reject_ready=1; @(posedge clk); @(negedge clk); risk_reject_ready=0;
        $display("I4_R01_REJECT_NO_PACKET_PASS");

        if(recovery_required) fail("unexpected recovery_required");
        $display("HFT_RMIC_I4_R01_BYTE_PARITY_TB_PASS");
        $finish;
    end
endmodule
