`timescale 1ns/1ps

module tb_hft_rmic_dual_xgmii_full_system #(
    parameter integer SC4_FULL = 0,
    parameter integer SC5_LATENCY = 0,
    parameter integer SC5_MARKET_PHASE_PS = 1100
);
    localparam integer MAX_BYTES = 512;
    localparam integer DATA_WIDTH = 64;
    localparam integer KEEP_WIDTH = 8;

    localparam [47:0] LOCAL_MAC  = 48'h020000000001;
    localparam [47:0] REMOTE_MAC = 48'h020000000002;
    localparam [47:0] STATIC_REMOTE_MAC_FALLBACK = 48'h0200000000ff;
    localparam [31:0] LOCAL_IP   = 32'h0a000001;
    localparam [31:0] REMOTE_IP  = 32'h0a000002;
    localparam [15:0] UDP_PORT   = 16'd5500;
    localparam [15:0] TCP_LPORT  = 16'd9000;
    localparam [15:0] TCP_RPORT  = 16'd8000;
    localparam [31:0] LOCAL_ISN  = 32'h01020304;
    localparam [31:0] PEER_ISN   = 32'h10000020;
    localparam [15:0] TCP_CONTROL_IP_ID = 16'h3001;
    localparam [15:0] HEARTBEAT_IP_ID = 16'h3007;
    localparam [15:0] RST_IP_ID = 16'h3008;
    localparam [15:0] APP_IP_ID = 16'h3009;

    localparam [3:0] ST_CLOSED = 4'd0;
    localparam [3:0] ST_ESTABLISHED = 4'd7;

    localparam [7:0] X_IDLE  = 8'h07;
    localparam [7:0] X_START = 8'hfb;
    localparam [7:0] X_TERM  = 8'hfd;
    localparam [7:0] X_PRE   = 8'h55;
    localparam [7:0] X_SFD   = 8'hd5;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    always #3.2 clk = ~clk;

    reg market_clk = 1'b0;
    reg market_rst_n = 1'b0;
    initial begin
        if (SC5_LATENCY != 0) begin
            #(SC5_MARKET_PHASE_PS / 1000.0);
            forever #3.2 market_clk = ~market_clk;
        end else begin
            #1.1;
            forever #3.35 market_clk = ~market_clk;
        end
    end

    reg connection_enable;
    reg link_up;
    reg clear_arp_cache;
    reg heartbeat_trigger;
    reg user_disconnect;
    reg [63:0] xgmii_rxd;
    reg [7:0] xgmii_rxc;
    reg [63:0] market_xgmii_rxd;
    reg [7:0] market_xgmii_rxc;

    // I5 risk host/configuration.
    reg risk_integration_ready;
    reg risk_accounting_ready;
    reg risk_global_kill;
    reg risk_recovery_clear;
    reg [255:0] risk_order_type_allow_mask;
    reg [255:0] risk_tif_allow_mask;
    reg [255:0] risk_position_effect_allow_mask;
    reg [7:0] cfg_position_effect;
    reg risk_account_cfg_we;
    reg [3:0] risk_account_cfg_index;
    reg risk_account_cfg_valid;
    reg [31:0] risk_account_cfg_key;
    reg [7:0] risk_account_cfg_value;
    reg risk_product_cfg_we;
    reg [3:0] risk_product_cfg_index;
    reg risk_product_cfg_valid;
    reg [15:0] risk_product_cfg_key;
    reg [7:0] risk_product_cfg_value;
    reg risk_state_cfg_valid;
    wire risk_state_cfg_ready;
    reg [7:0] risk_state_cfg_account_id, risk_state_cfg_product_id;
    reg risk_state_cfg_enabled;
    reg [63:0] risk_state_cfg_margin_budget, risk_state_cfg_margin_per_contract;
    reg [15:0] risk_state_cfg_long_position, risk_state_cfg_short_position;
    reg [15:0] risk_state_cfg_pending_open_long, risk_state_cfg_pending_open_short;
    reg [15:0] risk_state_cfg_reserved_close_long, risk_state_cfg_reserved_close_short;
    wire risk_state_cfg_done, risk_state_cfg_ok;
    wire [7:0] risk_state_cfg_reason_code;
    wire risk_store_init_done;
    wire [1:0] risk_transaction_owner;
    wire risk_recovery_required;
    wire risk_reject_valid;
    wire [31:0] risk_reject_order_id;
    wire [1:0] risk_reject_reason_source;
    wire [7:0] risk_reject_reason_code;
    wire risk_exec_result_valid, risk_exec_result_ok;
    wire [1:0] risk_exec_result_reason_source;
    wire [7:0] risk_exec_result_reason_code;
    wire [31:0] risk_exec_result_order_id;
    wire [15:0] risk_exec_result_remaining_qty;
    wire risk_exec_metadata_error;
    wire risk_exec_queue_overflow;
    integer risk_exec_result_count;
    integer risk_reject_count;
    reg risk_exec_last_ok;
    reg [1:0] risk_exec_last_reason_source;
    reg [7:0] risk_exec_last_reason_code;
    reg [31:0] risk_exec_last_order_id;
    reg [15:0] risk_exec_last_remaining_qty;

    wire [63:0] xgmii_txd;
    wire [7:0] xgmii_txc;
    wire tcp_connected;
    wire network_ready;
    wire order_tx_enable;
    wire tx_ready;
    wire app_tx_enable;
    wire [3:0] runtime_state;
    wire [31:0] tx_next_seq;
    wire [31:0] rx_next_ack;
    wire [31:0] syn_tx_count;
    wire [31:0] final_ack_tx_count;
    wire [31:0] pure_ack_tx_count;
    wire [31:0] app_tx_count;
    wire [31:0] heartbeat_tx_count;
    wire [31:0] rst_tx_count;
    wire [31:0] ignored_rx_count;
    wire [31:0] runtime_error_count;
    wire tcp_payload_accept_pulse;
    wire tcp_payload_reject_pulse;
    wire heartbeat_pending;
    wire [15:0] heartbeat_payload_len;
    wire [31:0] heartbeat_request_count;
    wire [31:0] heartbeat_sent_count;
    wire [31:0] heartbeat_error_count;
    wire [15:0] app_payload_len;
    wire [31:0] app_sent_count;
    wire arp_remote_mac_valid;
    wire [47:0] arp_remote_mac;
    wire mandatory_ack_pending;
    wire [31:0] mandatory_ack_deadline_count;
    wire [31:0] ack_piggyback_count;
    wire app_wire_active;
    wire delivery_unknown;
    wire [31:0] delivery_unknown_count;
    wire [31:0] reconnect_count;
    wire [2:0] arp_state;
    wire [31:0] arp_request_count;
    wire [31:0] arp_reply_count;
    wire [31:0] arp_ignored_reply_count;
    wire [31:0] arp_timeout_count;
    wire [31:0] arp_retry_count;
    wire xgmii_rx_frame_done;
    wire xgmii_rx_frame_error;
    wire [7:0] xgmii_rx_error_code;
    wire [15:0] xgmii_rx_frame_len;
    wire xgmii_rx_fcs_ok;
    wire network_rx_frame_done;
    wire network_rx_frame_error;
    wire [7:0] network_rx_error_code;
    wire [15:0] network_rx_payload_len;
    wire rx_meta_valid;
    wire [1:0] rx_meta_frame_type;
    wire [31:0] rx_meta_tcp_seq;
    wire [31:0] rx_meta_tcp_ack;
    wire [7:0] rx_meta_tcp_flags;
    wire [15:0] rx_meta_payload_len;
    wire rx_meta_early_valid;
    wire [1:0] rx_meta_early_type;
    wire [15:0] rx_meta_early_payload_len;
    wire rx_market_early_header_valid;
    wire rx_payload_speculative_valid;
    wire [63:0] rx_payload_speculative_data;
    wire [7:0] rx_payload_speculative_keep;
    wire rx_payload_speculative_last;
    wire rx_payload_commit;
    wire rx_payload_squash;
    wire [31:0] heartbeat_builder_frame_seq_num;
    wire [31:0] heartbeat_builder_frame_ack_num;
    wire [15:0] heartbeat_builder_frame_payload_len;
    wire [31:0] app_builder_frame_seq_num;
    wire [31:0] app_builder_frame_ack_num;
    wire [15:0] app_builder_frame_payload_len;
    wire [2:0] arbiter_active_select;
    wire [31:0] arbiter_rst_packet_count;
    wire [31:0] arbiter_arp_packet_count;
    wire [31:0] arbiter_tcp_packet_count;
    wire [31:0] arbiter_heartbeat_packet_count;
    wire [31:0] arbiter_app_packet_count;
    wire xgmii_tx_frame_done;
    wire xgmii_tx_frame_error;
    wire [7:0] xgmii_tx_error_code;
    wire [15:0] xgmii_tx_frame_len;
    wire [2:0] xgmii_tx_source_select;
    wire market_rx_frame_done;
    wire market_rx_frame_error;
    wire market_rx_fcs_ok;
    wire [7:0] market_hot_error_code;
    wire market_cdc_overflow_sticky;
    wire market_cdc_src_reset_busy;
    wire market_cdc_dst_reset_busy;
    wire market_cdc_dst_record_valid;
    wire [1:0] market_cdc_dst_record_kind;
    wire round_session_ready;
    wire [3:0] round_session_state;
    wire round_app_subsystem_ready;
    wire round_strategy_order_valid_seen;
    wire round_encoder_order_accepted;
    wire round_chip_error;
    wire round_selected_book_valid;
    wire round_selected_strategy_ready;
    wire round_market_health_stale;
    wire round_market_checksum_error_seen;
    wire round_market_recovery_seen;
    wire [63:0] round_tx_data;
    wire [7:0] round_tx_keep;
    wire round_tx_valid;
    wire round_tx_last;
    wire [15:0] round_tx_payload_len;
    wire round_tx_complete;
    wire round_maintenance_disconnect_request;
    wire round_tmp_message_start_accept;
    wire [7:0] round_tmp_message_start_type;
    wire round_flow_credit_available;
    wire [15:0] round_flow_message_count;
    wire round_flow_overflow_sticky;
    wire round_maintenance_waiting_for_r05;
    integer m6_sim_cycle;
    reg m6_marker_arm;
    integer m6_app_first_cycle, m6_app_last_cycle;
    integer m6_runtime_first_cycle, m6_runtime_last_cycle;
    integer m6_direct_accept_cycle;
    integer m6_arb_first_cycle, m6_arb_last_cycle;
    integer m6_xgmii_start_cycle, m6_xgmii_term_cycle;
    integer market_cdc_commit_count;
    integer market_hot_commit_count;
    integer market_axis_last_count;
    integer market_hot_squash_count;
    reg sc5_marker_arm = 1'b0;
    realtime sc5_market_start_time;
    realtime sc5_market_commit_time;
    realtime sc5_cdc_commit_time;
    realtime sc5_cdc_final_data_time;
    realtime sc5_shadow_decision_time;
    realtime sc5_prebuild_accept_time;
    realtime sc5_risk_order_fire_time;
    realtime sc5_acct_req_time;
    realtime sc5_store_req_time;
    realtime sc5_acct_rsp_time;
    realtime sc5_store_rsp_time;
    realtime sc5_risk_accept_time;
    realtime sc5_encoder_accept_time;
    realtime sc5_app_first_time;
    realtime sc5_trading_start_time;
    real sc5_internal_ns;
    real sc5_cdc_commit_ns;
    integer sc5_internal_cycles;

    byte unsigned empty_payload [0:MAX_BYTES-1];
    byte unsigned heartbeat_payload [0:MAX_BYTES-1];
    byte unsigned l10_payload [0:MAX_BYTES-1];
    byte unsigned l30_payload [0:MAX_BYTES-1];
    byte unsigned l50_payload [0:MAX_BYTES-1];
    byte unsigned l20_expected [0:MAX_BYTES-1];
    byte unsigned l40_expected [0:MAX_BYTES-1];
    byte unsigned l60_expected [0:MAX_BYTES-1];
    byte unsigned r04_payload [0:MAX_BYTES-1];
    byte unsigned r05_payload [0:MAX_BYTES-1];
    byte unsigned l70_expected [0:MAX_BYTES-1];
    byte unsigned l80_payload [0:MAX_BYTES-1];
    byte unsigned l41_payload [0:MAX_BYTES-1];
    byte unsigned l42_expected [0:MAX_BYTES-1];
    byte unsigned market_payload [0:MAX_BYTES-1];
    byte unsigned r01_expected [0:MAX_BYTES-1];
    byte unsigned r02_fill_payload [0:MAX_BYTES-1];
    byte unsigned tcp_payload [0:MAX_BYTES-1];
    byte unsigned arp_request_frame [0:MAX_BYTES-1];
    byte unsigned arp_reply_frame [0:MAX_BYTES-1];
    byte unsigned syn_frame [0:MAX_BYTES-1];
    byte unsigned synack_frame [0:MAX_BYTES-1];
    byte unsigned final_ack_frame [0:MAX_BYTES-1];
    byte unsigned tcp_frame [0:MAX_BYTES-1];
    byte unsigned udp_frame [0:MAX_BYTES-1];
    byte unsigned ack_frame [0:MAX_BYTES-1];
    byte unsigned app_frame [0:MAX_BYTES-1];
    byte unsigned heartbeat_frame [0:MAX_BYTES-1];
    byte unsigned rst_frame [0:MAX_BYTES-1];
    byte unsigned rx_wire [0:MAX_BYTES-1];
    byte unsigned expected_wire [0:MAX_BYTES-1];
    byte unsigned got_wire [0:MAX_BYTES-1];

    integer heartbeat_len;
    integer l10_len;
    integer l30_len;
    integer l50_len;
    integer l20_len;
    integer l40_len;
    integer l60_len;
    integer r04_len;
    integer r05_len;
    integer l70_len;
    integer l80_len;
    integer l41_len;
    integer l42_len;
    integer market_len;
    integer r01_len;
    integer r02_fill_len;
    integer arp_request_len;
    integer arp_reply_len;
    integer syn_frame_len;
    integer synack_frame_len;
    integer final_ack_frame_len;
    integer tcp_frame_len;
    integer udp_frame_len;
    integer ack_frame_len;
    integer app_frame_len;
    integer heartbeat_frame_len;
    integer rst_frame_len;
    integer rx_wire_len;
    integer expected_wire_len;
    integer got_wire_len;
    reg tx_wire_done;
    integer tx_term_lane;

    hft_rmic_dual_xgmii_full_system_top_v1 #(
        .MAX_FRAME_BYTES(MAX_BYTES),
        .DATA_WIDTH(DATA_WIDTH),
        .KEEP_WIDTH(KEEP_WIDTH),
        .LOCAL_MAC(LOCAL_MAC),
        .REMOTE_MAC(STATIC_REMOTE_MAC_FALLBACK),
        .LOCAL_IP(LOCAL_IP),
        .REMOTE_IP(REMOTE_IP),
        .UDP_MARKET_PORT(UDP_PORT),
        .TCP_LOCAL_PORT(TCP_LPORT),
        .TCP_REMOTE_PORT(TCP_RPORT),
        .LOCAL_INITIAL_SEQ(LOCAL_ISN),
        .ARP_TIMEOUT_CYCLES(32'd4096),
        .ARP_MAX_RETRIES(8'd2),
        .MARKET_CDC_FIFO_DEPTH(64)
    ) dut (
        .market_rx_clk(market_clk),
        .market_rx_rst_n(market_rst_n),
        .market_xgmii_rxd(market_xgmii_rxd),
        .market_xgmii_rxc(market_xgmii_rxc),
        .trading_clk(clk),
        .trading_rst_n(rst_n),
        .connection_enable(connection_enable),
        .link_up(link_up),
        .clear_arp_cache(clear_arp_cache),
        .user_disconnect(user_disconnect),
        .trading_xgmii_rxd(xgmii_rxd),
        .trading_xgmii_rxc(xgmii_rxc),
        .trading_xgmii_txd(xgmii_txd),
        .trading_xgmii_txc(xgmii_txc),
        .risk_integration_ready(risk_integration_ready),
        .risk_accounting_ready(risk_accounting_ready),
        .risk_global_kill(risk_global_kill),
        .risk_recovery_clear(risk_recovery_clear),
        .risk_order_type_allow_mask(risk_order_type_allow_mask),
        .risk_tif_allow_mask(risk_tif_allow_mask),
        .risk_position_effect_allow_mask(risk_position_effect_allow_mask),
        .cfg_position_effect(cfg_position_effect),
        .risk_account_cfg_we(risk_account_cfg_we),
        .risk_account_cfg_index(risk_account_cfg_index),
        .risk_account_cfg_valid(risk_account_cfg_valid),
        .risk_account_cfg_key(risk_account_cfg_key),
        .risk_account_cfg_value(risk_account_cfg_value),
        .risk_product_cfg_we(risk_product_cfg_we),
        .risk_product_cfg_index(risk_product_cfg_index),
        .risk_product_cfg_valid(risk_product_cfg_valid),
        .risk_product_cfg_key(risk_product_cfg_key),
        .risk_product_cfg_value(risk_product_cfg_value),
        .risk_state_cfg_valid(risk_state_cfg_valid),
        .risk_state_cfg_ready(risk_state_cfg_ready),
        .risk_state_cfg_account_id(risk_state_cfg_account_id),
        .risk_state_cfg_product_id(risk_state_cfg_product_id),
        .risk_state_cfg_enabled(risk_state_cfg_enabled),
        .risk_state_cfg_margin_budget(risk_state_cfg_margin_budget),
        .risk_state_cfg_margin_per_contract(risk_state_cfg_margin_per_contract),
        .risk_state_cfg_long_position(risk_state_cfg_long_position),
        .risk_state_cfg_short_position(risk_state_cfg_short_position),
        .risk_state_cfg_pending_open_long(risk_state_cfg_pending_open_long),
        .risk_state_cfg_pending_open_short(risk_state_cfg_pending_open_short),
        .risk_state_cfg_reserved_close_long(risk_state_cfg_reserved_close_long),
        .risk_state_cfg_reserved_close_short(risk_state_cfg_reserved_close_short),
        .risk_state_cfg_done(risk_state_cfg_done),
        .risk_state_cfg_ok(risk_state_cfg_ok),
        .risk_state_cfg_reason_code(risk_state_cfg_reason_code),
        .risk_store_init_done(risk_store_init_done),
        .risk_transaction_owner(risk_transaction_owner),
        .risk_recovery_required(risk_recovery_required),
        .risk_reject_valid(risk_reject_valid),
        .risk_reject_order_id(risk_reject_order_id),
        .risk_reject_reason_source(risk_reject_reason_source),
        .risk_reject_reason_code(risk_reject_reason_code),
        .risk_exec_result_valid(risk_exec_result_valid),
        .risk_exec_result_ok(risk_exec_result_ok),
        .risk_exec_result_reason_source(risk_exec_result_reason_source),
        .risk_exec_result_reason_code(risk_exec_result_reason_code),
        .risk_exec_result_order_id(risk_exec_result_order_id),
        .risk_exec_result_remaining_qty(risk_exec_result_remaining_qty),
        .risk_exec_metadata_error(risk_exec_metadata_error),
        .risk_exec_queue_overflow(risk_exec_queue_overflow),
        .tcp_connected(tcp_connected),
        .network_ready(network_ready),
        .order_tx_enable(order_tx_enable),
        .tx_ready(tx_ready),
        .app_tx_enable(app_tx_enable),
        .runtime_state(runtime_state),
        .tx_next_seq(tx_next_seq),
        .rx_next_ack(rx_next_ack),
        .app_tx_count(app_tx_count),
        .syn_tx_count(syn_tx_count),
        .final_ack_tx_count(final_ack_tx_count),
        .pure_ack_tx_count(pure_ack_tx_count),
        .runtime_error_count(runtime_error_count),
        .mandatory_ack_pending(mandatory_ack_pending),
        .mandatory_ack_deadline_count(mandatory_ack_deadline_count),
        .ack_piggyback_count(ack_piggyback_count),
        .app_wire_active(app_wire_active),
        .learned_remote_mac(arp_remote_mac),
        .learned_remote_mac_valid(arp_remote_mac_valid),
        .round_session_ready(round_session_ready),
        .round_session_state(round_session_state),
        .round_tmp_message_start_accept(round_tmp_message_start_accept),
        .round_tmp_message_start_type(round_tmp_message_start_type),
        .round_flow_credit_available(round_flow_credit_available),
        .round_flow_message_count(round_flow_message_count),
        .delivery_unknown(delivery_unknown),
        .delivery_unknown_count(delivery_unknown_count),
        .reconnect_count(reconnect_count),
        .app_payload_len(app_payload_len),
        .app_sent_count(app_sent_count),
        .arp_request_count(arp_request_count),
        .arp_reply_count(arp_reply_count),
        .arp_timeout_count(arp_timeout_count),
        .arp_retry_count(arp_retry_count),
        .arbiter_arp_packet_count(arbiter_arp_packet_count),
        .arbiter_app_packet_count(arbiter_app_packet_count),
        .app_builder_frame_seq_num(app_builder_frame_seq_num),
        .app_builder_frame_ack_num(app_builder_frame_ack_num),
        .app_builder_frame_payload_len(app_builder_frame_payload_len),
        .trading_rx_frame_done(xgmii_rx_frame_done),
        .trading_rx_frame_error(xgmii_rx_frame_error),
        .xgmii_tx_frame_done(xgmii_tx_frame_done),
        .xgmii_tx_frame_error(xgmii_tx_frame_error),
        .xgmii_tx_error_code(xgmii_tx_error_code),
        .xgmii_tx_source_select(xgmii_tx_source_select),
        .market_rx_frame_done(market_rx_frame_done),
        .market_rx_frame_error(market_rx_frame_error),
        .market_rx_fcs_ok(market_rx_fcs_ok),
        .market_hot_error_code(market_hot_error_code),
        .market_cdc_overflow_sticky(market_cdc_overflow_sticky),
        .market_cdc_src_reset_busy(market_cdc_src_reset_busy),
        .market_cdc_dst_reset_busy(market_cdc_dst_reset_busy),
        .market_cdc_dst_record_valid(market_cdc_dst_record_valid),
        .market_cdc_dst_record_kind(market_cdc_dst_record_kind),
        .round_app_subsystem_ready(round_app_subsystem_ready),
        .round_selected_book_valid(round_selected_book_valid),
        .round_strategy_order_valid_seen(round_strategy_order_valid_seen),
        .round_encoder_order_accepted(round_encoder_order_accepted),
        .round_chip_error(round_chip_error),
        .round_market_health_stale(round_market_health_stale),
        .round_market_checksum_error_seen(round_market_checksum_error_seen),
        .round_market_recovery_seen(round_market_recovery_seen),
        .round_tx_data(round_tx_data),
        .round_tx_keep(round_tx_keep),
        .round_tx_valid(round_tx_valid),
        .round_tx_last(round_tx_last),
        .round_tx_payload_len(round_tx_payload_len),
        .round_tx_complete(round_tx_complete)
    );

    function automatic [15:0] fold16(input int unsigned sum_in);
        int unsigned tmp;
        begin
            tmp = sum_in;
            tmp = (tmp & 32'h0000ffff) + (tmp >> 16);
            tmp = (tmp & 32'h0000ffff) + (tmp >> 16);
            fold16 = tmp[15:0];
        end
    endfunction

    function automatic [15:0] checksum_finalize(input int unsigned sum_in);
        begin
            checksum_finalize = ~fold16(sum_in);
        end
    endfunction

    function automatic [31:0] next_crc32_byte(input [31:0] crc, input [7:0] data);
        int bit_idx;
        reg [31:0] c;
        begin
            c = crc ^ {24'd0, data};
            for (bit_idx = 0; bit_idx < 8; bit_idx = bit_idx + 1) begin
                if (c[0]) begin
                    c = (c >> 1) ^ 32'hedb88320;
                end else begin
                    c = c >> 1;
                end
            end
            next_crc32_byte = c;
        end
    endfunction

    function automatic [31:0] eth_crc32(ref byte unsigned bytes [0:MAX_BYTES-1], input integer len);
        int i;
        reg [31:0] crc;
        begin
            crc = 32'hffff_ffff;
            for (i = 0; i < len; i = i + 1) begin
                crc = next_crc32_byte(crc, bytes[i]);
            end
            eth_crc32 = ~crc;
        end
    endfunction

    task automatic clear_bytes(ref byte unsigned bytes [0:MAX_BYTES-1]);
        int i;
        begin
            for (i = 0; i < MAX_BYTES; i = i + 1) begin
                bytes[i] = 8'h00;
            end
        end
    endtask

    task automatic put16(ref byte unsigned frame [0:MAX_BYTES-1], input int offset, input bit [15:0] value);
        begin
            frame[offset] = value[15:8];
            frame[offset+1] = value[7:0];
        end
    endtask

    task automatic put32(ref byte unsigned frame [0:MAX_BYTES-1], input int offset, input bit [31:0] value);
        begin
            frame[offset] = value[31:24];
            frame[offset+1] = value[23:16];
            frame[offset+2] = value[15:8];
            frame[offset+3] = value[7:0];
        end
    endtask

    task automatic put_mac(ref byte unsigned frame [0:MAX_BYTES-1], input int offset, input bit [47:0] mac);
        begin
            frame[offset+0] = mac[47:40];
            frame[offset+1] = mac[39:32];
            frame[offset+2] = mac[31:24];
            frame[offset+3] = mac[23:16];
            frame[offset+4] = mac[15:8];
            frame[offset+5] = mac[7:0];
        end
    endtask

    function automatic [15:0] ipv4_checksum(ref byte unsigned frame [0:MAX_BYTES-1], input int ip_off);
        int unsigned sum;
        int i;
        begin
            sum = 0;
            for (i = 0; i < 20; i = i + 2) begin
                if (i != 10) begin
                    sum += {frame[ip_off+i], frame[ip_off+i+1]};
                end
            end
            ipv4_checksum = checksum_finalize(sum);
        end
    endfunction

    function automatic [15:0] tcp_checksum(
        ref byte unsigned frame [0:MAX_BYTES-1],
        input int ip_off,
        input int tcp_off,
        input int tcp_len
    );
        int unsigned sum;
        int i;
        begin
            sum = 0;
            sum += {frame[ip_off+12], frame[ip_off+13]};
            sum += {frame[ip_off+14], frame[ip_off+15]};
            sum += {frame[ip_off+16], frame[ip_off+17]};
            sum += {frame[ip_off+18], frame[ip_off+19]};
            sum += 16'h0006;
            sum += tcp_len[15:0];
            for (i = 0; i < tcp_len; i = i + 2) begin
                if ((i + 1) < tcp_len) begin
                    sum += {frame[tcp_off+i], frame[tcp_off+i+1]};
                end else begin
                    sum += {frame[tcp_off+i], 8'h00};
                end
            end
            tcp_checksum = checksum_finalize(sum);
        end
    endfunction

    task automatic build_tcp_frame(
        ref byte unsigned frame [0:MAX_BYTES-1],
        output integer frame_len,
        ref byte unsigned payload [0:MAX_BYTES-1],
        input integer payload_bytes_len,
        input bit local_to_remote,
        input bit [7:0] flags,
        input bit [31:0] seq,
        input bit [31:0] ack,
        input bit [15:0] ip_id
    );
        int i;
        int ip_len;
        int tcp_len;
        begin
            clear_bytes(frame);
            tcp_len = 20 + payload_bytes_len;
            ip_len = 20 + tcp_len;
            frame_len = 14 + ip_len;
            put_mac(frame, 0, local_to_remote ? REMOTE_MAC : LOCAL_MAC);
            put_mac(frame, 6, local_to_remote ? LOCAL_MAC : REMOTE_MAC);
            put16(frame, 12, 16'h0800);
            frame[14] = 8'h45;
            frame[15] = 8'h00;
            put16(frame, 16, ip_len[15:0]);
            put16(frame, 18, ip_id);
            put16(frame, 20, 16'h4000);
            frame[22] = 8'd64;
            frame[23] = 8'h06;
            put16(frame, 24, 16'h0000);
            put32(frame, 26, local_to_remote ? LOCAL_IP : REMOTE_IP);
            put32(frame, 30, local_to_remote ? REMOTE_IP : LOCAL_IP);
            put16(frame, 24, ipv4_checksum(frame, 14));
            put16(frame, 34, local_to_remote ? TCP_LPORT : TCP_RPORT);
            put16(frame, 36, local_to_remote ? TCP_RPORT : TCP_LPORT);
            put32(frame, 38, seq);
            put32(frame, 42, ack);
            frame[46] = 8'h50;
            frame[47] = flags;
            put16(frame, 48, 16'h4000);
            put16(frame, 50, 16'h0000);
            put16(frame, 52, 16'h0000);
            for (i = 0; i < payload_bytes_len; i = i + 1) begin
                frame[54+i] = payload[i];
            end
            put16(frame, 50, tcp_checksum(frame, 14, 34, tcp_len));
        end
    endtask

    task automatic build_udp_frame(
        ref byte unsigned frame [0:MAX_BYTES-1],
        output integer frame_len,
        ref byte unsigned payload [0:MAX_BYTES-1],
        input integer payload_bytes_len
    );
        int i;
        int ip_len;
        int udp_len;
        begin
            clear_bytes(frame);
            ip_len = 20 + 8 + payload_bytes_len;
            udp_len = 8 + payload_bytes_len;
            frame_len = 14 + ip_len;
            put_mac(frame, 0, LOCAL_MAC);
            put_mac(frame, 6, REMOTE_MAC);
            put16(frame, 12, 16'h0800);
            frame[14] = 8'h45;
            frame[15] = 8'h00;
            put16(frame, 16, ip_len[15:0]);
            put16(frame, 18, 16'h2222);
            put16(frame, 20, 16'h4000);
            frame[22] = 8'd64;
            frame[23] = 8'h11;
            put16(frame, 24, 16'h0000);
            put32(frame, 26, REMOTE_IP);
            put32(frame, 30, LOCAL_IP);
            put16(frame, 24, ipv4_checksum(frame, 14));
            put16(frame, 34, 16'd6000);
            put16(frame, 36, UDP_PORT);
            put16(frame, 38, udp_len[15:0]);
            put16(frame, 40, 16'h0000);
            for (i = 0; i < payload_bytes_len; i = i + 1) begin
                frame[42+i] = payload[i];
            end
        end
    endtask

    task automatic build_arp_request(ref byte unsigned frame [0:MAX_BYTES-1], output integer frame_len);
        begin
            clear_bytes(frame);
            frame_len = 42;
            put_mac(frame, 0, 48'hffff_ffff_ffff);
            put_mac(frame, 6, LOCAL_MAC);
            put16(frame, 12, 16'h0806);
            put16(frame, 14, 16'h0001);
            put16(frame, 16, 16'h0800);
            frame[18] = 8'h06;
            frame[19] = 8'h04;
            put16(frame, 20, 16'h0001);
            put_mac(frame, 22, LOCAL_MAC);
            put32(frame, 28, LOCAL_IP);
            put_mac(frame, 32, 48'd0);
            put32(frame, 38, REMOTE_IP);
        end
    endtask

    task automatic build_arp_reply(ref byte unsigned frame [0:MAX_BYTES-1], output integer frame_len);
        begin
            clear_bytes(frame);
            frame_len = 42;
            put_mac(frame, 0, LOCAL_MAC);
            put_mac(frame, 6, REMOTE_MAC);
            put16(frame, 12, 16'h0806);
            put16(frame, 14, 16'h0001);
            put16(frame, 16, 16'h0800);
            frame[18] = 8'h06;
            frame[19] = 8'h04;
            put16(frame, 20, 16'h0002);
            put_mac(frame, 22, REMOTE_MAC);
            put32(frame, 28, REMOTE_IP);
            put_mac(frame, 32, LOCAL_MAC);
            put32(frame, 38, LOCAL_IP);
        end
    endtask

    task automatic build_wire_frame(
        ref byte unsigned frame [0:MAX_BYTES-1],
        input integer frame_len,
        ref byte unsigned wire_bytes [0:MAX_BYTES-1],
        output integer out_len,
        input bit bad_fcs
    );
        int i;
        int padded_len;
        reg [31:0] crc;
        begin
            clear_bytes(wire_bytes);
            padded_len = (frame_len < 60) ? 60 : frame_len;
            for (i = 0; i < padded_len; i = i + 1) begin
                wire_bytes[i] = (i < frame_len) ? frame[i] : 8'h00;
            end
            crc = eth_crc32(wire_bytes, padded_len);
            if (bad_fcs) begin
                crc = crc ^ 32'h0000_0001;
            end
            wire_bytes[padded_len + 0] = crc[7:0];
            wire_bytes[padded_len + 1] = crc[15:8];
            wire_bytes[padded_len + 2] = crc[23:16];
            wire_bytes[padded_len + 3] = crc[31:24];
            out_len = padded_len + 4;
        end
    endtask

    task automatic compare_bytes(
        input string label,
        ref byte unsigned got [0:MAX_BYTES-1],
        input integer got_len,
        ref byte unsigned expected [0:MAX_BYTES-1],
        input integer exp_len
    );
        int i;
        begin
            if (got_len !== exp_len) begin
                $display("TEST_FAIL: %s length got=%0d expected=%0d", label, got_len, exp_len);
                $finish;
            end
            for (i = 0; i < exp_len; i = i + 1) begin
                if (got[i] !== expected[i]) begin
                    $display("TEST_FAIL: %s byte[%0d] got=0x%02x expected=0x%02x",
                             label, i, got[i], expected[i]);
                    $finish;
                end
            end
            $display("TEST_PASS: %s byte-accurate match len=%0d", label, exp_len);
        end
    endtask

    task automatic reset_tx_collector;
        begin
            clear_bytes(got_wire);
            got_wire_len = 0;
            tx_wire_done = 1'b0;
            tx_term_lane = -1;
        end
    endtask

    task automatic send_xgmii_word(input [63:0] data_word, input [7:0] ctrl_word);
        begin
            @(posedge clk);
            xgmii_rxd <= data_word;
            xgmii_rxc <= ctrl_word;
        end
    endtask

    task automatic drive_xgmii_frame(ref byte unsigned wire_bytes [0:MAX_BYTES-1], input integer wire_len);
        int idx;
        int lane;
        bit term_done;
        reg [63:0] data_word;
        reg [7:0] ctrl_word;
        begin
            send_xgmii_word(64'hd5555555555555fb, 8'h01);
            idx = 0;
            term_done = 1'b0;
            while (!term_done) begin
                data_word = {8{X_IDLE}};
                ctrl_word = 8'hff;
                for (lane = 0; lane < KEEP_WIDTH; lane = lane + 1) begin
                    if (idx < wire_len) begin
                        data_word[lane*8 +: 8] = wire_bytes[idx];
                        ctrl_word[lane] = 1'b0;
                        idx = idx + 1;
                    end else if (!term_done) begin
                        data_word[lane*8 +: 8] = X_TERM;
                        ctrl_word[lane] = 1'b1;
                        term_done = 1'b1;
                    end
                end
                send_xgmii_word(data_word, ctrl_word);
            end
            send_xgmii_word({8{X_IDLE}}, 8'hff);
            send_xgmii_word({8{X_IDLE}}, 8'hff);
        end
    endtask

    task automatic send_market_xgmii_word(input [63:0] data_word, input [7:0] ctrl_word);
        begin
            @(posedge market_clk);
            market_xgmii_rxd <= data_word;
            market_xgmii_rxc <= ctrl_word;
        end
    endtask

    task automatic drive_market_xgmii_frame(
        ref byte unsigned wire_bytes [0:MAX_BYTES-1],
        input integer wire_len
    );
        int idx;
        int lane;
        bit term_done;
        reg [63:0] data_word;
        reg [7:0] ctrl_word;
        begin
            send_market_xgmii_word(64'hd5555555555555fb, 8'h01);
            idx = 0;
            term_done = 1'b0;
            while (!term_done) begin
                data_word = {8{X_IDLE}};
                ctrl_word = 8'hff;
                for (lane = 0; lane < KEEP_WIDTH; lane = lane + 1) begin
                    if (idx < wire_len) begin
                        data_word[lane*8 +: 8] = wire_bytes[idx];
                        ctrl_word[lane] = 1'b0;
                        idx = idx + 1;
                    end else if (!term_done) begin
                        data_word[lane*8 +: 8] = X_TERM;
                        ctrl_word[lane] = 1'b1;
                        term_done = 1'b1;
                    end
                end
                send_market_xgmii_word(data_word, ctrl_word);
            end
            send_market_xgmii_word({8{X_IDLE}}, 8'hff);
            send_market_xgmii_word({8{X_IDLE}}, 8'hff);
        end
    endtask

    task automatic expect_next_wire(input string label, ref byte unsigned frame [0:MAX_BYTES-1], input integer frame_len);
        begin
            build_wire_frame(frame, frame_len, expected_wire, expected_wire_len, 1'b0);
            wait (tx_wire_done);
            if (xgmii_tx_frame_error) begin
                $display("TEST_FAIL: %s TX encoder error code=0x%02x", label, xgmii_tx_error_code);
                $finish;
            end
            compare_bytes(label, got_wire, got_wire_len, expected_wire, expected_wire_len);
            repeat (2) @(posedge clk);
            reset_tx_collector();
        end
    endtask

    task automatic expect_no_tx(input string label, input integer cycles);
        begin
            repeat (cycles) @(posedge clk);
            if (tx_wire_done) begin
                $display("TEST_FAIL: %s produced unexpected TX frame", label);
                $finish;
            end
            $display("TEST_PASS: %s produced no TX frame", label);
        end
    endtask

    task automatic pulse_heartbeat;
        begin
            @(negedge clk);
            heartbeat_trigger = 1'b1;
            @(negedge clk);
            heartbeat_trigger = 1'b0;
        end
    endtask

    task automatic pulse_disconnect;
        begin
            @(negedge clk);
            user_disconnect = 1'b1;
            @(negedge clk);
            user_disconnect = 1'b0;
        end
    endtask

    always @(posedge clk) begin
        if (!rst_n) begin
            risk_exec_result_count <= 0;
            risk_reject_count <= 0;
            risk_exec_last_ok <= 1'b0;
            risk_exec_last_reason_source <= 2'd0;
            risk_exec_last_reason_code <= 8'd0;
            risk_exec_last_order_id <= 32'd0;
            risk_exec_last_remaining_qty <= 16'd0;
        end else if (risk_exec_result_valid) begin
            risk_exec_result_count <= risk_exec_result_count + 1;
            risk_exec_last_ok <= risk_exec_result_ok;
            risk_exec_last_reason_source <= risk_exec_result_reason_source;
            risk_exec_last_reason_code <= risk_exec_result_reason_code;
            risk_exec_last_order_id <= risk_exec_result_order_id;
            risk_exec_last_remaining_qty <= risk_exec_result_remaining_qty;
        end
        if (rst_n && risk_reject_valid)
            risk_reject_count <= risk_reject_count + 1;
    end

    task automatic configure_risk;
        integer guard;
        begin
            guard = 0;
            while (!risk_store_init_done) begin
                @(posedge clk);
                guard = guard + 1;
                if (guard > 1200) begin
                    $display("TEST_FAIL: I5 risk AMU init timeout");
                    $finish;
                end
            end

            // Frozen XGMII app uses investor account 0x0012d687 and TXF slot 0.
            @(negedge clk);
            risk_account_cfg_index = 4'd0;
            risk_account_cfg_valid = 1'b1;
            risk_account_cfg_key = 32'h0012d687;
            risk_account_cfg_value = 8'd1;
            risk_account_cfg_we = 1'b1;
            risk_product_cfg_index = 4'd0;
            risk_product_cfg_valid = 1'b1;
            risk_product_cfg_key = 16'd0;
            risk_product_cfg_value = 8'd1;
            risk_product_cfg_we = 1'b1;
            @(posedge clk);
            @(negedge clk);
            risk_account_cfg_we = 1'b0;
            risk_product_cfg_we = 1'b0;

            risk_state_cfg_account_id = 8'd1;
            risk_state_cfg_product_id = 8'd1;
            risk_state_cfg_enabled = 1'b1;
            risk_state_cfg_margin_budget = 64'd1000000000;
            risk_state_cfg_margin_per_contract = 64'd1000;
            risk_state_cfg_long_position = 16'd0;
            risk_state_cfg_short_position = 16'd0;
            risk_state_cfg_pending_open_long = 16'd0;
            risk_state_cfg_pending_open_short = 16'd0;
            risk_state_cfg_reserved_close_long = 16'd0;
            risk_state_cfg_reserved_close_short = 16'd0;
            risk_state_cfg_valid = 1'b1;
            #1;
            guard = 0;
            while (!risk_state_cfg_ready) begin
                @(posedge clk);
                #1;
                guard = guard + 1;
                if (guard > 200) begin
                    $display("TEST_FAIL: I5 risk state config timeout");
                    $finish;
                end
            end
            @(posedge clk);
            #1;
            if (!risk_state_cfg_done || !risk_state_cfg_ok) begin
                $display("TEST_FAIL: I5 risk state config failed ok=%0d reason=%0d",
                         risk_state_cfg_ok, risk_state_cfg_reason_code);
                $finish;
            end
            @(negedge clk);
            risk_state_cfg_valid = 1'b0;
            risk_integration_ready = 1'b1;
            risk_accounting_ready = 1'b1;
            $display("I5_RISK_CONFIGURATION_PASS");
        end
    endtask

    task automatic reset_dut;
        begin
            rst_n = 1'b0;
            market_rst_n = 1'b0;
            connection_enable = 1'b0;
            link_up = 1'b0;
            clear_arp_cache = 1'b0;
            heartbeat_trigger = 1'b0;
            user_disconnect = 1'b0;
            xgmii_rxd = {8{X_IDLE}};
            xgmii_rxc = 8'hff;
            market_xgmii_rxd = {8{X_IDLE}};
            market_xgmii_rxc = 8'hff;
            risk_integration_ready = 1'b0;
            risk_accounting_ready = 1'b0;
            risk_global_kill = 1'b0;
            risk_recovery_clear = 1'b0;
            risk_order_type_allow_mask = {256{1'b1}};
            risk_tif_allow_mask = {256{1'b1}};
            risk_position_effect_allow_mask = {256{1'b1}};
            cfg_position_effect = 8'h4f; // OPEN
            risk_account_cfg_we = 1'b0;
            risk_account_cfg_index = 4'd0;
            risk_account_cfg_valid = 1'b0;
            risk_account_cfg_key = 32'd0;
            risk_account_cfg_value = 8'd0;
            risk_product_cfg_we = 1'b0;
            risk_product_cfg_index = 4'd0;
            risk_product_cfg_valid = 1'b0;
            risk_product_cfg_key = 16'd0;
            risk_product_cfg_value = 8'd0;
            risk_state_cfg_valid = 1'b0;
            risk_state_cfg_account_id = 8'd0;
            risk_state_cfg_product_id = 8'd0;
            risk_state_cfg_enabled = 1'b0;
            risk_state_cfg_margin_budget = 64'd0;
            risk_state_cfg_margin_per_contract = 64'd0;
            risk_state_cfg_long_position = 16'd0;
            risk_state_cfg_short_position = 16'd0;
            risk_state_cfg_pending_open_long = 16'd0;
            risk_state_cfg_pending_open_short = 16'd0;
            risk_state_cfg_reserved_close_long = 16'd0;
            risk_state_cfg_reserved_close_short = 16'd0;
            reset_tx_collector();
            repeat (10) @(posedge clk);
            rst_n = 1'b1;
            repeat (2) @(posedge market_clk);
            market_rst_n = 1'b1;
            wait (!market_cdc_src_reset_busy && !market_cdc_dst_reset_busy);
            configure_risk();
            if (risk_recovery_required || risk_exec_metadata_error || risk_exec_queue_overflow) begin
                $display("TEST_FAIL: I5 risk did not initialize cleanly recovery=%0d meta=%0d queue=%0d",
                         risk_recovery_required, risk_exec_metadata_error, risk_exec_queue_overflow);
                $finish;
            end
            repeat (10) @(posedge clk);
        end
    endtask

    task automatic write_ascii_payload(
        ref byte unsigned payload [0:MAX_BYTES-1],
        output integer len,
        input string text
    );
        int i;
        begin
            clear_bytes(payload);
            len = text.len();
            for (i = 0; i < len; i = i + 1) begin
                payload[i] = text.getc(i);
            end
        end
    endtask

    task automatic set_l10_payload;
        begin
            clear_bytes(l10_payload);
            l10_len = 23;
            l10_payload[0]=8'h00; l10_payload[1]=8'h14; l10_payload[2]=8'h00; l10_payload[3]=8'h00;
            l10_payload[4]=8'h00; l10_payload[5]=8'h00; l10_payload[6]=8'h00; l10_payload[7]=8'h00;
            l10_payload[8]=8'h00; l10_payload[9]=8'h01; l10_payload[10]=8'h00; l10_payload[11]=8'h02;
            l10_payload[12]=8'h0a; l10_payload[13]=8'h12; l10_payload[14]=8'h34; l10_payload[15]=8'h00;
            l10_payload[16]=8'h56; l10_payload[17]=8'h00; l10_payload[18]=8'h00; l10_payload[19]=8'h00;
            l10_payload[20]=8'h00; l10_payload[21]=8'h00; l10_payload[22]=8'hbd;
        end
    endtask

    task automatic set_l30_payload;
        begin
            clear_bytes(l30_payload);
            l30_len = 27;
            l30_payload[0]=8'h00; l30_payload[1]=8'h18; l30_payload[2]=8'h00; l30_payload[3]=8'h00;
            l30_payload[4]=8'h00; l30_payload[5]=8'h00; l30_payload[6]=8'h00; l30_payload[7]=8'h00;
            l30_payload[8]=8'h00; l30_payload[9]=8'h01; l30_payload[10]=8'h00; l30_payload[11]=8'h02;
            l30_payload[12]=8'h1e; l30_payload[13]=8'h12; l30_payload[14]=8'h34; l30_payload[15]=8'h00;
            l30_payload[16]=8'h56; l30_payload[17]=8'h00; l30_payload[18]=8'h00; l30_payload[19]=8'h03;
            l30_payload[20]=8'h00; l30_payload[21]=8'h00; l30_payload[22]=8'h00; l30_payload[23]=8'h01;
            l30_payload[24]=8'h14; l30_payload[25]=8'h00; l30_payload[26]=8'hed;
        end
    endtask

    task automatic set_l50_payload;
        begin
            clear_bytes(l50_payload);
            l50_len = 22;
            l50_payload[0]=8'h00; l50_payload[1]=8'h13; l50_payload[2]=8'h00; l50_payload[3]=8'h00;
            l50_payload[4]=8'h00; l50_payload[5]=8'h00; l50_payload[6]=8'h00; l50_payload[7]=8'h00;
            l50_payload[8]=8'h00; l50_payload[9]=8'h01; l50_payload[10]=8'h00; l50_payload[11]=8'h02;
            l50_payload[12]=8'h32; l50_payload[13]=8'h12; l50_payload[14]=8'h34; l50_payload[15]=8'h00;
            l50_payload[16]=8'h56; l50_payload[17]=8'h00; l50_payload[18]=8'h1e; l50_payload[19]=8'h00;
            l50_payload[20]=8'h64; l50_payload[21]=8'h66;
        end
    endtask

    task automatic set_l20_expected;
        begin
            clear_bytes(l20_expected);
            l20_len = 19;
            l20_expected[0]=8'h00; l20_expected[1]=8'h10; l20_expected[2]=8'h00; l20_expected[3]=8'h00;
            l20_expected[4]=8'h00; l20_expected[5]=8'h00; l20_expected[6]=8'h00; l20_expected[7]=8'h00;
            l20_expected[8]=8'h00; l20_expected[9]=8'h01; l20_expected[10]=8'h00; l20_expected[11]=8'h02;
            l20_expected[12]=8'h14; l20_expected[13]=8'h12; l20_expected[14]=8'h34; l20_expected[15]=8'h00;
            l20_expected[16]=8'h56; l20_expected[17]=8'h00; l20_expected[18]=8'hc3;
        end
    endtask

    task automatic set_l40_expected;
        begin
            clear_bytes(l40_expected);
            l40_len = 33;
            l40_expected[0]=8'h00; l40_expected[1]=8'h1e; l40_expected[2]=8'h00; l40_expected[3]=8'h00;
            l40_expected[4]=8'h00; l40_expected[5]=8'h00; l40_expected[6]=8'h00; l40_expected[7]=8'h00;
            l40_expected[8]=8'h00; l40_expected[9]=8'h01; l40_expected[10]=8'h00; l40_expected[11]=8'h02;
            l40_expected[12]=8'h28; l40_expected[13]=8'h12; l40_expected[14]=8'h34; l40_expected[15]=8'h00;
            l40_expected[16]=8'h56; l40_expected[17]=8'h00; l40_expected[18]=8'h00; l40_expected[19]=8'h03;
            l40_expected[20]=8'h12; l40_expected[21]=8'h34; l40_expected[22]=8'h00; l40_expected[23]=8'h56;
            l40_expected[24]=8'h14; l40_expected[25]=8'h04; l40_expected[26]=8'h0c; l40_expected[27]=8'h00;
            // No committed R02/R32 report exists at initial login, so L40
            // requests replay after persistent report sequence zero.
            l40_expected[28]=8'h00; l40_expected[29]=8'h00; l40_expected[30]=8'h00; l40_expected[31]=8'h00;
            l40_expected[32]=8'ha8;
        end
    endtask

    task automatic set_l60_expected;
        begin
            clear_bytes(l60_expected);
            l60_len = 19;
            l60_expected[0]=8'h00; l60_expected[1]=8'h10; l60_expected[2]=8'h00; l60_expected[3]=8'h00;
            l60_expected[4]=8'h00; l60_expected[5]=8'h00; l60_expected[6]=8'h00; l60_expected[7]=8'h00;
            l60_expected[8]=8'h00; l60_expected[9]=8'h01; l60_expected[10]=8'h00; l60_expected[11]=8'h02;
            l60_expected[12]=8'h3c; l60_expected[13]=8'h12; l60_expected[14]=8'h34; l60_expected[15]=8'h00;
            l60_expected[16]=8'h56; l60_expected[17]=8'h00; l60_expected[18]=8'heb;
        end
    endtask

    task automatic set_fixed_r04_r05_payload(
        ref byte unsigned payload [0:MAX_BYTES-1],
        output integer len,
        input byte unsigned message_type
    );
        int i;
        byte unsigned sum;
        begin
            clear_bytes(payload);
            len = 19;
            payload[0]=8'h00; payload[1]=8'h10;
            payload[2]=8'h00; payload[3]=8'h00; payload[4]=8'h00; payload[5]=8'h00;
            payload[6]=8'h00; payload[7]=8'h00; payload[8]=8'h00; payload[9]=8'h01;
            payload[10]=8'h00; payload[11]=8'h02;
            payload[12]=message_type;
            payload[13]=8'h12; payload[14]=8'h34; payload[15]=8'h00; payload[16]=8'h56;
            payload[17]=8'h00;
            sum = 8'h00;
            for (i = 0; i < 18; i = i + 1)
                sum = sum + payload[i];
            payload[18] = sum;
        end
    endtask

    task automatic make_l41_replay_report(
        input integer base,
        input integer total_len,
        input byte unsigned message_type,
        input reg [31:0] report_seq
    );
        int i;
        reg [15:0] sum;
        begin
            for (i = 0; i < total_len; i = i + 1)
                l41_payload[base+i] = 8'h00;
            l41_payload[base] = (total_len-3) >> 8;
            l41_payload[base+1] = (total_len-3) & 8'hff;
            l41_payload[base+5] = report_seq[7:0];
            l41_payload[base+12] = message_type;
            if (message_type == 8'd102) begin
                l41_payload[base+127]=report_seq[31:24];
                l41_payload[base+128]=report_seq[23:16];
                l41_payload[base+129]=report_seq[15:8];
                l41_payload[base+130]=report_seq[7:0];
            end else begin
                l41_payload[base+147]=report_seq[31:24];
                l41_payload[base+148]=report_seq[23:16];
                l41_payload[base+149]=report_seq[15:8];
                l41_payload[base+150]=report_seq[7:0];
            end
            sum = 16'd0;
            for (i = 0; i < total_len-1; i = i + 1)
                sum = sum + l41_payload[base+i];
            l41_payload[base+total_len-1] = sum[7:0];
        end
    endtask

    task automatic set_l41_r02_r32_payload;
        int i;
        integer data_len;
        reg [15:0] sum;
        begin
            clear_bytes(l41_payload);
            make_l41_replay_report(23, 132, 8'd102, 32'd1);
            make_l41_replay_report(155, 152, 8'd132, 32'd2);
            data_len = 284;
            l41_len = 23 + data_len + 1;
            l41_payload[0]=(l41_len-3)>>8;
            l41_payload[1]=(l41_len-3)&8'hff;
            l41_payload[12]=8'd41;
            l41_payload[13]=8'h12; l41_payload[14]=8'h34;
            l41_payload[15]=8'h00; l41_payload[16]=8'h56;
            l41_payload[17]=8'd0;
            l41_payload[18]=8'd1;
            l41_payload[19]=data_len>>24;
            l41_payload[20]=data_len>>16;
            l41_payload[21]=data_len>>8;
            l41_payload[22]=data_len;
            sum = 16'd0;
            for (i = 0; i < l41_len-1; i = i + 1)
                sum = sum + l41_payload[i];
            l41_payload[l41_len-1] = sum[7:0];
        end
    endtask

    task automatic set_l42_expected;
        int i;
        reg [15:0] sum;
        begin
            clear_bytes(l42_expected);
            l42_len = 19;
            l42_expected[0]=8'h00; l42_expected[1]=8'h10;
            l42_expected[2]=8'h00; l42_expected[3]=8'h00;
            l42_expected[4]=8'h00; l42_expected[5]=8'h00;
            l42_expected[6]=8'h00; l42_expected[7]=8'h00;
            l42_expected[8]=8'h00; l42_expected[9]=8'h01;
            l42_expected[10]=8'h00; l42_expected[11]=8'h02;
            l42_expected[12]=8'd42;
            l42_expected[13]=8'h12; l42_expected[14]=8'h34;
            l42_expected[15]=8'h00; l42_expected[16]=8'h56;
            l42_expected[17]=8'h00;
            sum = 16'd0;
            for (i = 0; i < 18; i = i + 1)
                sum = sum + l42_expected[i];
            l42_expected[18] = sum[7:0];
        end
    endtask

    task automatic set_l40_expected_report_seq(input reg [31:0] report_seq);
        int i;
        reg [15:0] sum;
        begin
            l40_expected[27]=report_seq[31:24];
            l40_expected[28]=report_seq[23:16];
            l40_expected[29]=report_seq[15:8];
            l40_expected[30]=report_seq[7:0];
            l40_expected[31]=8'h00;
            sum = 16'd0;
            for (i = 0; i < 32; i = i + 1)
                sum = sum + l40_expected[i];
            l40_expected[32] = sum[7:0];
        end
    endtask

    task automatic set_second_market_and_r01;
        int i;
        reg [7:0] market_xor;
        reg [15:0] r01_sum;
        begin
            // Change the best ask from 1005 to 1006 so the canonical book
            // produces one distinct post-recovery R01 rather than suppressing
            // an unchanged market snapshot.
            market_payload[64] = 8'h06;
            market_xor = 8'h00;
            for (i = 1; i < 70; i = i + 1)
                market_xor = market_xor ^ market_payload[i];
            market_payload[70] = market_xor;

            r01_expected[60]=8'h00; r01_expected[61]=8'h00;
            r01_expected[62]=8'h03; r01_expected[63]=8'hee;
            // The bridge owns a monotonic order-id counter. The first order
            // used base+0; the post-recovery transaction must use base+1.
            r01_expected[27]=8'h00; r01_expected[28]=8'h00;
            r01_expected[29]=8'h00; r01_expected[30]=8'h02;
            r01_sum = 16'd0;
            for (i = 0; i < 79; i = i + 1)
                r01_sum = r01_sum + r01_expected[i];
            r01_expected[79] = r01_sum[7:0];
        end
    endtask

    task automatic set_sell_close_market_and_r01;
        int i;
        reg [7:0] market_xor;
        reg [15:0] r01_sum;
        begin
            // Force a clean SELL-only strategy condition:
            // bid=1040 > close(1020)+threshold(10), ask=1050 prevents BUY.
            market_payload[51] = 8'h10;
            market_payload[52] = 8'h40;
            market_payload[63] = 8'h10;
            market_payload[64] = 8'h50;
            market_xor = 8'h00;
            for (i = 1; i < 70; i = i + 1)
                market_xor = market_xor ^ market_payload[i];
            market_payload[70] = market_xor;

            // Second order from a fresh scenario uses order-id 2, SELL side,
            // price 1040 and PositionEffect CLOSE.
            r01_expected[27]=8'h00; r01_expected[28]=8'h00;
            r01_expected[29]=8'h00; r01_expected[30]=8'h02;
            r01_expected[60]=8'h00; r01_expected[61]=8'h00;
            r01_expected[62]=8'h04; r01_expected[63]=8'h10;
            r01_expected[71]=8'h02;
            r01_expected[74]=8'h43;
            r01_sum = 16'd0;
            for (i = 0; i < 79; i = i + 1)
                r01_sum = r01_sum + r01_expected[i];
            r01_expected[79] = r01_sum[7:0];
        end
    endtask

    task automatic set_market_payload;
        int i;
        begin
            clear_bytes(market_payload);
            market_len = 73;
            market_payload[0]=8'h1b;  market_payload[1]=8'h32;  market_payload[2]=8'h42;  market_payload[3]=8'h00;
            market_payload[4]=8'h00;  market_payload[5]=8'h00;  market_payload[6]=8'h12;  market_payload[7]=8'h34;
            market_payload[8]=8'h56;  market_payload[9]=8'h00;  market_payload[10]=8'h01; market_payload[11]=8'h00;
            market_payload[12]=8'h00; market_payload[13]=8'h00; market_payload[14]=8'h00; market_payload[15]=8'h01;
            market_payload[16]=8'h01; market_payload[17]=8'h00; market_payload[18]=8'h61; market_payload[19]=8'h54;
            market_payload[20]=8'h58; market_payload[21]=8'h46;
            for (i = 22; i < 39; i = i + 1) begin
                market_payload[i]=8'h20;
            end
            market_payload[39]=8'h00; market_payload[40]=8'h00; market_payload[41]=8'h00; market_payload[42]=8'h02;
            market_payload[43]=8'h00; market_payload[44]=8'h30; market_payload[45]=8'h02; market_payload[46]=8'h30;
            market_payload[47]=8'h30; market_payload[48]=8'h00; market_payload[49]=8'h00; market_payload[50]=8'h00;
            market_payload[51]=8'h09; market_payload[52]=8'h90; market_payload[53]=8'h00; market_payload[54]=8'h00;
            market_payload[55]=8'h00; market_payload[56]=8'h10; market_payload[57]=8'h01; market_payload[58]=8'h31;
            market_payload[59]=8'h30; market_payload[60]=8'h00; market_payload[61]=8'h00; market_payload[62]=8'h00;
            market_payload[63]=8'h10; market_payload[64]=8'h05; market_payload[65]=8'h00; market_payload[66]=8'h00;
            market_payload[67]=8'h00; market_payload[68]=8'h12; market_payload[69]=8'h01; market_payload[70]=8'hb5;
            market_payload[71]=8'h0d; market_payload[72]=8'h0a;
        end
    endtask

    task automatic set_r01_expected;
        int i;
        reg [7:0] sum;
        begin
            clear_bytes(r01_expected);
            r01_len = 80;
            r01_expected[0]=8'h00; r01_expected[1]=8'h4d;
            r01_expected[2]=8'h00; r01_expected[3]=8'h00; r01_expected[4]=8'h00; r01_expected[5]=8'h01;
            r01_expected[6]=8'h00; r01_expected[7]=8'h00; r01_expected[8]=8'h00; r01_expected[9]=8'h01;
            r01_expected[10]=8'h00; r01_expected[11]=8'h02; r01_expected[12]=8'h65;
            r01_expected[13]=8'h12; r01_expected[14]=8'h34; r01_expected[15]=8'h00; r01_expected[16]=8'h56;
            r01_expected[17]=8'h30; r01_expected[18]=8'h56; r01_expected[19]=8'h78;
            r01_expected[20]=8'h12; r01_expected[21]=8'h34;
            r01_expected[22]="A"; r01_expected[23]="0"; r01_expected[24]="0"; r01_expected[25]="0"; r01_expected[26]="1";
            r01_expected[27]=8'h00; r01_expected[28]=8'h00; r01_expected[29]=8'h00; r01_expected[30]=8'h01;
            for (i = 31; i <= 38; i = i + 1) begin
                r01_expected[i]=8'h00;
            end
            r01_expected[39]=8'h02;
            r01_expected[40]="T"; r01_expected[41]="X"; r01_expected[42]="F";
            for (i = 43; i <= 59; i = i + 1) begin
                r01_expected[i]=8'h20;
            end
            r01_expected[60]=8'h00; r01_expected[61]=8'h00; r01_expected[62]=8'h03; r01_expected[63]=8'hed;
            r01_expected[64]=8'h00; r01_expected[65]=8'h01;
            r01_expected[66]=8'h00; r01_expected[67]=8'h12; r01_expected[68]=8'hd6; r01_expected[69]=8'h87;
            r01_expected[70]=8'h41; r01_expected[71]=8'h01; r01_expected[72]=8'h02;
            r01_expected[73]=8'h00; r01_expected[74]=8'h4f; r01_expected[75]=8'h39;
            r01_expected[76]=8'h39; r01_expected[77]=8'h39; r01_expected[78]=8'h39;
            sum = 8'h00;
            for (i = 0; i < 79; i = i + 1) begin
                sum = sum + r01_expected[i];
            end
            r01_expected[79] = sum;
        end
    endtask

    task automatic set_r02_full_fill_payload;
        integer i;
        reg [7:0] sum;
        begin
            clear_bytes(r02_fill_payload);
            r02_fill_len = 133;
            r02_fill_payload[0] = 8'h00;
            r02_fill_payload[1] = 8'h82;
            // The frozen hft_report_sequence_owner commits R02/R32 by the
            // common TMP MsgSeqNum at bytes 2..5. Scenario 10 starts from a
            // cold report owner, so the first live report must be sequence 1.
            // The prior fixture incorrectly used 2 here while ReportSeq was 1,
            // causing a GAP reject before RMIC ever saw the execution.
            r02_fill_payload[2] = 8'h00;
            r02_fill_payload[3] = 8'h00;
            r02_fill_payload[4] = 8'h00;
            r02_fill_payload[5] = 8'h01;
            r02_fill_payload[6] = 8'h01;
            r02_fill_payload[7] = 8'h02;
            r02_fill_payload[8] = 8'h03;
            r02_fill_payload[9] = 8'h04;
            r02_fill_payload[10] = 8'h00;
            r02_fill_payload[11] = 8'h5a;
            r02_fill_payload[12] = 8'h66;
            r02_fill_payload[13] = 8'h12;
            r02_fill_payload[14] = 8'h34;
            r02_fill_payload[15] = 8'h00;
            r02_fill_payload[16] = 8'h01;
            r02_fill_payload[17] = 8'h00;
            r02_fill_payload[18] = 8'h46;
            r02_fill_payload[19] = 8'h56;
            r02_fill_payload[20] = 8'h78;
            r02_fill_payload[21] = 8'h12;
            r02_fill_payload[22] = 8'h34;
            r02_fill_payload[23] = 8'h41;
            r02_fill_payload[24] = 8'h30;
            r02_fill_payload[25] = 8'h30;
            r02_fill_payload[26] = 8'h30;
            r02_fill_payload[27] = 8'h31;
            r02_fill_payload[28] = 8'h00;
            r02_fill_payload[29] = 8'h00;
            r02_fill_payload[30] = 8'h00;
            r02_fill_payload[31] = 8'h01;
            r02_fill_payload[32] = 8'h55;
            r02_fill_payload[33] = 8'h53;
            r02_fill_payload[34] = 8'h52;
            r02_fill_payload[35] = 8'h44;
            r02_fill_payload[36] = 8'h45;
            r02_fill_payload[37] = 8'h46;
            r02_fill_payload[38] = 8'h30;
            r02_fill_payload[39] = 8'h31;
            r02_fill_payload[40] = 8'h02;
            r02_fill_payload[41] = 8'h54;
            r02_fill_payload[42] = 8'h58;
            r02_fill_payload[43] = 8'h46;
            r02_fill_payload[44] = 8'h32;
            r02_fill_payload[45] = 8'h30;
            r02_fill_payload[46] = 8'h32;
            r02_fill_payload[47] = 8'h36;
            r02_fill_payload[48] = 8'h30;
            r02_fill_payload[49] = 8'h36;
            r02_fill_payload[50] = 8'h20;
            r02_fill_payload[51] = 8'h20;
            r02_fill_payload[52] = 8'h20;
            r02_fill_payload[53] = 8'h20;
            r02_fill_payload[54] = 8'h20;
            r02_fill_payload[55] = 8'h20;
            r02_fill_payload[56] = 8'h20;
            r02_fill_payload[57] = 8'h20;
            r02_fill_payload[58] = 8'h20;
            r02_fill_payload[59] = 8'h20;
            r02_fill_payload[60] = 8'h20;
            r02_fill_payload[61] = 8'h00;
            r02_fill_payload[62] = 8'h00;
            r02_fill_payload[63] = 8'h03;
            r02_fill_payload[64] = 8'hed;
            r02_fill_payload[65] = 8'h00;
            r02_fill_payload[66] = 8'h01;
            r02_fill_payload[67] = 8'h00;
            r02_fill_payload[68] = 8'h12;
            r02_fill_payload[69] = 8'hd6;
            r02_fill_payload[70] = 8'h87;
            r02_fill_payload[71] = 8'h30;
            r02_fill_payload[72] = 8'h01;
            r02_fill_payload[73] = 8'h02;
            r02_fill_payload[74] = 8'h00;
            r02_fill_payload[75] = 8'h4f;
            r02_fill_payload[76] = 8'h00;
            r02_fill_payload[77] = 8'h00;
            r02_fill_payload[78] = 8'h03;
            r02_fill_payload[79] = 8'hed;
            r02_fill_payload[80] = 8'h00;
            r02_fill_payload[81] = 8'h01;
            r02_fill_payload[82] = 8'h00;
            r02_fill_payload[83] = 8'h00;
            r02_fill_payload[84] = 8'h00;
            r02_fill_payload[85] = 8'h00;
            r02_fill_payload[86] = 8'h00;
            r02_fill_payload[87] = 8'h00;
            r02_fill_payload[88] = 8'h00;
            r02_fill_payload[89] = 8'h00;
            r02_fill_payload[90] = 8'h00;
            r02_fill_payload[91] = 8'h00;
            r02_fill_payload[92] = 8'h00;
            r02_fill_payload[93] = 8'h00;
            r02_fill_payload[94] = 8'h00;
            r02_fill_payload[95] = 8'h01;
            r02_fill_payload[96] = 8'h00;
            r02_fill_payload[97] = 8'h00;
            r02_fill_payload[98] = 8'h00;
            r02_fill_payload[99] = 8'h00;
            r02_fill_payload[100] = 8'h00;
            r02_fill_payload[101] = 8'h00;
            r02_fill_payload[102] = 8'h00;
            r02_fill_payload[103] = 8'h00;
            r02_fill_payload[104] = 8'h00;
            r02_fill_payload[105] = 8'h00;
            r02_fill_payload[106] = 8'h00;
            r02_fill_payload[107] = 8'h00;
            r02_fill_payload[108] = 8'h00;
            r02_fill_payload[109] = 8'h00;
            r02_fill_payload[110] = 8'h00;
            r02_fill_payload[111] = 8'h00;
            r02_fill_payload[112] = 8'h00;
            r02_fill_payload[113] = 8'h00;
            r02_fill_payload[114] = 8'h00;
            r02_fill_payload[115] = 8'h00;
            r02_fill_payload[116] = 8'h01;
            r02_fill_payload[117] = 8'h02;
            r02_fill_payload[118] = 8'h03;
            r02_fill_payload[119] = 8'h04;
            r02_fill_payload[120] = 8'h00;
            r02_fill_payload[121] = 8'h5a;
            r02_fill_payload[122] = 8'h04;
            r02_fill_payload[123] = 8'hab;
            r02_fill_payload[124] = 8'hcd;
            r02_fill_payload[125] = 8'hef;
            r02_fill_payload[126] = 8'h01;
            r02_fill_payload[127] = 8'h00;
            r02_fill_payload[128] = 8'h00;
            r02_fill_payload[129] = 8'h00;
            r02_fill_payload[130] = 8'h01;
            r02_fill_payload[131] = 8'h01;

            // TMP checksum is the modulo-256 sum of every byte except the
            // checksum byte itself. Derive it from the fixture instead of
            // hard-coding it so sequence/field edits cannot silently create
            // a decoder-level checksum failure.
            sum = 8'h00;
            for (i = 0; i < 132; i = i + 1)
                sum = sum + r02_fill_payload[i];
            r02_fill_payload[132] = sum;
        end
    endtask

    task automatic set_all_payloads;
        begin
            clear_bytes(empty_payload);
            write_ascii_payload(heartbeat_payload, heartbeat_len, "HBV1");
            set_l10_payload();
            set_l30_payload();
            set_l50_payload();
            set_l20_expected();
            set_l40_expected();
            set_l60_expected();
            set_fixed_r04_r05_payload(r04_payload, r04_len, 8'd104);
            set_fixed_r04_r05_payload(r05_payload, r05_len, 8'd105);
            set_l70_l80_payloads();
            set_l41_r02_r32_payload();
            set_l42_expected();
            set_market_payload();
            set_r01_expected();
            set_r02_full_fill_payload();
        end
    endtask

    task automatic run_arp_tcp_handshake(input string label);
        begin
            build_arp_request(arp_request_frame, arp_request_len);
            build_arp_reply(arp_reply_frame, arp_reply_len);
            build_tcp_frame(syn_frame, syn_frame_len, empty_payload, 0, 1'b1, 8'h02,
                            LOCAL_ISN, 32'd0, TCP_CONTROL_IP_ID);
            build_tcp_frame(final_ack_frame, final_ack_frame_len, empty_payload, 0, 1'b1, 8'h10,
                            LOCAL_ISN + 32'd1, PEER_ISN + 32'd1, TCP_CONTROL_IP_ID);
            build_tcp_frame(synack_frame, synack_frame_len, empty_payload, 0, 1'b0, 8'h12,
                            PEER_ISN, LOCAL_ISN + 32'd1, 16'h4401);

            reset_tx_collector();
            @(negedge clk);
            connection_enable = 1'b1;
            link_up = 1'b1;
            expect_next_wire({label, " ARP request"}, arp_request_frame, arp_request_len);
            if ((arbiter_arp_packet_count < 32'd1) || (arp_request_count < 32'd1)) begin
                $display("TEST_FAIL: %s did not send ARP request arb=%0d req=%0d", label, arbiter_arp_packet_count, arp_request_count);
                $finish;
            end

            build_wire_frame(arp_reply_frame, arp_reply_len, rx_wire, rx_wire_len, 1'b0);
            reset_tx_collector();
            drive_xgmii_frame(rx_wire, rx_wire_len);
            wait (arp_remote_mac_valid);
            if ((arp_remote_mac !== REMOTE_MAC) || (arp_reply_count < 32'd1)) begin
                $display("TEST_FAIL: %s ARP cache remote_mac=0x%012x reply_count=%0d", label, arp_remote_mac, arp_reply_count);
                $finish;
            end
            if (arp_remote_mac === STATIC_REMOTE_MAC_FALLBACK) begin
                $display("TEST_FAIL: %s did not replace static MAC fallback", label);
                $finish;
            end
            expect_next_wire({label, " TCP SYN"}, syn_frame, syn_frame_len);

            build_wire_frame(synack_frame, synack_frame_len, rx_wire, rx_wire_len, 1'b0);
            reset_tx_collector();
            drive_xgmii_frame(rx_wire, rx_wire_len);
            expect_next_wire({label, " TCP final ACK"}, final_ack_frame, final_ack_frame_len);
            repeat (8) @(posedge clk);
            if (!tcp_connected || !network_ready || !order_tx_enable || !tx_ready ||
                (runtime_state !== ST_ESTABLISHED) ||
                (tx_next_seq !== (LOCAL_ISN + 32'd1)) ||
                (rx_next_ack !== (PEER_ISN + 32'd1))) begin
                $display("TEST_FAIL: %s did not establish state=%0d tx=0x%08x rx=0x%08x",
                         label, runtime_state, tx_next_seq, rx_next_ack);
                $finish;
            end
            $display("TEST_PASS: %s ARP cache + TCP handshake established", label);
        end
    endtask

    task automatic send_tcp_payload_expect_ack_and_app(
        input string label,
        ref byte unsigned input_payload [0:MAX_BYTES-1],
        input integer input_len,
        ref byte unsigned expected_payload [0:MAX_BYTES-1],
        input integer expected_len
    );
        reg [31:0] seq_before;
        reg [31:0] ack_before;
        reg [31:0] expected_ack;
        begin
            seq_before = tx_next_seq;
            ack_before = rx_next_ack;
            expected_ack = ack_before + input_len[31:0];
            build_tcp_frame(tcp_frame, tcp_frame_len, input_payload, input_len, 1'b0, 8'h18,
                            ack_before, seq_before, 16'h4402);
            build_tcp_frame(ack_frame, ack_frame_len, empty_payload, 0, 1'b1, 8'h10,
                            seq_before, expected_ack, TCP_CONTROL_IP_ID);
            build_tcp_frame(app_frame, app_frame_len, expected_payload, expected_len, 1'b1, 8'h18,
                            seq_before, expected_ack, APP_IP_ID);
            build_wire_frame(tcp_frame, tcp_frame_len, rx_wire, rx_wire_len, 1'b0);
            reset_tx_collector();
            drive_xgmii_frame(rx_wire, rx_wire_len);
            expect_next_wire({label, " pure ACK"}, ack_frame, ack_frame_len);
            expect_next_wire({label, " round-chip response"}, app_frame, app_frame_len);
            repeat (8) @(posedge clk);
            if ((rx_next_ack !== expected_ack) ||
                (tx_next_seq !== (seq_before + expected_len[31:0])) ||
                (app_builder_frame_seq_num !== seq_before) ||
                (app_builder_frame_ack_num !== expected_ack) ||
                (app_builder_frame_payload_len !== expected_len[15:0])) begin
                $display("TEST_FAIL: %s runtime/app fields tx=0x%08x rx=0x%08x app_seq=0x%08x app_ack=0x%08x len=%0d",
                         label, tx_next_seq, rx_next_ack, app_builder_frame_seq_num,
                         app_builder_frame_ack_num, app_builder_frame_payload_len);
                $finish;
            end
            $display("TEST_PASS: %s updates rx_next_ack and emits runtime seq/ack app frame", label);
        end
    endtask

    task automatic send_tcp_payload_expect_ack_only(
        input string label,
        ref byte unsigned input_payload [0:MAX_BYTES-1],
        input integer input_len
    );
        reg [31:0] seq_before;
        reg [31:0] ack_before;
        reg [31:0] expected_ack;
        begin
            seq_before = tx_next_seq;
            ack_before = rx_next_ack;
            expected_ack = ack_before + input_len[31:0];
            build_tcp_frame(tcp_frame, tcp_frame_len, input_payload, input_len, 1'b0, 8'h18,
                            ack_before, seq_before, 16'h4451);
            build_tcp_frame(ack_frame, ack_frame_len, empty_payload, 0, 1'b1, 8'h10,
                            seq_before, expected_ack, TCP_CONTROL_IP_ID);
            build_wire_frame(tcp_frame, tcp_frame_len, rx_wire, rx_wire_len, 1'b0);
            reset_tx_collector();
            drive_xgmii_frame(rx_wire, rx_wire_len);
            expect_next_wire({label, " pure ACK"}, ack_frame, ack_frame_len);
            repeat (8) @(posedge clk);
            if ((rx_next_ack !== expected_ack) || (tx_next_seq !== seq_before)) begin
                $display("TEST_FAIL: %s ACK-only state tx=0x%08x rx=0x%08x expected_rx=0x%08x",
                         label, tx_next_seq, rx_next_ack, expected_ack);
                $finish;
            end
            $display("TEST_PASS: %s accepted inbound TMP without an application response", label);
        end
    endtask

    task automatic send_live_r02_fill_expect_risk(input string label);
        integer before_count;
        integer guard;
        begin
            before_count = risk_exec_result_count;
            send_tcp_payload_expect_ack_only(label, r02_fill_payload, r02_fill_len);
            guard = 0;
            while (risk_exec_result_count == before_count) begin
                @(posedge clk);
                guard = guard + 1;
                if (guard > 400) begin
                    $display("TEST_FAIL: %s no RMIC execution result owner_last=%0d owner_err=%0d owner_code=0x%02x decoder_valid=%0d live_meta=%0d commit_meta=%0d risk_commit=%0d meta_err=%0d execq_occ=%0d queue_overflow=%0d recovery=%0d",
                             label,
                             dut.u_trading_core.u_round_chip_app.u_rx_order_book.u_report_sequence_owner.last_committed_seq,
                             dut.u_trading_core.u_round_chip_app.u_rx_order_book.u_report_sequence_owner.error_valid,
                             dut.u_trading_core.u_round_chip_app.u_rx_order_book.u_report_sequence_owner.error_code,
                             dut.u_trading_core.u_round_chip_app.u_rx_order_book.decoder_order_valid,
                             dut.u_trading_core.u_round_chip_app.u_rx_order_book.live_meta_valid,
                             dut.u_trading_core.u_round_chip_app.u_rx_order_book.risk_commit_valid,
                             dut.u_trading_core.u_round_chip_app.rx_risk_commit_valid,
                             risk_exec_metadata_error,
                             dut.u_trading_core.u_round_chip_app.execq_occupancy,
                             risk_exec_queue_overflow,
                             risk_recovery_required);
                    $finish;
                end
            end
            #1;
            if (!risk_exec_last_ok ||
                (risk_exec_last_order_id !== 32'd1) ||
                (risk_exec_last_remaining_qty !== 16'd0) ||
                risk_exec_metadata_error || risk_exec_queue_overflow ||
                risk_recovery_required) begin
                $display("TEST_FAIL: %s RMIC fill result ok=%0d src=%0d code=%0d oid=%0d rem=%0d meta=%0d queue=%0d recovery=%0d",
                         label, risk_exec_last_ok, risk_exec_last_reason_source,
                         risk_exec_last_reason_code, risk_exec_last_order_id,
                         risk_exec_last_remaining_qty, risk_exec_metadata_error,
                         risk_exec_queue_overflow, risk_recovery_required);
                $finish;
            end
            $display("I5_FULL_SYSTEM_COMMITTED_FILL_PASS order_id=%0d remaining=%0d",
                     risk_exec_last_order_id, risk_exec_last_remaining_qty);
        end
    endtask

    task automatic trigger_local_r04_expect_frame(input string label);
        reg [31:0] seq_before;
        reg [31:0] ack_before;
        reg [31:0] r04_count_before;
        begin
            seq_before = tx_next_seq;
            ack_before = rx_next_ack;
            r04_count_before = dut.u_trading_core.u_round_chip_app.u_financial_encoder.sent_r04_count;
            build_tcp_frame(app_frame, app_frame_len, r04_payload, r04_len, 1'b1, 8'h18,
                            seq_before, ack_before, APP_IP_ID);
            // Accelerate only the simulation counters. The active RTL keeps
            // the configured HeartBtInt and 156.25 MHz clock contract.
            force dut.u_trading_core.u_round_chip_app.u_financial_encoder.u_tmp_session_maintenance.idle_seconds = 8'd29;
            force dut.u_trading_core.u_round_chip_app.u_financial_encoder.u_tmp_session_maintenance.subsecond_count = 28'd156249999;
            @(posedge clk); #1;
            release dut.u_trading_core.u_round_chip_app.u_financial_encoder.u_tmp_session_maintenance.idle_seconds;
            release dut.u_trading_core.u_round_chip_app.u_financial_encoder.u_tmp_session_maintenance.subsecond_count;
            reset_tx_collector();
            expect_next_wire(label, app_frame, app_frame_len);
            repeat (8) @(posedge clk);
            if ((tx_next_seq !== (seq_before + r04_len[31:0])) ||
                (rx_next_ack !== ack_before) ||
                !round_maintenance_waiting_for_r05 ||
                (dut.u_trading_core.u_round_chip_app.u_financial_encoder.sent_r04_count !== r04_count_before + 1)) begin
                $display("TEST_FAIL: %s R04 start state tx=0x%08x rx=0x%08x wait=%0d count=%0d/%0d",
                         label, tx_next_seq, rx_next_ack,
                         round_maintenance_waiting_for_r05,
                         dut.u_trading_core.u_round_chip_app.u_financial_encoder.sent_r04_count,
                         r04_count_before);
                $finish;
            end
            $display("TEST_PASS: %s emitted byte-exact R04 and armed R05 timeout on start_accept", label);
        end
    endtask

    task automatic send_udp_market_expect_r01(input string label);
        reg [31:0] seq_before;
        reg [31:0] ack_before;
        begin
            seq_before = tx_next_seq;
            ack_before = rx_next_ack;
            build_udp_frame(udp_frame, udp_frame_len, market_payload, market_len);
            build_tcp_frame(app_frame, app_frame_len, r01_expected, r01_len, 1'b1, 8'h18,
                            seq_before, ack_before, APP_IP_ID);
            build_wire_frame(udp_frame, udp_frame_len, rx_wire, rx_wire_len, 1'b0);
            reset_tx_collector();
            m6_app_first_cycle = -1; m6_app_last_cycle = -1;
            m6_runtime_first_cycle = -1; m6_runtime_last_cycle = -1;
            m6_direct_accept_cycle = -1;
            m6_arb_first_cycle = -1; m6_arb_last_cycle = -1;
            m6_xgmii_start_cycle = -1; m6_xgmii_term_cycle = -1;
            sc5_market_start_time = -1.0;
            sc5_market_commit_time = -1.0;
            sc5_cdc_commit_time = -1.0;
            sc5_cdc_final_data_time = -1.0;
            sc5_shadow_decision_time = -1.0;
            sc5_prebuild_accept_time = -1.0;
            sc5_risk_order_fire_time = -1.0;
            sc5_acct_req_time = -1.0;
            sc5_store_req_time = -1.0;
            sc5_acct_rsp_time = -1.0;
            sc5_store_rsp_time = -1.0;
            sc5_risk_accept_time = -1.0;
            sc5_encoder_accept_time = -1.0;
            sc5_app_first_time = -1.0;
            sc5_trading_start_time = -1.0;
            sc5_marker_arm = (SC5_LATENCY != 0);
            m6_marker_arm = 1'b1;
            drive_market_xgmii_frame(rx_wire, rx_wire_len);
            expect_next_wire(label, app_frame, app_frame_len);
            $display("M6_3_XGMII_RESULT label=\"%s\" route=direct app_first=%0d app_last=%0d direct_accept=%0d xgmii_start=%0d xgmii_term=%0d app_to_accept_cycles=%0d app_to_start_cycles=%0d",
                     label, m6_app_first_cycle, m6_app_last_cycle,
                     m6_direct_accept_cycle,
                     m6_xgmii_start_cycle, m6_xgmii_term_cycle,
                     m6_direct_accept_cycle - m6_app_first_cycle,
                     m6_xgmii_start_cycle - m6_app_first_cycle);
            if (SC5_LATENCY != 0) begin
                if ((sc5_market_start_time < 0.0) ||
                    (sc5_market_commit_time < 0.0) ||
                    (sc5_cdc_commit_time < 0.0) ||
                    (sc5_app_first_time < 0.0) ||
                    (sc5_trading_start_time < 0.0)) begin
                    $display("TEST_FAIL: SC5 latency marker missing market_start=%0.3f market_commit=%0.3f cdc_commit=%0.3f app_first=%0.3f trading_start=%0.3f",
                             sc5_market_start_time, sc5_market_commit_time,
                             sc5_cdc_commit_time, sc5_app_first_time,
                             sc5_trading_start_time);
                    $finish;
                end
                sc5_internal_ns = sc5_trading_start_time - sc5_market_start_time;
                sc5_cdc_commit_ns = sc5_cdc_commit_time - sc5_market_commit_time;
                sc5_internal_cycles = $rtoi((sc5_internal_ns + 6.399999) / 6.4);
                $display("SC5_DUAL_LATENCY_SAMPLE phase_ps=%0d market_start_ns=%0.3f market_commit_ns=%0.3f cdc_final_data_ns=%0.3f cdc_commit_ns=%0.3f shadow_decision_ns=%0.3f prebuild_accept_ns=%0.3f app_first_ns=%0.3f trading_start_ns=%0.3f internal_ns=%0.3f internal_cycles=%0d cdc_commit_delta_ns=%0.3f app_to_start_ns=%0.3f",
                         SC5_MARKET_PHASE_PS, sc5_market_start_time,
                         sc5_market_commit_time, sc5_cdc_final_data_time,
                         sc5_cdc_commit_time, sc5_shadow_decision_time,
                         sc5_prebuild_accept_time,
                         sc5_app_first_time, sc5_trading_start_time,
                         sc5_internal_ns, sc5_internal_cycles,
                         sc5_cdc_commit_ns,
                         sc5_trading_start_time - sc5_app_first_time);
                $display("I5_RISK_LATENCY_SAMPLE phase_ps=%0d risk_order_fire_ns=%0.3f acct_req_ns=%0.3f store_req_ns=%0.3f acct_rsp_ns=%0.3f store_rsp_ns=%0.3f risk_accept_ns=%0.3f encoder_accept_ns=%0.3f app_first_ns=%0.3f xgmii_start_ns=%0.3f",
                         SC5_MARKET_PHASE_PS,
                         sc5_risk_order_fire_time,
                         sc5_acct_req_time,
                         sc5_store_req_time,
                         sc5_acct_rsp_time,
                         sc5_store_rsp_time,
                         sc5_risk_accept_time,
                         sc5_encoder_accept_time,
                         sc5_app_first_time,
                         sc5_trading_start_time);
            end
            m6_marker_arm = 1'b0;
            sc5_marker_arm = 1'b0;
            repeat (8) @(posedge clk);
            if ((tx_next_seq !== (seq_before + r01_len[31:0])) ||
                (rx_next_ack !== ack_before) ||
                !round_selected_book_valid ||
                !round_strategy_order_valid_seen ||
                !round_encoder_order_accepted) begin
                $display("TEST_FAIL: %s status tx=0x%08x rx=0x%08x book=%0d strategy=%0d accepted=%0d app_cnt=%0d arb_app=%0d app_len=%0d builder_len=%0d",
                         label, tx_next_seq, rx_next_ack, round_selected_book_valid,
                         round_strategy_order_valid_seen, round_encoder_order_accepted,
                         app_tx_count, arbiter_app_packet_count, app_payload_len,
                         app_builder_frame_payload_len);
                $finish;
            end
            $display("TEST_PASS: %s UDP market reaches round-chip and emits runtime TCP order response", label);
        end
    endtask

    task automatic send_bad_frame_expect_no_side_effect(
        input string label,
        input bit is_tcp
    );
        reg [31:0] tx_before;
        reg [31:0] rx_before;
        reg [31:0] arp_reply_before;
        reg [31:0] app_before;
        begin
            tx_before = tx_next_seq;
            rx_before = rx_next_ack;
            arp_reply_before = arp_reply_count;
            app_before = app_tx_count;
            if (is_tcp) begin
                write_ascii_payload(tcp_payload, tcp_frame_len, "BAD-FCS-PAYLOAD");
                build_tcp_frame(tcp_frame, tcp_frame_len, tcp_payload, tcp_frame_len, 1'b0, 8'h18,
                                rx_before, tx_before, 16'h4403);
                build_wire_frame(tcp_frame, tcp_frame_len, rx_wire, rx_wire_len, 1'b1);
            end else begin
                build_udp_frame(udp_frame, udp_frame_len, market_payload, market_len);
                build_wire_frame(udp_frame, udp_frame_len, rx_wire, rx_wire_len, 1'b1);
            end
            reset_tx_collector();
            if (is_tcp) begin
                drive_xgmii_frame(rx_wire, rx_wire_len);
                wait (xgmii_rx_frame_done);
                if (!xgmii_rx_frame_error) begin
                    $display("TEST_FAIL: %s did not assert trading XGMII frame error", label);
                    $finish;
                end
            end else begin
                drive_market_xgmii_frame(rx_wire, rx_wire_len);
                wait (market_rx_frame_done);
                if (!market_rx_frame_error) begin
                    $display("TEST_FAIL: %s did not assert market XGMII frame error", label);
                    $finish;
                end
            end
            expect_no_tx(label, 140);
            if ((tx_next_seq !== tx_before) ||
                (rx_next_ack !== rx_before) ||
                (arp_reply_count !== arp_reply_before) ||
                (app_tx_count !== app_before)) begin
                $display("TEST_FAIL: %s side effect tx=0x%08x/0x%08x rx=0x%08x/0x%08x arp=%0d/%0d app=%0d/%0d",
                         label, tx_next_seq, tx_before, rx_next_ack, rx_before,
                         arp_reply_count, arp_reply_before, app_tx_count, app_before);
                $finish;
            end
            $display("TEST_PASS: %s creates no cache/state/seq/application side effect", label);
        end
    endtask

    task automatic trading_port_market_expect_no_order(input string label);
        reg [31:0] tx_before;
        reg [31:0] app_before;
        begin
            tx_before = tx_next_seq;
            app_before = app_tx_count;
            build_udp_frame(udp_frame, udp_frame_len, market_payload, market_len);
            build_wire_frame(udp_frame, udp_frame_len, rx_wire, rx_wire_len, 1'b0);
            reset_tx_collector();
            drive_xgmii_frame(rx_wire, rx_wire_len);
            wait (xgmii_rx_frame_done);
            expect_no_tx(label, 120);
            if ((tx_next_seq !== tx_before) || (app_tx_count !== app_before)) begin
                $display("TEST_FAIL: %s trading-port market frame changed order state tx=0x%08x/0x%08x app=%0d/%0d",
                         label, tx_next_seq, tx_before, app_tx_count, app_before);
                $finish;
            end
            $display("TEST_PASS: %s external market CDC is the sole active market transaction owner", label);
        end
    endtask

    task automatic back_to_back_market_expect_two_commits(input string label);
        reg [31:0] tx_before;
        reg [31:0] app_before;
        reg [7:0] market_xor;
        integer commit_before;
        integer hot_before;
        integer reject_before;
        integer wait_cycles;
        integer i;
        begin
            tx_before = tx_next_seq;
            app_before = app_tx_count;
            commit_before = market_cdc_commit_count;
            hot_before = market_hot_commit_count;
            reject_before = risk_reject_count;

            // Keep this CDC/dedup regression independent of whichever market
            // state and PositionEffect the preceding scenario left behind.
            // Scenario 10 ends with PositionEffect=CLOSE and a SELL-close
            // snapshot; the old helper only toggled one ask byte, which could
            // create a crossed book or a CLOSE order with no matching position.
            // Build a deterministic, non-crossed SELL-only snapshot and use
            // OPEN so the risk gate cannot reject it for close-position state.
            cfg_position_effect = 8'h4f; // OPEN
            market_payload[51] = 8'h10;
            market_payload[52] = 8'h41; // bid 1041 > close(1020)+threshold(10)
            market_payload[63] = 8'h10;
            market_payload[64] = 8'h50; // ask 1050, so book remains non-crossed

            // Send the exact same snapshot twice. The first must create one
            // canonical-book change/order; the second must commit through CDC
            // but produce no duplicate R01.
            market_xor = 8'h00;
            for (i = 1; i < 70; i = i + 1)
                market_xor = market_xor ^ market_payload[i];
            market_payload[70] = market_xor;
            build_udp_frame(udp_frame, udp_frame_len, market_payload, market_len);
            build_wire_frame(udp_frame, udp_frame_len, rx_wire, rx_wire_len, 1'b0);
            reset_tx_collector();
            drive_market_xgmii_frame(rx_wire, rx_wire_len);
            drive_market_xgmii_frame(rx_wire, rx_wire_len);
            wait_cycles = 0;
            while ((market_cdc_commit_count < (commit_before + 2)) && (wait_cycles < 500)) begin
                @(posedge clk);
                wait_cycles = wait_cycles + 1;
            end
            repeat (80) @(posedge clk);
            if ((market_cdc_commit_count !== (commit_before + 2)) ||
                (app_tx_count !== (app_before + 1)) ||
                (tx_next_seq !== (tx_before + r01_len)) ||
                (risk_reject_count !== reject_before) ||
                market_cdc_overflow_sticky) begin
                $display("TEST_FAIL: %s axis_last=%0d hot_commits=%0d/%0d hot_squash=%0d cdc_commits=%0d/%0d app=%0d/%0d tx=0x%08x/0x%08x risk_reject_delta=%0d reject_src=%0d reject_code=0x%02x cdc_overflow=%0d last_hot_error=0x%02x",
                         label, market_axis_last_count,
                         market_hot_commit_count, hot_before + 2, market_hot_squash_count,
                         market_cdc_commit_count, commit_before + 2,
                         app_tx_count, app_before + 1,
                         tx_next_seq, tx_before + r01_len,
                         risk_reject_count - reject_before,
                         risk_reject_reason_source, risk_reject_reason_code,
                         market_cdc_overflow_sticky, market_hot_error_code);
                $finish;
            end
            $display("TEST_PASS: %s preserved two CDC commits and the unchanged second market state produced no duplicate R01", label);
        end
    endtask

    task automatic market_source_reset_expect_no_phantom(input string label);
        reg [31:0] tx_before;
        reg [31:0] app_before;
        begin
            tx_before = tx_next_seq;
            app_before = app_tx_count;
            reset_tx_collector();
            @(negedge market_clk);
            market_rst_n = 1'b0;
            repeat (8) @(posedge market_clk);
            @(negedge market_clk);
            market_rst_n = 1'b1;
            wait (!market_cdc_src_reset_busy && !market_cdc_dst_reset_busy);
            expect_no_tx(label, 100);
            if ((tx_next_seq !== tx_before) || (app_tx_count !== app_before)) begin
                $display("TEST_FAIL: %s reset produced phantom order tx=0x%08x/0x%08x app=%0d/%0d",
                         label, tx_next_seq, tx_before, app_tx_count, app_before);
                $finish;
            end
            $display("TEST_PASS: %s source reset recovered without phantom transaction", label);
        end
    endtask

    task automatic trigger_heartbeat_expect_frame(input string label);
        reg [31:0] seq_before;
        reg [31:0] ack_before;
        begin
            seq_before = tx_next_seq;
            ack_before = rx_next_ack;
            build_tcp_frame(heartbeat_frame, heartbeat_frame_len, heartbeat_payload, heartbeat_len, 1'b1, 8'h18,
                            seq_before, ack_before, HEARTBEAT_IP_ID);
            reset_tx_collector();
            pulse_heartbeat();
            wait (heartbeat_pending);
            expect_next_wire(label, heartbeat_frame, heartbeat_frame_len);
            repeat (8) @(posedge clk);
            if (heartbeat_pending ||
                (tx_next_seq !== (seq_before + heartbeat_len[31:0])) ||
                (rx_next_ack !== ack_before) ||
                (heartbeat_builder_frame_seq_num !== seq_before) ||
                (heartbeat_builder_frame_ack_num !== ack_before) ||
                (heartbeat_builder_frame_payload_len !== heartbeat_len[15:0])) begin
                $display("TEST_FAIL: %s heartbeat state pending=%0b tx=0x%08x expected=0x%08x rx=0x%08x",
                         label, heartbeat_pending, tx_next_seq, seq_before + heartbeat_len[31:0], rx_next_ack);
                $finish;
            end
            $display("TEST_PASS: %s placeholder heartbeat scheduled through shared arbiter", label);
        end
    endtask

    task automatic disconnect_expect_rst(input string label);
        reg [31:0] seq_before;
        reg [31:0] ack_before;
        reg [31:0] seq_after_l70;
        reg [31:0] ack_after_l80;
        reg [31:0] reconnect_before;
        reg [31:0] reconnect_peer_isn;
        begin
            seq_before = tx_next_seq;
            ack_before = rx_next_ack;
            reconnect_before = reconnect_count;
            reconnect_peer_isn = PEER_ISN + 32'h0000_0100 + reconnect_before;
            seq_after_l70 = seq_before + l70_len[31:0];
            ack_after_l80 = ack_before + l80_len[31:0];
            build_tcp_frame(app_frame, app_frame_len, l70_expected, l70_len, 1'b1, 8'h18,
                            seq_before, ack_before, APP_IP_ID);
            reset_tx_collector();
            pulse_disconnect();
            expect_next_wire({label, " orderly L70"}, app_frame, app_frame_len);

            build_tcp_frame(tcp_frame, tcp_frame_len, l80_payload, l80_len, 1'b0, 8'h18,
                            ack_before, seq_after_l70, 16'h44e0);
            build_tcp_frame(rst_frame, rst_frame_len, empty_payload, 0, 1'b1, 8'h14,
                            seq_after_l70, ack_after_l80, RST_IP_ID);
            build_wire_frame(tcp_frame, tcp_frame_len, rx_wire, rx_wire_len, 1'b0);
            reset_tx_collector();
            drive_xgmii_frame(rx_wire, rx_wire_len);
            expect_next_wire(label, rst_frame, rst_frame_len);

            build_tcp_frame(syn_frame, syn_frame_len, empty_payload, 0, 1'b1, 8'h02,
                            LOCAL_ISN, 32'd0, TCP_CONTROL_IP_ID);
            expect_next_wire({label, " automatic reconnect SYN"}, syn_frame, syn_frame_len);

            build_tcp_frame(final_ack_frame, final_ack_frame_len, empty_payload, 0, 1'b1, 8'h10,
                            LOCAL_ISN + 32'd1, reconnect_peer_isn + 32'd1,
                            TCP_CONTROL_IP_ID);
            build_tcp_frame(synack_frame, synack_frame_len, empty_payload, 0, 1'b0, 8'h12,
                            reconnect_peer_isn, LOCAL_ISN + 32'd1, 16'h44f0);
            build_wire_frame(synack_frame, synack_frame_len, rx_wire, rx_wire_len, 1'b0);
            reset_tx_collector();
            drive_xgmii_frame(rx_wire, rx_wire_len);
            expect_next_wire({label, " automatic reconnect final ACK"},
                             final_ack_frame, final_ack_frame_len);
            repeat (8) @(posedge clk);
            if (!tcp_connected || !network_ready || !order_tx_enable || !tx_ready ||
                !app_tx_enable || (runtime_state !== ST_ESTABLISHED) ||
                (reconnect_count !== (reconnect_before + 32'd1)) ||
                (tx_next_seq !== (LOCAL_ISN + 32'd1)) ||
                (rx_next_ack !== (reconnect_peer_isn + 32'd1))) begin
                $display("TEST_FAIL: %s reconnect state=%0d reconnect=%0d tx=0x%08x rx=0x%08x",
                         label, runtime_state, reconnect_count, tx_next_seq, rx_next_ack);
                $finish;
            end
            if (round_session_ready) begin
                $display("TEST_FAIL: %s reconnect retained stale TMP session_ready", label);
                $finish;
            end
            send_tcp_payload_expect_ack_and_app({label, " relogin L10"},
                                                l10_payload, l10_len, l20_expected, l20_len);
            send_tcp_payload_expect_ack_and_app({label, " relogin L30"},
                                                l30_payload, l30_len, l40_expected, l40_len);
            send_tcp_payload_expect_ack_and_app({label, " relogin L50"},
                                                l50_payload, l50_len, l60_expected, l60_len);
            if (!round_session_ready) begin
                $display("TEST_FAIL: %s automatic reconnect did not complete TMP relogin", label);
                $finish;
            end
            $display("TEST_PASS: %s RST, automatic reconnect, and full TMP relogin complete", label);
        end
    endtask

    task automatic maintenance_timeout_expect_reconnect(
        input string label,
        input bit complete_relogin
    );
        reg [31:0] seq_before;
        reg [31:0] ack_before;
        reg [31:0] reconnect_before;
        reg [31:0] reconnect_peer_isn;
        begin
            seq_before = tx_next_seq;
            ack_before = rx_next_ack;
            reconnect_before = reconnect_count;
            reconnect_peer_isn = PEER_ISN + 32'h0000_0200 + reconnect_before;
            build_tcp_frame(rst_frame, rst_frame_len, empty_payload, 0, 1'b1, 8'h14,
                            seq_before, ack_before, RST_IP_ID);
            build_tcp_frame(syn_frame, syn_frame_len, empty_payload, 0, 1'b1, 8'h02,
                            LOCAL_ISN, 32'd0, TCP_CONTROL_IP_ID);

            // Seed the five-second counter one cycle before expiry. This is
            // test acceleration only; production R05_TIMEOUT_CYCLES is intact.
            force dut.u_trading_core.u_round_chip_app.u_financial_encoder.u_tmp_session_maintenance.r05_timeout_count = 30'd781249999;
            @(posedge clk); #1;
            release dut.u_trading_core.u_round_chip_app.u_financial_encoder.u_tmp_session_maintenance.r05_timeout_count;
            reset_tx_collector();
            expect_next_wire({label, " timeout RST"}, rst_frame, rst_frame_len);
            expect_next_wire({label, " automatic reconnect SYN"}, syn_frame, syn_frame_len);

            build_tcp_frame(final_ack_frame, final_ack_frame_len, empty_payload, 0, 1'b1, 8'h10,
                            LOCAL_ISN + 32'd1, reconnect_peer_isn + 32'd1,
                            TCP_CONTROL_IP_ID);
            build_tcp_frame(synack_frame, synack_frame_len, empty_payload, 0, 1'b0, 8'h12,
                            reconnect_peer_isn, LOCAL_ISN + 32'd1, 16'h44f1);
            build_wire_frame(synack_frame, synack_frame_len, rx_wire, rx_wire_len, 1'b0);
            reset_tx_collector();
            drive_xgmii_frame(rx_wire, rx_wire_len);
            expect_next_wire({label, " automatic reconnect final ACK"},
                             final_ack_frame, final_ack_frame_len);
            repeat (8) @(posedge clk);
            if (!tcp_connected || (runtime_state !== ST_ESTABLISHED) ||
                (reconnect_count !== reconnect_before + 32'd1) || round_session_ready) begin
                $display("TEST_FAIL: %s reconnect state=%0d count=%0d ready=%0d",
                         label, runtime_state, reconnect_count, round_session_ready);
                $finish;
            end
            if (complete_relogin) begin
                send_tcp_payload_expect_ack_and_app({label, " relogin L10"},
                                                    l10_payload, l10_len, l20_expected, l20_len);
                send_tcp_payload_expect_ack_and_app({label, " relogin L30"},
                                                    l30_payload, l30_len, l40_expected, l40_len);
                send_tcp_payload_expect_ack_and_app({label, " relogin L50"},
                                                    l50_payload, l50_len, l60_expected, l60_len);
                if (!round_session_ready) begin
                    $display("TEST_FAIL: %s timeout reconnect did not complete TMP relogin", label);
                    $finish;
                end
                $display("TEST_PASS: %s timeout disconnect, automatic reconnect, and relogin complete", label);
            end else begin
                $display("TEST_PASS: %s timeout disconnect and TCP reconnect complete; TMP replay relogin remains pending", label);
            end
        end
    endtask

    task automatic send_r04_and_market_contention_expect_r05_r01(input string label);
        byte unsigned inbound_frame [0:MAX_BYTES-1];
        byte unsigned inbound_wire [0:MAX_BYTES-1];
        byte unsigned market_frame [0:MAX_BYTES-1];
        byte unsigned market_wire [0:MAX_BYTES-1];
        byte unsigned expected_ack_frame [0:MAX_BYTES-1];
        byte unsigned expected_r05_frame [0:MAX_BYTES-1];
        byte unsigned expected_r01_frame [0:MAX_BYTES-1];
        integer inbound_frame_len;
        integer inbound_wire_len;
        integer market_frame_len;
        integer market_wire_len;
        integer expected_ack_len;
        integer expected_r05_len;
        integer expected_r01_len;
        reg [31:0] seq_before;
        reg [31:0] ack_before;
        reg [31:0] expected_ack;
        reg [31:0] pure_ack_before;
        reg [31:0] piggyback_before;
        begin
            seq_before = tx_next_seq;
            ack_before = rx_next_ack;
            expected_ack = ack_before + r04_len[31:0];
            pure_ack_before = pure_ack_tx_count;
            piggyback_before = ack_piggyback_count;

            build_tcp_frame(inbound_frame, inbound_frame_len,
                            r04_payload, r04_len, 1'b0, 8'h18,
                            ack_before, seq_before, 16'h4461);
            build_wire_frame(inbound_frame, inbound_frame_len,
                             inbound_wire, inbound_wire_len, 1'b0);
            build_udp_frame(market_frame, market_frame_len,
                            market_payload, market_len);
            build_wire_frame(market_frame, market_frame_len,
                             market_wire, market_wire_len, 1'b0);

            build_tcp_frame(expected_ack_frame, expected_ack_len,
                            empty_payload, 0, 1'b1, 8'h10,
                            seq_before, expected_ack, TCP_CONTROL_IP_ID);
            build_tcp_frame(expected_r05_frame, expected_r05_len,
                            r05_payload, r05_len, 1'b1, 8'h18,
                            seq_before, expected_ack, APP_IP_ID);
            build_tcp_frame(expected_r01_frame, expected_r01_len,
                            r01_expected, r01_len, 1'b1, 8'h18,
                            seq_before + r05_len[31:0], expected_ack, APP_IP_ID);

            reset_tx_collector();
            fork
                drive_xgmii_frame(inbound_wire, inbound_wire_len);
                begin
                    // Establish the inbound R04/mandatory-ACK ownership before
                    // the cut-through market candidate reaches the trading
                    // domain. This phase offset exercises pending R05 priority
                    // rather than the unrelated case where R01 wins first.
                    wait (round_tmp_message_start_accept &&
                          round_tmp_message_start_type == 8'd105);
                    drive_market_xgmii_frame(market_wire, market_wire_len);
                end
                begin
                    expect_next_wire({label, " mandatory pure ACK"},
                                     expected_ack_frame, expected_ack_len);
                    expect_next_wire({label, " R05 priority"},
                                     expected_r05_frame, expected_r05_len);
                    expect_next_wire({label, " deferred R01"},
                                     expected_r01_frame, expected_r01_len);
                end
            join

            repeat (8) @(posedge clk);
            if ((pure_ack_tx_count !== pure_ack_before + 32'd1) ||
                (ack_piggyback_count !== piggyback_before) ||
                (tx_next_seq !== seq_before + r05_len[31:0] + r01_len[31:0]) ||
                (rx_next_ack !== expected_ack)) begin
                $display("TEST_FAIL: %s ownership pure_ack=%0d/%0d piggyback=%0d/%0d tx=0x%08x rx=0x%08x",
                         label, pure_ack_tx_count, pure_ack_before,
                         ack_piggyback_count, piggyback_before,
                         tx_next_seq, rx_next_ack);
                $finish;
            end
            $display("TEST_PASS: %s preserved mandatory ACK, R05 priority, packet boundaries, and one deferred R01",
                     label);
        end
    endtask

    task automatic set_l70_l80_payloads;
        begin
            clear_bytes(l70_expected);
            l70_len = 18;
            l70_expected[0]=8'h00; l70_expected[1]=8'h0f; l70_expected[2]=8'h00; l70_expected[3]=8'h00;
            l70_expected[4]=8'h00; l70_expected[5]=8'h00; l70_expected[6]=8'h00; l70_expected[7]=8'h00;
            l70_expected[8]=8'h00; l70_expected[9]=8'h01; l70_expected[10]=8'h00; l70_expected[11]=8'h02;
            l70_expected[12]=8'h46; l70_expected[13]=8'h12; l70_expected[14]=8'h34; l70_expected[15]=8'h00;
            l70_expected[16]=8'h56; l70_expected[17]=8'hf4;

            clear_bytes(l80_payload);
            l80_len = 19;
            l80_payload[0]=8'h00; l80_payload[1]=8'h10; l80_payload[2]=8'h00; l80_payload[3]=8'h00;
            l80_payload[4]=8'h00; l80_payload[5]=8'h00; l80_payload[6]=8'h00; l80_payload[7]=8'h00;
            l80_payload[8]=8'h00; l80_payload[9]=8'h01; l80_payload[10]=8'h00; l80_payload[11]=8'h02;
            l80_payload[12]=8'h50; l80_payload[13]=8'h12; l80_payload[14]=8'h34; l80_payload[15]=8'h00;
            l80_payload[16]=8'h56; l80_payload[17]=8'h00; l80_payload[18]=8'hff;
        end
    endtask

    task automatic scenario_1_arp_handshake;
        begin
            $display("SCENARIO_1: ARP + TCP handshake");
            reset_dut();
            run_arp_tcp_handshake("Scenario 1");
        end
    endtask

    task automatic scenario_2_tcp_payload_app_response;
        begin
            $display("SCENARIO_2: TCP payload -> round-chip/application response");
            send_tcp_payload_expect_ack_and_app("Scenario 2 L10", l10_payload, l10_len, l20_expected, l20_len);
        end
    endtask

    task automatic scenario_3_udp_market_order_response;
        begin
            $display("SCENARIO_3: UDP market -> application/order response");
            send_tcp_payload_expect_ack_and_app("Scenario 3 L30 setup", l30_payload, l30_len, l40_expected, l40_len);
            send_tcp_payload_expect_ack_and_app("Scenario 3 L50 setup", l50_payload, l50_len, l60_expected, l60_len);
            if (!round_session_ready || !round_app_subsystem_ready) begin
                $display("TEST_FAIL: Scenario 3 setup did not reach session_ready session=%0d app=%0d state=0x%0h",
                         round_session_ready, round_app_subsystem_ready, round_session_state);
                $finish;
            end
            send_udp_market_expect_r01("Scenario 3 UDP market R01");
        end
    endtask

    task automatic scenario_10_risk_closed_loop;
        integer reject_before;
        begin
            $display("SCENARIO_10: market BUY OPEN -> committed R02 fill -> SELL CLOSE");
            reset_dut();
            cfg_position_effect = 8'h4f; // OPEN
            set_market_payload();
            set_r01_expected();
            set_r02_full_fill_payload();
            set_l40_expected_report_seq(32'd0);

            run_arp_tcp_handshake("Scenario 10");
            send_tcp_payload_expect_ack_and_app("Scenario 10 L10",
                                                l10_payload, l10_len, l20_expected, l20_len);
            send_tcp_payload_expect_ack_and_app("Scenario 10 L30",
                                                l30_payload, l30_len, l40_expected, l40_len);
            send_tcp_payload_expect_ack_and_app("Scenario 10 L50",
                                                l50_payload, l50_len, l60_expected, l60_len);
            if (!round_session_ready || !round_app_subsystem_ready) begin
                $display("TEST_FAIL: Scenario 10 session setup ready=%0d app=%0d",
                         round_session_ready, round_app_subsystem_ready);
                $finish;
            end

            reject_before = risk_reject_count;
            send_udp_market_expect_r01("Scenario 10 BUY OPEN R01");
            if (risk_reject_count != reject_before) begin
                $display("TEST_FAIL: Scenario 10 BUY OPEN was risk rejected");
                $finish;
            end

            send_live_r02_fill_expect_risk("Scenario 10 live R02 full fill");
            if (dut.u_trading_core.u_round_chip_app.rx_last_committed_report_seq !== 32'd1) begin
                $display("TEST_FAIL: Scenario 10 committed report seq=%0d expected=1",
                         dut.u_trading_core.u_round_chip_app.rx_last_committed_report_seq);
                $finish;
            end

            // Only a real successful EX2CL fill creates long_position=1.
            // Switch the next order metadata to CLOSE and force a SELL-only
            // market snapshot. If the fill did not mutate the shared state,
            // this order must fail CLOSE_LONG_INSUFFICIENT instead of emitting R01.
            cfg_position_effect = 8'h43; // CLOSE
            set_sell_close_market_and_r01();
            reject_before = risk_reject_count;
            send_udp_market_expect_r01("Scenario 10 SELL CLOSE R01");
            if (risk_reject_count != reject_before ||
                risk_recovery_required || risk_exec_metadata_error ||
                risk_exec_queue_overflow) begin
                $display("TEST_FAIL: Scenario 10 SELL CLOSE risk state reject_delta=%0d recovery=%0d meta=%0d queue=%0d",
                         risk_reject_count-reject_before, risk_recovery_required,
                         risk_exec_metadata_error, risk_exec_queue_overflow);
                $finish;
            end
            if (dut.u_trading_core.u_round_chip_app.u_decoder_encoder_bridge.order_id_counter !== 32'd2) begin
                $display("TEST_FAIL: Scenario 10 order-id counter=%0d expected=2",
                         dut.u_trading_core.u_round_chip_app.u_decoder_encoder_bridge.order_id_counter);
                $finish;
            end
            $display("I5_FULL_SYSTEM_FILL_TO_CLOSE_PASS");
            $display("TEST_PASS: Scenario 10 full bidirectional HFT+RMIC risk loop complete");
        end
    endtask

    task automatic scenario_4_bad_frame_drop;
        begin
            $display("SCENARIO_4: bad-FCS / checksum failure drop");
            send_bad_frame_expect_no_side_effect("Scenario 4 bad-FCS TCP", 1'b1);
            send_bad_frame_expect_no_side_effect("Scenario 4 bad-FCS UDP", 1'b0);
        end
    endtask

    task automatic scenario_5_heartbeat;
        begin
            $display("SCENARIO_5: heartbeat");
            $display("HEARTBEAT_PAYLOAD_SOURCE: simulation-only placeholder payload 'HBV1'; not official TAIFEX/TWSE heartbeat protocol.");
            trigger_heartbeat_expect_frame("Scenario 5 heartbeat");
        end
    endtask

    task automatic scenario_6_disconnect_rst;
        begin
            $display("SCENARIO_6: disconnect / RST");
            disconnect_expect_rst("Scenario 6 active disconnect RST+ACK");
        end
    endtask

    task automatic scenario_7_combined_smoke;
        begin
            $display("SCENARIO_7: combined smoke test");
            reset_dut();
            run_arp_tcp_handshake("Scenario 7 smoke");
            send_tcp_payload_expect_ack_and_app("Scenario 7 smoke L10", l10_payload, l10_len, l20_expected, l20_len);
            send_tcp_payload_expect_ack_and_app("Scenario 7 smoke L30", l30_payload, l30_len, l40_expected, l40_len);
            send_tcp_payload_expect_ack_and_app("Scenario 7 smoke L50", l50_payload, l50_len, l60_expected, l60_len);
            send_udp_market_expect_r01("Scenario 7 smoke UDP market");
            trigger_heartbeat_expect_frame("Scenario 7 smoke heartbeat");
            disconnect_expect_rst("Scenario 7 smoke disconnect");
            $display("TEST_PASS: Scenario 7 combined smoke flow completed");
        end
    endtask

    task automatic scenario_8_tmp_maintenance;
        begin
            $display("SCENARIO_8: formal TMP R04/R05 maintenance");
            reset_dut();
            run_arp_tcp_handshake("Scenario 8 maintenance");
            send_tcp_payload_expect_ack_and_app("Scenario 8 L10", l10_payload, l10_len, l20_expected, l20_len);
            send_tcp_payload_expect_ack_and_app("Scenario 8 L30", l30_payload, l30_len, l40_expected, l40_len);
            send_tcp_payload_expect_ack_and_app("Scenario 8 L50", l50_payload, l50_len, l60_expected, l60_len);
            if (!dut.u_trading_core.u_round_chip_app.u_financial_encoder.u_tmp_session_rate_limiter.limit_configured ||
                (dut.u_trading_core.u_round_chip_app.u_financial_encoder.u_tmp_session_rate_limiter.active_limit !== 16'd100) ||
                (round_flow_message_count !== 16'd2) || !round_flow_credit_available) begin
                $display("TEST_FAIL: Scenario 8 flow config configured=%0d limit=%0d count=%0d credit=%0d",
                         dut.u_trading_core.u_round_chip_app.u_financial_encoder.u_tmp_session_rate_limiter.limit_configured,
                         dut.u_trading_core.u_round_chip_app.u_financial_encoder.u_tmp_session_rate_limiter.active_limit,
                         round_flow_message_count, round_flow_credit_available);
                $finish;
            end
            $display("TEST_PASS: Scenario 8 L20/L40 counted, L60 excluded, and L50 limit applied");

            // Flow 1: peer R04 is acknowledged by an exact outbound R05.
            send_tcp_payload_expect_ack_and_app("Scenario 8 inbound R04", r04_payload, r04_len,
                                                r05_payload, r05_len);

            // Flow 2: local R04 starts on wire, then a matching inbound R05
            // clears the maintenance deadline without producing another TMP response.
            trigger_local_r04_expect_frame("Scenario 8 outbound R04");
            send_tcp_payload_expect_ack_only("Scenario 8 matching inbound R05",
                                             r05_payload, r05_len);
            if (round_maintenance_waiting_for_r05) begin
                $display("TEST_FAIL: Scenario 8 matching R05 did not clear maintenance wait");
                $finish;
            end
            $display("TEST_PASS: Scenario 8 inbound R04/R05 and outbound R04/inbound R05 are independent");

            // Flow 3: a second local R04 receives no R05 and therefore drives
            // SC1 disconnect, reconnect, and full SC2A relogin.
            trigger_local_r04_expect_frame("Scenario 8 timeout outbound R04");
            maintenance_timeout_expect_reconnect("Scenario 8 missing R05", 1'b1);
        end
    endtask

    task automatic scenario_9_sc4_continuous_recovery;
        begin
            $display("SCENARIO_9: SC4 continuous connection/session/replay/order recovery");
            reset_dut();
            set_l40_expected_report_seq(32'd0);
            run_arp_tcp_handshake("Scenario 9 initial");
            send_tcp_payload_expect_ack_and_app("Scenario 9 initial L10",
                                                l10_payload, l10_len, l20_expected, l20_len);
            send_tcp_payload_expect_ack_and_app("Scenario 9 initial L30",
                                                l30_payload, l30_len, l40_expected, l40_len);
            send_tcp_payload_expect_ack_and_app("Scenario 9 initial L50",
                                                l50_payload, l50_len, l60_expected, l60_len);
            if (!round_session_ready ||
                (dut.u_trading_core.u_round_chip_app.rx_last_committed_report_seq !== 32'd0)) begin
                $display("TEST_FAIL: Scenario 9 initial session/report owner ready=%0d seq=%0d",
                         round_session_ready,
                         dut.u_trading_core.u_round_chip_app.rx_last_committed_report_seq);
                $finish;
            end
            // Exercise mandatory ACK, R05 and R01 packet-boundary contention
            // in the active dual-port composition. R05 must keep its encoder
            // priority, the pure ACK must not be canceled after its deadline,
            // and the R01 may start only after the prior frame completes.
            send_r04_and_market_contention_expect_r05_r01(
                "Scenario 9 inbound R04 plus market");

            // Exercise the remaining formal maintenance flows in the same
            // live connection before the recovery/replay sequence.
            trigger_local_r04_expect_frame("Scenario 9 outbound R04");
            send_tcp_payload_expect_ack_only("Scenario 9 matching inbound R05",
                                             r05_payload, r05_len);
            trigger_local_r04_expect_frame("Scenario 9 timeout outbound R04");
            maintenance_timeout_expect_reconnect("Scenario 9 missing R05", 1'b0);

            if (round_session_ready ||
                (dut.u_trading_core.u_round_chip_app.rx_last_committed_report_seq !== 32'd0)) begin
                $display("TEST_FAIL: Scenario 9 reconnect state ready=%0d seq=%0d",
                         round_session_ready,
                         dut.u_trading_core.u_round_chip_app.rx_last_committed_report_seq);
                $finish;
            end

            send_tcp_payload_expect_ack_and_app("Scenario 9 relogin L10",
                                                l10_payload, l10_len, l20_expected, l20_len);
            send_tcp_payload_expect_ack_and_app("Scenario 9 relogin L30/N=0",
                                                l30_payload, l30_len, l40_expected, l40_len);
            send_tcp_payload_expect_ack_and_app("Scenario 9 L41 R02/R32 -> L42",
                                                l41_payload, l41_len, l42_expected, l42_len);
            repeat (8) @(posedge clk);
            if ((dut.u_trading_core.u_round_chip_app.rx_last_committed_report_seq !== 32'd2) ||
                dut.u_trading_core.u_round_chip_app.rx_replay_error) begin
                $display("TEST_FAIL: Scenario 9 replay owner seq=%0d error=%0d code=0x%02x",
                         dut.u_trading_core.u_round_chip_app.rx_last_committed_report_seq,
                         dut.u_trading_core.u_round_chip_app.rx_replay_error,
                         dut.u_trading_core.u_round_chip_app.rx_replay_error_code);
                $finish;
            end
            send_tcp_payload_expect_ack_and_app("Scenario 9 post-replay L50",
                                                l50_payload, l50_len, l60_expected, l60_len);
            if (!round_session_ready) begin
                $display("TEST_FAIL: Scenario 9 replay relogin did not reach session ready");
                $finish;
            end

            // A second reconnect must preserve the committed owner and put N=2
            // into the next L40 request rather than restarting from zero.
            set_l40_expected_report_seq(32'd2);
            disconnect_expect_rst("Scenario 9 persistent sequence reconnect");
            if ((dut.u_trading_core.u_round_chip_app.rx_last_committed_report_seq !== 32'd2) ||
                !round_session_ready) begin
                $display("TEST_FAIL: Scenario 9 persistent owner after reconnect seq=%0d ready=%0d",
                         dut.u_trading_core.u_round_chip_app.rx_last_committed_report_seq,
                         round_session_ready);
                $finish;
            end
            if (dut.u_trading_core.u_round_chip_app.u_decoder_encoder_bridge.order_id_counter !== 32'd1) begin
                $display("TEST_FAIL: Scenario 9 duplicate legacy intent changed order-id counter to %0d before second market",
                         dut.u_trading_core.u_round_chip_app.u_decoder_encoder_bridge.order_id_counter);
                $finish;
            end

            set_second_market_and_r01();
            send_udp_market_expect_r01("Scenario 9 post-recovery market R01");
            if (dut.u_trading_core.u_round_chip_app.u_decoder_encoder_bridge.order_id_counter !== 32'd2) begin
                $display("TEST_FAIL: Scenario 9 second market order-id counter=%0d expected=2",
                         dut.u_trading_core.u_round_chip_app.u_decoder_encoder_bridge.order_id_counter);
                $finish;
            end
            $display("TEST_PASS: Scenario 9 continuous connection/session/replay/order recovery complete");
        end
    endtask

    always @(posedge clk) begin
        int lane_idx;
        bit term_seen_this_word;
        if (!rst_n) begin
            got_wire_len <= 0;
            tx_wire_done <= 1'b0;
            tx_term_lane <= -1;
        end else if (!tx_wire_done) begin
            if ((xgmii_txc[0] === 1'b1) && (xgmii_txd[7:0] === X_START)) begin
                if ((xgmii_txc !== 8'h01) ||
                    (xgmii_txd[15:8] !== X_PRE) ||
                    (xgmii_txd[23:16] !== X_PRE) ||
                    (xgmii_txd[31:24] !== X_PRE) ||
                    (xgmii_txd[39:32] !== X_PRE) ||
                    (xgmii_txd[47:40] !== X_PRE) ||
                    (xgmii_txd[55:48] !== X_PRE) ||
                    (xgmii_txd[63:56] !== X_SFD)) begin
                    $display("TEST_FAIL: E2E TX bad start data=0x%016x ctrl=0x%02x", xgmii_txd, xgmii_txc);
                    $finish;
                end
            end else if ((xgmii_txc === 8'hff) && (xgmii_txd === {8{X_IDLE}})) begin
                // Idle.
            end else begin
                term_seen_this_word = 1'b0;
                for (lane_idx = 0; lane_idx < KEEP_WIDTH; lane_idx = lane_idx + 1) begin
                    if (!term_seen_this_word) begin
                        if (xgmii_txc[lane_idx] == 1'b0) begin
                            got_wire[got_wire_len] = xgmii_txd[lane_idx*8 +: 8];
                            got_wire_len = got_wire_len + 1;
                        end else if (xgmii_txd[lane_idx*8 +: 8] == X_TERM) begin
                            tx_term_lane = lane_idx;
                            tx_wire_done <= 1'b1;
                            term_seen_this_word = 1'b1;
                        end else begin
                            $display("TEST_FAIL: E2E TX unexpected control lane=%0d value=0x%02x",
                                     lane_idx, xgmii_txd[lane_idx*8 +: 8]);
                            $finish;
                        end
                    end else begin
                        if ((xgmii_txc[lane_idx] !== 1'b1) ||
                            (xgmii_txd[lane_idx*8 +: 8] !== X_IDLE)) begin
                            $display("TEST_FAIL: E2E TX post-terminate lane %0d is not idle", lane_idx);
                            $finish;
                        end
                    end
                end
            end
        end
    end

    always @(posedge market_clk) begin
        if (!market_rst_n) begin
            market_hot_commit_count <= 0;
            market_axis_last_count <= 0;
            market_hot_squash_count <= 0;
        end else begin
            if (sc5_marker_arm && (sc5_market_start_time < 0.0) &&
                (market_xgmii_rxc[0] === 1'b1) &&
                (market_xgmii_rxd[7:0] === X_START))
                sc5_market_start_time = $realtime;
            if (sc5_marker_arm && (sc5_market_commit_time < 0.0) && dut.market_commit)
                sc5_market_commit_time = $realtime;
            if (dut.market_axis_valid && dut.market_axis_last)
                market_axis_last_count <= market_axis_last_count + 1;
            if (dut.market_commit)
                market_hot_commit_count <= market_hot_commit_count + 1;
            if (dut.market_squash)
                market_hot_squash_count <= market_hot_squash_count + 1;
        end
    end

    always @(posedge clk) begin
        if (!rst_n)
            market_cdc_commit_count <= 0;
        else if (market_cdc_dst_record_valid && (market_cdc_dst_record_kind == 2'b01))
            market_cdc_commit_count <= market_cdc_commit_count + 1;

        if (rst_n && sc5_marker_arm) begin
            if ((sc5_cdc_final_data_time < 0.0) && dut.trading_spec_valid &&
                dut.trading_spec_last)
                sc5_cdc_final_data_time = $realtime;
            if ((sc5_cdc_commit_time < 0.0) && market_cdc_dst_record_valid &&
                (market_cdc_dst_record_kind == 2'b01))
                sc5_cdc_commit_time = $realtime;
            if ((sc5_shadow_decision_time < 0.0) &&
                dut.u_trading_core.u_round_chip_app.spec_shadow_decision_valid)
                sc5_shadow_decision_time = $realtime;
            if ((sc5_prebuild_accept_time < 0.0) &&
                dut.u_trading_core.u_round_chip_app.prebuild_direct_accept)
                sc5_prebuild_accept_time = $realtime;
            if ((sc5_risk_order_fire_time < 0.0) &&
                dut.u_trading_core.u_round_chip_app.risk_source_valid &&
                dut.u_trading_core.u_round_chip_app.risk_source_ready)
                sc5_risk_order_fire_time = $realtime;
            if ((sc5_acct_req_time < 0.0) &&
                dut.u_trading_core.u_round_chip_app.u_i5_risk.cl_acct_req_valid &&
                dut.u_trading_core.u_round_chip_app.u_i5_risk.cl_acct_req_ready)
                sc5_acct_req_time = $realtime;
            if ((sc5_store_req_time < 0.0) &&
                dut.u_trading_core.u_round_chip_app.u_i5_risk.cl_store_req_valid &&
                dut.u_trading_core.u_round_chip_app.u_i5_risk.cl_store_req_ready)
                sc5_store_req_time = $realtime;
            if ((sc5_acct_rsp_time < 0.0) &&
                dut.u_trading_core.u_round_chip_app.u_i5_risk.cl_acct_rsp_valid &&
                dut.u_trading_core.u_round_chip_app.u_i5_risk.cl_acct_rsp_ready)
                sc5_acct_rsp_time = $realtime;
            if ((sc5_store_rsp_time < 0.0) &&
                dut.u_trading_core.u_round_chip_app.u_i5_risk.cl_store_rsp_valid &&
                dut.u_trading_core.u_round_chip_app.u_i5_risk.cl_store_rsp_ready)
                sc5_store_rsp_time = $realtime;
            if ((sc5_risk_accept_time < 0.0) &&
                dut.u_trading_core.u_round_chip_app.risk_accepted_valid)
                sc5_risk_accept_time = $realtime;
            if ((sc5_encoder_accept_time < 0.0) &&
                dut.u_trading_core.u_round_chip_app.risk_accepted_valid &&
                dut.u_trading_core.u_round_chip_app.encoder_strategy_order_ready)
                sc5_encoder_accept_time = $realtime;
            if ((sc5_app_first_time < 0.0) && round_tx_valid)
                sc5_app_first_time = $realtime;
            if ((sc5_trading_start_time < 0.0) &&
                (xgmii_txc[0] === 1'b1) && (xgmii_txd[7:0] === X_START))
                sc5_trading_start_time = $realtime;
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            m6_sim_cycle <= 0;
            m6_marker_arm <= 1'b0;
        end else begin
            m6_sim_cycle <= m6_sim_cycle + 1;
            if (m6_marker_arm) begin
                if ((m6_app_first_cycle < 0) && round_tx_valid)
                    m6_app_first_cycle <= m6_sim_cycle;
                if (round_tx_valid && dut.u_trading_core.round_app_ready && round_tx_last)
                    m6_app_last_cycle <= m6_sim_cycle;
                if ((m6_runtime_first_cycle < 0) && dut.u_trading_core.app_tvalid_raw)
                    m6_runtime_first_cycle <= m6_sim_cycle;
                if ((m6_direct_accept_cycle < 0) && dut.u_trading_core.stream_start_accept)
                    m6_direct_accept_cycle <= m6_sim_cycle;
                if (dut.u_trading_core.app_tvalid_raw && dut.u_trading_core.app_tready_raw && dut.u_trading_core.app_tlast)
                    m6_runtime_last_cycle <= m6_sim_cycle;
                if ((m6_arb_first_cycle < 0) && dut.u_trading_core.arb_tvalid && dut.u_trading_core.arb_tready)
                    m6_arb_first_cycle <= m6_sim_cycle;
                if (dut.u_trading_core.arb_tvalid && dut.u_trading_core.arb_tready && dut.u_trading_core.arb_tlast)
                    m6_arb_last_cycle <= m6_sim_cycle;
                if ((m6_xgmii_start_cycle < 0) && (xgmii_txc[0] === 1'b1) &&
                    (xgmii_txd[7:0] === X_START))
                    m6_xgmii_start_cycle <= m6_sim_cycle;
                if (xgmii_tx_frame_done)
                    m6_xgmii_term_cycle <= m6_sim_cycle;
            end
        end
    end

    initial begin
        fork
            begin
                #1200000;
                $display("TEST_FAIL: tb_hft_dual_xgmii_full_system timeout state=%0d tx=0x%08x rx=0x%08x source=%0d market_last=%0d market_commit=%0d cdc_commit=%0d cdc_busy=%0d/%0d",
                         runtime_state, tx_next_seq, rx_next_ack, xgmii_tx_source_select,
                         market_axis_last_count, market_hot_commit_count,
                         market_cdc_commit_count, market_cdc_src_reset_busy,
                         market_cdc_dst_reset_busy);
                $finish;
            end
        join_none

        $display("E2E_SCOPE: local Vivado XGMII-level simulation only; no PCS/PMA, QSFP, U50, AAT, Vitis, xo/xclbin, or official conformance.");
        set_all_payloads();

        if (SC5_LATENCY != 0) begin
            scenario_1_arp_handshake();
            scenario_2_tcp_payload_app_response();
            scenario_3_udp_market_order_response();
        end else if (SC4_FULL != 0) begin
            scenario_9_sc4_continuous_recovery();
            back_to_back_market_expect_two_commits("Scenario 9 back-to-back market CDC");
            market_source_reset_expect_no_phantom("Scenario 9 market-source reset");
            scenario_4_bad_frame_drop();
            trading_port_market_expect_no_order("Scenario 9 trading-port market isolation");
        end else begin
            scenario_1_arp_handshake();
            scenario_2_tcp_payload_app_response();
            scenario_3_udp_market_order_response();
            scenario_10_risk_closed_loop();
            back_to_back_market_expect_two_commits("Scenario 10 back-to-back market CDC");
            market_source_reset_expect_no_phantom("Scenario 3 market-source reset");
            scenario_4_bad_frame_drop();
            trading_port_market_expect_no_order("Scenario 4 trading-port market isolation");
        end

        if ((runtime_error_count !== 32'd0) ||
            (arp_timeout_count !== 32'd0) ||
            (arp_retry_count !== 32'd0) ||
            market_cdc_overflow_sticky ||
            round_chip_error ||
            round_market_health_stale ||
            round_market_checksum_error_seen) begin
            $display("TEST_FAIL: final E2E status runtime_err=%0d arp_timeout=%0d retry=%0d cdc_overflow=%0d round_err=%0d stale=%0d csum=%0d recovery=%0d",
                     runtime_error_count, arp_timeout_count, arp_retry_count, market_cdc_overflow_sticky,
                     round_chip_error, round_market_health_stale, round_market_checksum_error_seen,
                     round_market_recovery_seen);
            $finish;
        end

        $display("TEST_INFO: final E2E market_recovery_seen=%0d (status observation, not failure)", round_market_recovery_seen);

        if (SC5_LATENCY != 0)
            $display("TB_HFT_RMIC_DUAL_XGMII_SC5_LATENCY PASS");
        else if (SC4_FULL != 0)
            $display("TB_HFT_RMIC_DUAL_XGMII_SC4 PASS");
        else
            $display("TB_HFT_RMIC_DUAL_XGMII_FULL_SYSTEM PASS");
        $finish;
    end
endmodule
