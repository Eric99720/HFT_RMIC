`timescale 1ns/1ps
// HFT_RMIC I5 integration-owned derivative.
// Provenance: deps/hft-full-system-fpga/rtl/top/hft_xgmii_network_layer_e2e_top.v
// pinned at 50217fad1fd580f8c451ba893f9035f4be1dc21a.
// Network/TCP/ARP logic is retained; only the contained round-chip app is
// replaced by the risk-aware integration-owned derivative.
`include "round_chip_defs.vh"

module hft_rmic_xgmii_network_layer_e2e_top_v1 #(
    parameter integer MAX_FRAME_BYTES = 512,
    parameter integer MAX_PAYLOAD_BYTES = 256,
    parameter integer DATA_WIDTH = 64,
    parameter integer KEEP_WIDTH = 8,
    parameter [47:0] LOCAL_MAC = 48'h020000000001,
    parameter [47:0] REMOTE_MAC = 48'h020000000002,
    parameter [31:0] LOCAL_IP = 32'h0a000001,
    parameter [31:0] REMOTE_IP = 32'h0a000002,
    parameter [15:0] UDP_MARKET_PORT = 16'd5500,
    parameter [15:0] TCP_LOCAL_PORT = 16'd9000,
    parameter [15:0] TCP_REMOTE_PORT = 16'd8000,
    parameter [31:0] LOCAL_INITIAL_SEQ = 32'h01020304,
    parameter [15:0] TCP_CONTROL_IP_ID = 16'h3001,
    parameter [15:0] RST_IP_ID = 16'h3008,
    parameter [15:0] HEARTBEAT_IP_ID = 16'h3007,
    parameter [15:0] APP_IP_ID = 16'h3009,
    parameter [31:0] ARP_TIMEOUT_CYCLES = 32'd128,
    parameter [7:0]  ARP_MAX_RETRIES = 8'd2,
    parameter [31:0] ACK_PIGGYBACK_DEADLINE_CYCLES = 32'd8,
    parameter         ENABLE_R01_TX_STREAM = 1'b0,
    parameter         ENABLE_EXTERNAL_MARKET_TRANSACTION = 1'b0,
    parameter         ENABLE_TMP_MAINTENANCE = 1'b1,
    parameter         ENABLE_TMP_FLOW_CONTROL = 1'b1,
    parameter         ENABLE_HEARTBEAT_PLACEHOLDER = 1'b0,
    parameter integer TMP_RATE_WINDOW_CYCLES = 156250000,
    parameter integer MAINTENANCE_CLOCK_HZ = 156250000,
    parameter integer R05_TIMEOUT_CYCLES = 781250000
) (
    input  wire                   clk,
    input  wire                   rst_n,

    input  wire                   connection_enable,
    input  wire                   link_up,
    input  wire                   clear_arp_cache,
    input  wire                   heartbeat_trigger,
    input  wire                   user_disconnect,

    input  wire [DATA_WIDTH-1:0]  xgmii_rxd,
    input  wire [KEEP_WIDTH-1:0]  xgmii_rxc,
    output wire [DATA_WIDTH-1:0]  xgmii_txd,
    output wire [KEEP_WIDTH-1:0]  xgmii_txc,

    input  wire                   external_market_valid,
    input  wire [DATA_WIDTH-1:0]  external_market_data,
    input  wire [KEEP_WIDTH-1:0]  external_market_keep,
    input  wire                   external_market_last,
    input  wire                   external_market_commit,
    input  wire                   external_market_squash,

    // HFT_RMIC host/recovery configuration propagated to the contained app.
    input  wire                   risk_integration_ready,
    input  wire                   risk_accounting_ready,
    input  wire                   risk_global_kill,
    input  wire                   risk_recovery_clear,
    input  wire [255:0]           risk_order_type_allow_mask,
    input  wire [255:0]           risk_tif_allow_mask,
    input  wire [255:0]           risk_position_effect_allow_mask,
    // Integration-owned futures order metadata. Frozen HFT hard-coded OPEN
    // at this wrapper layer; I5 exposes the field so full-system validation
    // and later host control can exercise OPEN/CLOSE without upstream edits.
    input  wire [7:0]             cfg_position_effect,
    input  wire                   risk_account_cfg_we,
    input  wire [3:0]             risk_account_cfg_index,
    input  wire                   risk_account_cfg_valid,
    input  wire [31:0]            risk_account_cfg_key,
    input  wire [7:0]             risk_account_cfg_value,
    input  wire                   risk_product_cfg_we,
    input  wire [3:0]             risk_product_cfg_index,
    input  wire                   risk_product_cfg_valid,
    input  wire [15:0]            risk_product_cfg_key,
    input  wire [7:0]             risk_product_cfg_value,
    input  wire                   risk_state_cfg_valid,
    output wire                   risk_state_cfg_ready,
    input  wire [7:0]             risk_state_cfg_account_id,
    input  wire [7:0]             risk_state_cfg_product_id,
    input  wire                   risk_state_cfg_enabled,
    input  wire [63:0]            risk_state_cfg_margin_budget,
    input  wire [63:0]            risk_state_cfg_margin_per_contract,
    input  wire [15:0]            risk_state_cfg_long_position,
    input  wire [15:0]            risk_state_cfg_short_position,
    input  wire [15:0]            risk_state_cfg_pending_open_long,
    input  wire [15:0]            risk_state_cfg_pending_open_short,
    input  wire [15:0]            risk_state_cfg_reserved_close_long,
    input  wire [15:0]            risk_state_cfg_reserved_close_short,
    output wire                   risk_state_cfg_done,
    output wire                   risk_state_cfg_ok,
    output wire [7:0]             risk_state_cfg_reason_code,
    output wire                   risk_store_init_done,
    output wire [1:0]             risk_transaction_owner,
    output wire                   risk_recovery_required,
    output wire                   risk_reject_valid,
    output wire [31:0]            risk_reject_order_id,
    output wire [1:0]             risk_reject_reason_source,
    output wire [7:0]             risk_reject_reason_code,
    output wire                   risk_exec_result_valid,
    output wire                   risk_exec_result_ok,
    output wire [1:0]             risk_exec_result_reason_source,
    output wire [7:0]             risk_exec_result_reason_code,
    output wire [31:0]            risk_exec_result_order_id,
    output wire [15:0]            risk_exec_result_remaining_qty,
    output wire                   risk_exec_metadata_error,
    output wire                   risk_exec_queue_overflow,

    output wire                   tcp_connected,
    output wire                   network_ready,
    output wire                   order_tx_enable,
    output wire                   tx_ready,
    output wire                   app_tx_enable,
    output wire [3:0]             runtime_state,
    output wire [31:0]            tx_next_seq,
    output wire [31:0]            rx_next_ack,
    output wire [31:0]            syn_tx_count,
    output wire [31:0]            final_ack_tx_count,
    output wire [31:0]            pure_ack_tx_count,
    output wire [31:0]            app_tx_count,
    output wire [31:0]            heartbeat_tx_count,
    output wire [31:0]            rst_tx_count,
    output wire [31:0]            disconnect_ignored_count,
    output wire [31:0]            ignored_rx_count,
    output wire [31:0]            valid_synack_count,
    output wire [31:0]            runtime_error_count,
    output wire                   tcp_payload_accept_pulse,
    output wire                   tcp_payload_reject_pulse,
    output wire                   mandatory_ack_pending,
    output wire [31:0]            mandatory_ack_deadline_count,
    output wire [31:0]            ack_piggyback_count,
    output wire                   app_wire_active,
    output wire                   delivery_unknown,
    output wire [31:0]            delivery_unknown_count,
    output wire [31:0]            reconnect_count,

    output wire                   heartbeat_pending,
    output wire [15:0]            heartbeat_payload_len,
    output wire [31:0]            heartbeat_request_count,
    output wire [31:0]            heartbeat_sent_count,
    output wire [31:0]            heartbeat_ignored_count,
    output wire [31:0]            heartbeat_error_count,

    output wire                   app_pending,
    output wire [15:0]            app_payload_len,
    output wire [31:0]            app_request_count,
    output wire [31:0]            app_sent_count,
    output wire [31:0]            app_ignored_count,
    output wire [31:0]            app_error_count,

    output wire                   arp_remote_mac_valid,
    output wire [47:0]            arp_remote_mac,
    output wire                   arp_request_pending,
    output wire                   arp_retry_exhausted,
    output wire [2:0]             arp_state,
    output wire [31:0]            arp_request_count,
    output wire [31:0]            arp_reply_count,
    output wire [31:0]            arp_ignored_reply_count,
    output wire [31:0]            arp_timeout_count,
    output wire [31:0]            arp_retry_count,

    output wire                   xgmii_rx_frame_done,
    output wire                   xgmii_rx_frame_error,
    output wire [7:0]             xgmii_rx_error_code,
    output wire [15:0]            xgmii_rx_frame_len,
    output wire                   xgmii_rx_fcs_ok,

    output wire                   network_rx_frame_done,
    output wire                   network_rx_frame_error,
    output wire [7:0]             network_rx_error_code,
    output wire [15:0]            network_rx_payload_len,
    output wire                   rx_meta_valid,
    output wire [1:0]             rx_meta_frame_type,
    output wire [31:0]            rx_meta_tcp_seq,
    output wire [31:0]            rx_meta_tcp_ack,
    output wire [7:0]             rx_meta_tcp_flags,
    output wire [15:0]            rx_meta_payload_len,
    output wire                   rx_meta_early_valid,
    output wire [1:0]             rx_meta_early_type,
    output wire [15:0]            rx_meta_early_payload_len,
    output wire                   rx_market_early_header_valid,
    output wire                   rx_payload_speculative_valid,
    output wire [DATA_WIDTH-1:0]  rx_payload_speculative_data,
    output wire [KEEP_WIDTH-1:0]  rx_payload_speculative_keep,
    output wire                   rx_payload_speculative_last,
    output wire                   rx_payload_commit,
    output wire                   rx_payload_squash,

    output wire                   rst_builder_frame_done,
    output wire                   tcp_builder_frame_done,
    output wire                   heartbeat_builder_frame_done,
    output wire                   app_builder_frame_done,
    output wire [31:0]            heartbeat_builder_frame_seq_num,
    output wire [31:0]            heartbeat_builder_frame_ack_num,
    output wire [15:0]            heartbeat_builder_frame_payload_len,
    output wire [31:0]            app_builder_frame_seq_num,
    output wire [31:0]            app_builder_frame_ack_num,
    output wire [15:0]            app_builder_frame_payload_len,
    output wire [2:0]             arbiter_active_select,
    output wire [31:0]            arbiter_rst_packet_count,
    output wire [31:0]            arbiter_arp_packet_count,
    output wire [31:0]            arbiter_tcp_packet_count,
    output wire [31:0]            arbiter_heartbeat_packet_count,
    output wire [31:0]            arbiter_app_packet_count,
    output wire                   xgmii_tx_frame_done,
    output wire                   xgmii_tx_frame_error,
    output wire [7:0]             xgmii_tx_error_code,
    output wire [15:0]            xgmii_tx_frame_len,
    output wire [31:0]            xgmii_tx_fcs_value,
    output wire [2:0]             xgmii_tx_source_select,

    output wire                   round_session_ready,
    output wire [3:0]             round_session_state,
    output wire                   round_app_subsystem_ready,
    output wire                   round_strategy_order_valid_seen,
    output wire                   round_encoder_order_accepted,
    output wire                   round_chip_error,
    output wire                   round_selected_book_valid,
    output wire                   round_selected_strategy_ready,
    output wire                   round_market_health_stale,
    output wire                   round_market_checksum_error_seen,
    output wire                   round_market_recovery_seen,
    output wire [DATA_WIDTH-1:0]  round_tx_data,
    output wire [KEEP_WIDTH-1:0]  round_tx_keep,
    output wire                   round_tx_valid,
    output wire                   round_tx_last,
    output wire [15:0]            round_tx_payload_len,
    output wire                   round_tx_complete,
    output wire                   round_maintenance_disconnect_request,
    output wire                   round_tmp_message_start_accept,
    output wire [7:0]             round_tmp_message_start_type,
    output wire                   round_flow_credit_available,
    output wire [15:0]            round_flow_message_count,
    output wire                   round_flow_overflow_sticky,
    output wire                   round_maintenance_waiting_for_r05,
    output wire                   dbg_financial_decode_valid,
    output wire                   dbg_market_decoder_packet_ok,
    output wire                   dbg_order_book_update_done,
    output wire                   dbg_selected_book_update_valid,
    output wire                   dbg_strategy_decision_valid,
    output wire                   dbg_order_intent_accepted,
    output wire                   dbg_financial_encoder_order_accepted,
    output wire                   dbg_financial_encoder_payload_first_valid,
    output wire                   dbg_financial_encoder_payload_complete,
    output wire                   round_market_valid_observed,
    output wire                   round_order_valid_observed
);
    localparam [2:0] SEL_NONE      = 3'd0;
    localparam [2:0] SEL_RST       = 3'd1;
    localparam [2:0] SEL_ARP       = 3'd2;
    localparam [2:0] SEL_TCP       = 3'd3;
    localparam [2:0] SEL_HEARTBEAT = 3'd4;
    localparam [2:0] SEL_APP       = 3'd5;

    wire                  rx_axis_tvalid;
    wire                  rx_axis_tready;
    wire [DATA_WIDTH-1:0] rx_axis_tdata;
    wire [KEEP_WIDTH-1:0] rx_axis_tkeep;
    wire                  rx_axis_tlast;
    wire                  rx_axis_tuser;

    wire                  net_market_valid;
    wire                  net_market_ready;
    wire [DATA_WIDTH-1:0] net_market_data;
    wire [KEEP_WIDTH-1:0] net_market_keep;
    wire                  net_market_last;
    wire                  round_market_valid;
    wire                  round_market_ready;
    wire [DATA_WIDTH-1:0] round_market_data;
    wire [KEEP_WIDTH-1:0] round_market_keep;
    wire                  round_market_last;
    wire                  net_spec_market_ready_unused;
    wire                  selected_spec_market_valid = ENABLE_EXTERNAL_MARKET_TRANSACTION ?
        external_market_valid : rx_payload_speculative_valid;
    wire [DATA_WIDTH-1:0] selected_spec_market_data = ENABLE_EXTERNAL_MARKET_TRANSACTION ?
        external_market_data : rx_payload_speculative_data;
    wire [KEEP_WIDTH-1:0] selected_spec_market_keep = ENABLE_EXTERNAL_MARKET_TRANSACTION ?
        external_market_keep : rx_payload_speculative_keep;
    wire                  selected_spec_market_last = ENABLE_EXTERNAL_MARKET_TRANSACTION ?
        external_market_last : rx_payload_speculative_last;
    wire                  selected_spec_market_commit = ENABLE_EXTERNAL_MARKET_TRANSACTION ?
        external_market_commit : rx_payload_commit;
    wire                  selected_spec_market_squash = ENABLE_EXTERNAL_MARKET_TRANSACTION ?
        external_market_squash : rx_payload_squash;
    wire                  round_spec_market_valid;
    wire [DATA_WIDTH-1:0] round_spec_market_data;
    wire [KEEP_WIDTH-1:0] round_spec_market_keep;
    wire                  round_spec_market_last;

    wire                  net_order_valid;
    wire                  net_order_ready;
    wire [DATA_WIDTH-1:0] net_order_data;
    wire [KEEP_WIDTH-1:0] net_order_keep;
    wire                  net_order_last;
    wire                  round_order_valid;
    wire                  round_order_ready;
    wire [DATA_WIDTH-1:0] round_order_data;
    wire [KEEP_WIDTH-1:0] round_order_keep;
    wire                  round_order_last;

    assign round_market_valid_observed = round_market_valid;
    assign round_order_valid_observed = round_order_valid;

    wire [47:0]           rx_meta_dst_mac;
    wire [47:0]           rx_meta_src_mac;
    wire [15:0]           rx_meta_eth_type;
    wire [31:0]           rx_meta_ipv4_src_ip;
    wire [31:0]           rx_meta_ipv4_dst_ip;
    wire [7:0]            rx_meta_ipv4_protocol;
    wire [15:0]           rx_meta_l4_src_port;
    wire [15:0]           rx_meta_l4_dst_port;
    wire [15:0]           rx_meta_arp_opcode;
    wire [47:0]           rx_meta_arp_sender_mac;
    wire [31:0]           rx_meta_arp_sender_ip;
    wire [47:0]           rx_meta_arp_target_mac;
    wire [31:0]           rx_meta_arp_target_ip;

    reg                   cm_rx_meta_valid;
    reg [1:0]             cm_rx_meta_frame_type;
    reg [47:0]            cm_rx_meta_dst_mac;
    reg [47:0]            cm_rx_meta_src_mac;
    reg [15:0]            cm_rx_meta_eth_type;
    reg [31:0]            cm_rx_meta_ipv4_src_ip;
    reg [31:0]            cm_rx_meta_ipv4_dst_ip;
    reg [7:0]             cm_rx_meta_ipv4_protocol;
    reg [15:0]            cm_rx_meta_l4_src_port;
    reg [15:0]            cm_rx_meta_l4_dst_port;
    reg [31:0]            cm_rx_meta_tcp_seq;
    reg [31:0]            cm_rx_meta_tcp_ack;
    reg [7:0]             cm_rx_meta_tcp_flags;
    reg [15:0]            cm_rx_meta_payload_len;
    reg                   cm_rx_frame_error_pulse;

    wire                  tcp_cmd_valid;
    wire                  tcp_cmd_ready;
    wire [7:0]            tcp_cmd_flags;
    wire [31:0]           tcp_cmd_seq;
    wire [31:0]           tcp_cmd_ack;

    wire                  rst_cmd_valid;
    wire                  rst_cmd_ready;
    wire [7:0]            rst_cmd_flags;
    wire [31:0]           rst_cmd_seq;
    wire [31:0]           rst_cmd_ack;

    wire                  rst_tvalid;
    wire                  rst_tready;
    wire [DATA_WIDTH-1:0] rst_tdata;
    wire [KEEP_WIDTH-1:0] rst_tkeep;
    wire                  rst_tlast;
    wire                  rst_tuser;
    wire                  rst_builder_frame_error;

    wire                  arp_tvalid;
    wire                  arp_tready;
    wire [DATA_WIDTH-1:0] arp_tdata;
    wire [KEEP_WIDTH-1:0] arp_tkeep;
    wire                  arp_tlast;
    wire                  arp_tuser;

    wire                  tcp_tvalid;
    wire                  tcp_tready;
    wire [DATA_WIDTH-1:0] tcp_tdata;
    wire [KEEP_WIDTH-1:0] tcp_tkeep;
    wire                  tcp_tlast;
    wire                  tcp_tuser;
    wire                  tcp_builder_frame_error;

    wire                  heartbeat_payload_valid;
    wire                  heartbeat_payload_ready;
    wire [DATA_WIDTH-1:0] heartbeat_payload_data;
    wire [KEEP_WIDTH-1:0] heartbeat_payload_keep;
    wire                  heartbeat_payload_last;

    wire                  heartbeat_tvalid_raw;
    wire                  heartbeat_tvalid_to_arb;
    wire                  heartbeat_tready_from_arb;
    wire                  heartbeat_tready_raw;
    wire [DATA_WIDTH-1:0] heartbeat_tdata;
    wire [KEEP_WIDTH-1:0] heartbeat_tkeep;
    wire                  heartbeat_tlast;
    wire                  heartbeat_tuser;
    wire                  heartbeat_builder_frame_error;
    wire [15:0]           heartbeat_builder_frame_len_unused;

    wire                  round_app_ready;
    wire                  app_payload_valid;
    wire                  app_payload_ready;
    wire [DATA_WIDTH-1:0] app_payload_data;
    wire [KEEP_WIDTH-1:0] app_payload_keep;
    wire                  app_payload_last;
    wire                  app_payload_ready_legacy;
    wire [31:0]           round_r01_tcp_payload_sum;
    wire                  round_r01_tcp_payload_sum_valid;
    wire                  round_session_disconnect_request;
    wire                  round_maintenance_disconnect_request_int;
    wire                  round_session_end_complete;
    wire                  round_session_end_error;
    wire                  round_session_end_in_progress;
    // SC2A consumes this as a read-only fixture. SC2B must replace it with
    // the single persistent last-committed report-sequence owner.
    wire [31:0]           last_committed_report_seq = 32'h00000001;
    wire                  graceful_session_end_request = user_disconnect & round_session_ready;
    wire                  manager_user_disconnect = round_session_disconnect_request |
                                                    round_maintenance_disconnect_request_int |
                                                    (user_disconnect & ~round_session_ready &
                                                     ~round_session_end_in_progress);

    wire                  app_tvalid_raw;
    wire                  app_tvalid_to_arb;
    wire                  app_tready_from_arb;
    wire                  app_tready_raw;
    wire [DATA_WIDTH-1:0] app_tdata;
    wire [KEEP_WIDTH-1:0] app_tkeep;
    wire                  app_tlast;
    wire                  app_tuser;
    wire                  app_builder_frame_error;
    wire                  app_builder_frame_done_legacy;
    wire                  app_builder_frame_error_legacy;
    wire [31:0]           app_builder_frame_seq_num_legacy;
    wire [31:0]           app_builder_frame_ack_num_legacy;
    wire [15:0]           app_builder_frame_payload_len_legacy;
    wire [15:0]           app_builder_frame_len_unused;

    wire                  arb_tvalid;
    wire                  arb_tready;
    wire [DATA_WIDTH-1:0] arb_tdata;
    wire [KEEP_WIDTH-1:0] arb_tkeep;
    wire                  arb_tlast;
    wire                  arb_tuser;

    reg  [2:0]            tx_source_select_r;
    reg                   xgmii_tx_source_valid;
    reg                   app_accept_blocked;
    reg                   app_frame_complete_seen;
    reg  [15:0]           app_tx_payload_len_latched;
    reg  [15:0]           heartbeat_tx_payload_len_latched;
    wire [2:0]            xgmii_tx_start_select;
    wire                  rst_xgmii_tx_done;
    wire                  rst_xgmii_tx_error;
    wire                  tcp_xgmii_tx_done;
    wire                  tcp_xgmii_tx_error;
    wire                  heartbeat_xgmii_tx_done;
    wire                  heartbeat_xgmii_tx_error;
    wire                  app_xgmii_tx_done;
    wire                  app_xgmii_tx_error;

    wire [DATA_WIDTH-1:0] legacy_xgmii_txd;
    wire [KEEP_WIDTH-1:0] legacy_xgmii_txc;
    wire                  legacy_xgmii_tx_frame_done;
    wire                  legacy_xgmii_tx_frame_error;
    wire [7:0]            legacy_xgmii_tx_error_code;
    wire [15:0]           legacy_xgmii_tx_frame_len;
    wire [31:0]           legacy_xgmii_tx_fcs_value;
    wire                  legacy_encoder_ready;

    wire [DATA_WIDTH-1:0] stream_xgmii_txd;
    wire [KEEP_WIDTH-1:0] stream_xgmii_txc;
    wire                  stream_app_ready;
    wire                  stream_busy;
    wire                  stream_input_reject_pulse;
    wire [7:0]            stream_input_reject_code;
    wire                  stream_frame_start;
    wire                  stream_frame_done;
    wire                  stream_frame_error;
    wire [15:0]           stream_frame_len;
    wire [31:0]           stream_fcs_value;
    wire [31:0]           stream_frame_seq_num;
    wire [31:0]           stream_frame_ack_num;
    wire                  stream_start_allowed;
    wire                  stream_start_accept;
    wire                  app_route_stream_selected;
    reg  [31:0]           stream_app_packet_count;
    reg                   app_route_active;
    reg                   app_route_stream;
    wire [31:0]           arbiter_app_packet_count_legacy;

    assign xgmii_tx_source_select = tx_source_select_r;

    assign heartbeat_tvalid_to_arb = ENABLE_HEARTBEAT_PLACEHOLDER &&
                                     tcp_connected && heartbeat_tvalid_raw;
    assign heartbeat_tready_raw = tcp_connected ? heartbeat_tready_from_arb : 1'b0;
    assign app_tvalid_to_arb = app_tx_enable & app_tvalid_raw;
    assign app_tready_raw = app_tx_enable ? app_tready_from_arb : 1'b0;
    assign round_app_ready = app_tx_enable & app_payload_ready & ~app_accept_blocked;
    assign app_payload_valid = app_tx_enable & round_tx_valid & ~app_accept_blocked;
    assign app_payload_data = round_tx_data;
    assign app_payload_keep = round_tx_keep;
    assign app_payload_last = round_tx_last;
    assign app_route_stream_selected = ENABLE_R01_TX_STREAM &&
                                       (app_route_active ? app_route_stream : round_r01_tcp_payload_sum_valid);
    assign app_payload_ready = app_route_stream_selected ? stream_app_ready : app_payload_ready_legacy;

    assign stream_start_allowed = ENABLE_R01_TX_STREAM &&
                                  !xgmii_tx_source_valid &&
                                  !stream_busy &&
                                  !arb_tvalid;
    assign arb_tready = legacy_encoder_ready && !stream_busy;

    assign xgmii_txd = stream_busy ? stream_xgmii_txd : legacy_xgmii_txd;
    assign xgmii_txc = stream_busy ? stream_xgmii_txc : legacy_xgmii_txc;
    assign xgmii_tx_frame_done = stream_frame_done | legacy_xgmii_tx_frame_done;
    assign xgmii_tx_frame_error = stream_frame_done ? stream_frame_error : legacy_xgmii_tx_frame_error;
    assign xgmii_tx_error_code = stream_frame_done ? (stream_frame_error ? 8'h01 : 8'h00) : legacy_xgmii_tx_error_code;
    assign xgmii_tx_frame_len = stream_busy ? stream_frame_len : legacy_xgmii_tx_frame_len;
    assign xgmii_tx_fcs_value = stream_busy ? stream_fcs_value : legacy_xgmii_tx_fcs_value;

    assign app_builder_frame_done = stream_frame_done | app_builder_frame_done_legacy;
    assign app_builder_frame_error = (stream_frame_done & stream_frame_error) | app_builder_frame_error_legacy;
    assign app_builder_frame_seq_num = (stream_busy | stream_frame_done) ? stream_frame_seq_num : app_builder_frame_seq_num_legacy;
    assign app_builder_frame_ack_num = (stream_busy | stream_frame_done) ? stream_frame_ack_num : app_builder_frame_ack_num_legacy;
    assign app_builder_frame_payload_len = (stream_busy | stream_frame_done) ? 16'd80 : app_builder_frame_payload_len_legacy;
    assign arbiter_app_packet_count = arbiter_app_packet_count_legacy + stream_app_packet_count;

    assign xgmii_tx_start_select =
        (arbiter_active_select != SEL_NONE) ? arbiter_active_select :
        rst_tvalid                         ? SEL_RST :
        arp_tvalid                         ? SEL_ARP :
        tcp_tvalid                         ? SEL_TCP :
        heartbeat_tvalid_to_arb            ? SEL_HEARTBEAT :
        app_tvalid_to_arb                  ? SEL_APP :
                                             SEL_NONE;

    assign rst_xgmii_tx_done =
        xgmii_tx_frame_done & ~xgmii_tx_frame_error & (tx_source_select_r == SEL_RST);
    assign rst_xgmii_tx_error =
        xgmii_tx_frame_done & xgmii_tx_frame_error & (tx_source_select_r == SEL_RST);
    assign tcp_xgmii_tx_done =
        xgmii_tx_frame_done & ~xgmii_tx_frame_error & (tx_source_select_r == SEL_TCP);
    assign tcp_xgmii_tx_error =
        xgmii_tx_frame_done & xgmii_tx_frame_error & (tx_source_select_r == SEL_TCP);
    assign heartbeat_xgmii_tx_done =
        xgmii_tx_frame_done & ~xgmii_tx_frame_error & (tx_source_select_r == SEL_HEARTBEAT);
    assign heartbeat_xgmii_tx_error =
        xgmii_tx_frame_done & xgmii_tx_frame_error & (tx_source_select_r == SEL_HEARTBEAT);
    assign app_xgmii_tx_done =
        xgmii_tx_frame_done & ~xgmii_tx_frame_error & (tx_source_select_r == SEL_APP);
    assign app_xgmii_tx_error =
        xgmii_tx_frame_done & xgmii_tx_frame_error & (tx_source_select_r == SEL_APP);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_source_select_r <= SEL_NONE;
            xgmii_tx_source_valid <= 1'b0;
            app_accept_blocked <= 1'b0;
            app_frame_complete_seen <= 1'b0;
            app_tx_payload_len_latched <= 16'd0;
            heartbeat_tx_payload_len_latched <= 16'd0;
        end else begin
            if (stream_start_accept) begin
                tx_source_select_r <= SEL_APP;
                xgmii_tx_source_valid <= 1'b1;
                app_tx_payload_len_latched <= 16'd80;
            end else if (!xgmii_tx_source_valid && arb_tvalid && arb_tready) begin
                tx_source_select_r <= xgmii_tx_start_select;
                xgmii_tx_source_valid <= 1'b1;
                if (xgmii_tx_start_select == SEL_APP) begin
                    app_tx_payload_len_latched <= app_builder_frame_payload_len;
                end
                if (xgmii_tx_start_select == SEL_HEARTBEAT) begin
                    heartbeat_tx_payload_len_latched <= heartbeat_builder_frame_payload_len;
                end
            end
            if (xgmii_tx_frame_done) begin
                xgmii_tx_source_valid <= 1'b0;
            end
            if (app_accept_blocked) begin
                if (app_xgmii_tx_done || app_xgmii_tx_error || app_builder_frame_error) begin
                    app_frame_complete_seen <= 1'b1;
                end
                // The previous packet owns the network path until its frame
                // completion, but the application source is allowed to hold
                // the next packet valid meanwhile. Requiring round_tx_valid
                // to drop deadlocks a queued R01 behind an R05/L42 legacy
                // frame because the encoder correctly holds that R01 valid
                // under backpressure.
                if (app_frame_complete_seen ||
                    app_xgmii_tx_done ||
                    app_xgmii_tx_error ||
                    app_builder_frame_error) begin
                    app_accept_blocked <= 1'b0;
                    app_frame_complete_seen <= 1'b0;
                end
            end else if (app_payload_valid && app_payload_ready && app_payload_last) begin
                app_accept_blocked <= 1'b1;
                app_frame_complete_seen <= 1'b0;
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            stream_app_packet_count <= 32'd0;
        else if (stream_start_accept)
            stream_app_packet_count <= stream_app_packet_count + 1'b1;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            app_route_active <= 1'b0;
            app_route_stream <= 1'b0;
        end else if (app_payload_valid && app_payload_ready) begin
            if (app_payload_last) begin
                app_route_active <= 1'b0;
                app_route_stream <= 1'b0;
            end else if (!app_route_active) begin
                app_route_active <= 1'b1;
                app_route_stream <= app_route_stream_selected;
            end
        end
    end

    hft_xgmii_rx_decoder #(
        .MAX_FRAME_BYTES(MAX_FRAME_BYTES),
        .DATA_WIDTH(DATA_WIDTH),
        .KEEP_WIDTH(KEEP_WIDTH),
        .FCS_BYPASS(1'b0)
    ) u_xgmii_rx_decoder (
        .clk(clk),
        .rst_n(rst_n),
        .xgmii_rxd(xgmii_rxd),
        .xgmii_rxc(xgmii_rxc),
        .m_axis_tvalid(rx_axis_tvalid),
        .m_axis_tready(rx_axis_tready),
        .m_axis_tdata(rx_axis_tdata),
        .m_axis_tkeep(rx_axis_tkeep),
        .m_axis_tlast(rx_axis_tlast),
        .m_axis_tuser(rx_axis_tuser),
        .frame_done(xgmii_rx_frame_done),
        .frame_error(xgmii_rx_frame_error),
        .error_code(xgmii_rx_error_code),
        .frame_len(xgmii_rx_frame_len),
        .fcs_ok(xgmii_rx_fcs_ok)
    );

    hft_network_rx_fast_path #(
        .MAX_FRAME_BYTES(MAX_FRAME_BYTES),
        .DATA_WIDTH(DATA_WIDTH),
        .KEEP_WIDTH(KEEP_WIDTH),
        .LOCAL_MAC(LOCAL_MAC),
        .LOCAL_IP(LOCAL_IP),
        .UDP_MARKET_PORT(UDP_MARKET_PORT),
        .TCP_LOCAL_PORT(TCP_LOCAL_PORT),
        .TCP_REMOTE_PORT(TCP_REMOTE_PORT),
        .ENABLE_MARKET_RX_HOT_PATH(1'b1)
    ) u_network_rx_fast_path (
        .clk(clk),
        .rst_n(rst_n),
        .s_axis_tvalid(rx_axis_tvalid),
        .s_axis_tready(rx_axis_tready),
        .s_axis_tdata(rx_axis_tdata),
        .s_axis_tkeep(rx_axis_tkeep),
        .s_axis_tlast(rx_axis_tlast),
        .s_axis_tuser(rx_axis_tuser),
        .market_in_valid(net_market_valid),
        .market_in_ready(net_market_ready),
        .market_in_data(net_market_data),
        .market_in_keep(net_market_keep),
        .market_in_last(net_market_last),
        .order_in_valid(net_order_valid),
        .order_in_ready(net_order_ready),
        .order_in_data(net_order_data),
        .order_in_keep(net_order_keep),
        .order_in_last(net_order_last),
        .frame_done(network_rx_frame_done),
        .frame_error(network_rx_frame_error),
        .error_code(network_rx_error_code),
        .payload_len(network_rx_payload_len),
        .rx_meta_valid(rx_meta_valid),
        .rx_meta_frame_type(rx_meta_frame_type),
        .rx_meta_dst_mac(rx_meta_dst_mac),
        .rx_meta_src_mac(rx_meta_src_mac),
        .rx_meta_eth_type(rx_meta_eth_type),
        .rx_meta_ipv4_src_ip(rx_meta_ipv4_src_ip),
        .rx_meta_ipv4_dst_ip(rx_meta_ipv4_dst_ip),
        .rx_meta_ipv4_protocol(rx_meta_ipv4_protocol),
        .rx_meta_l4_src_port(rx_meta_l4_src_port),
        .rx_meta_l4_dst_port(rx_meta_l4_dst_port),
        .rx_meta_tcp_seq(rx_meta_tcp_seq),
        .rx_meta_tcp_ack(rx_meta_tcp_ack),
        .rx_meta_tcp_flags(rx_meta_tcp_flags),
        .rx_meta_payload_len(rx_meta_payload_len),
        .rx_meta_early_valid(rx_meta_early_valid),
        .rx_meta_early_type(rx_meta_early_type),
        .rx_meta_early_payload_len(rx_meta_early_payload_len),
        .rx_market_early_header_valid(rx_market_early_header_valid),
        .rx_payload_speculative_valid(rx_payload_speculative_valid),
        .rx_payload_speculative_data(rx_payload_speculative_data),
        .rx_payload_speculative_keep(rx_payload_speculative_keep),
        .rx_payload_speculative_last(rx_payload_speculative_last),
        .rx_payload_commit(rx_payload_commit),
        .rx_payload_squash(rx_payload_squash),
        .rx_meta_arp_opcode(rx_meta_arp_opcode),
        .rx_meta_arp_sender_mac(rx_meta_arp_sender_mac),
        .rx_meta_arp_sender_ip(rx_meta_arp_sender_ip),
        .rx_meta_arp_target_mac(rx_meta_arp_target_mac),
        .rx_meta_arp_target_ip(rx_meta_arp_target_ip)
    );

    hft_rmic_axis_reverse_byte_order_64_e2e_v1 u_market_byte_order_adapter (
        .s_valid(net_market_valid),
        .s_ready(net_market_ready),
        .s_data(net_market_data),
        .s_keep(net_market_keep),
        .s_last(net_market_last),
        .m_valid(round_market_valid),
        .m_ready(round_market_ready),
        .m_data(round_market_data),
        .m_keep(round_market_keep),
        .m_last(round_market_last)
    );

    hft_rmic_axis_reverse_byte_order_64_e2e_v1 u_spec_market_byte_order_adapter (
        .s_valid(selected_spec_market_valid),
        .s_ready(net_spec_market_ready_unused),
        .s_data(selected_spec_market_data),
        .s_keep(selected_spec_market_keep),
        .s_last(selected_spec_market_last),
        .m_valid(round_spec_market_valid),
        .m_ready(1'b1),
        .m_data(round_spec_market_data),
        .m_keep(round_spec_market_keep),
        .m_last(round_spec_market_last)
    );

    hft_rmic_axis_reverse_byte_order_64_e2e_v1 u_order_byte_order_adapter (
        .s_valid(net_order_valid),
        .s_ready(net_order_ready),
        .s_data(net_order_data),
        .s_keep(net_order_keep),
        .s_last(net_order_last),
        .m_valid(round_order_valid),
        .m_ready(round_order_ready),
        .m_data(round_order_data),
        .m_keep(round_order_keep),
        .m_last(round_order_last)
    );

    hft_rmic_round_chip_app_top_v1 #(
        .ENABLE_SPECULATIVE_MARKET_DECODE(1'b1),
        .ENABLE_SPECULATIVE_APP_PATH(1'b1),
        .ENABLE_R01_PREBUILD(1'b1),
        .ENABLE_TMP_SESSION_CLOSURE(1'b1),
        .ENABLE_TMP_REPLAY(1'b1),
        .ENABLE_TMP_MAINTENANCE(ENABLE_TMP_MAINTENANCE),
        .ENABLE_TMP_FLOW_CONTROL(ENABLE_TMP_FLOW_CONTROL),
        .TMP_RATE_WINDOW_CYCLES(TMP_RATE_WINDOW_CYCLES),
        .MAINTENANCE_CLOCK_HZ(MAINTENANCE_CLOCK_HZ),
        .R05_TIMEOUT_CYCLES(R05_TIMEOUT_CYCLES)
    ) u_round_chip_app (
        .clk(clk),
        .rst_n(rst_n),
        .market_in_valid(round_market_valid),
        .market_in_ready(round_market_ready),
        .market_in_data(round_market_data),
        .market_in_keep(round_market_keep),
        .market_in_last(round_market_last),
        .spec_market_in_valid(round_spec_market_valid),
        .spec_market_in_data(round_spec_market_data),
        .spec_market_in_keep(round_spec_market_keep),
        .spec_market_in_last(round_spec_market_last),
        .spec_market_commit(selected_spec_market_commit),
        .spec_market_squash(selected_spec_market_squash),
        .order_in_valid(round_order_valid),
        .order_in_ready(round_order_ready),
        .order_in_data(round_order_data),
        .order_in_keep(round_order_keep),
        .order_in_last(round_order_last),
        .selected_book_id(2'd0),
        .force_market_symbol_en(1'b1),
        .force_market_symbol(`RC_SYMBOL_TXF),
        .strategy_enable(1'b1),
        .txf_yesterday_close_price(32'd1020),
        .mxf_yesterday_close_price(32'd2000),
        .tmf_yesterday_close_price(32'd3000),
        .threshold_ticks(32'd10),
        .fixed_order_qty(32'd1),
        .tcp_connected(tcp_connected),
        .order_tx_enable(order_tx_enable),
        .network_ready(network_ready),
        .tx_ready(round_app_ready),
        .session_end_request(graceful_session_end_request),
        .msg_epoch_s(32'h00000001),
        .msg_ms(16'h0002),
        .fcm_id(16'h1234),
        .session_id(16'h0056),
        .cm_id(16'h5678),
        .body_fcm_id(16'h1234),
        .user_define(64'h0000000000000000),
        .symbol_text({"                 ", "F", "X", "T"}),
        .order_source(8'h39),
        .info_source(24'h393939),
        .r01_msg_seq_num(32'h00000001),
        .l20_version(8'h00),
        .l40_status_code(8'h00),
        .l40_ap_code(8'h04),
        .l40_key_value(8'h0c),
        .l40_request_start_seq(last_committed_report_seq),
        .l40_cancel_order_sec(8'h00),
        .l60_status_code(8'h00),
        .cfg_time_in_force(8'h00),
        .cfg_position_effect(cfg_position_effect),
        .cfg_investor_flag(8'h41),
        .cfg_investor_acno(32'h0012d687),
        .cfg_order_id_base(32'h00000001),
        .cfg_order_no(40'h4130303031),
        .cfg_symbol_slot(16'h0000),
        .cfg_order_flags(8'h00),
        .risk_integration_ready(risk_integration_ready),
        .risk_accounting_ready(risk_accounting_ready),
        .risk_global_kill(risk_global_kill),
        .risk_recovery_clear(risk_recovery_clear),
        .risk_order_type_allow_mask(risk_order_type_allow_mask),
        .risk_tif_allow_mask(risk_tif_allow_mask),
        .risk_position_effect_allow_mask(risk_position_effect_allow_mask),
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
        .direct_session_en(1'b0),
        .direct_order_packet_ok(1'b0),
        .direct_order_packet_bad(1'b0),
        .direct_order_error_valid(1'b0),
        .direct_l10_valid(1'b0),
        .direct_l30_valid(1'b0),
        .direct_l30_status_code(8'd0),
        .direct_l30_append_no(16'd0),
        .direct_l30_end_out_bound_num(32'd0),
        .direct_l30_system_type(8'd0),
        .direct_l30_encrypt_method(8'd0),
        .direct_l50_valid(1'b0),
        .direct_l50_status_code(8'd0),
        .direct_l50_heartbt_int(8'd0),
        .direct_l50_max_flow_ctrl_cnt(16'd0),
        .direct_l41_valid(1'b0),
        .direct_l80_valid(1'b0),
        .direct_l80_status_code(8'd0),
        .direct_r04_valid(1'b0),
        .direct_r05_valid(1'b0),
        .direct_r05_status_code(8'd0),
        .direct_order_intent_en(1'b0),
        .direct_order_intent_valid(1'b0),
        .direct_order_intent_ready(),
        .direct_order_intent_symbol(`RC_SYMBOL_TXF),
        .direct_order_intent_side(`RC_SIDE_BUY),
        .direct_order_intent_price(32'd0),
        .direct_order_intent_qty(32'd0),
        .direct_order_intent_type(4'd0),
        .direct_order_intent_tif(8'd0),
        .direct_order_intent_flags(8'd0),
        .tx_data(round_tx_data),
        .tx_keep(round_tx_keep),
        .tx_valid(round_tx_valid),
        .tx_last(round_tx_last),
        .tx_payload_len(round_tx_payload_len),
        .tx_complete(round_tx_complete),
        .r01_tcp_payload_sum(round_r01_tcp_payload_sum),
        .r01_tcp_payload_sum_valid(round_r01_tcp_payload_sum_valid),
        .session_ready(round_session_ready),
        .session_state(round_session_state),
        .session_disconnect_request(round_session_disconnect_request),
        .maintenance_disconnect_request(round_maintenance_disconnect_request_int),
        .session_end_complete(round_session_end_complete),
        .session_end_error(round_session_end_error),
        .session_end_in_progress(round_session_end_in_progress),
        .app_subsystem_ready(round_app_subsystem_ready),
        .connection_status_valid(),
        .r05_req_valid_seen(),
        .strategy_order_valid_seen(round_strategy_order_valid_seen),
        .encoder_order_accepted(round_encoder_order_accepted),
        .round_chip_error(round_chip_error),
        .bridge_r04_pending(),
        .bridge_order_pending(),
        .bridge_strategy_order_valid(),
        .encoder_strategy_order_ready(),
        .inbound_checksum_ok(),
        .tmp_message_start_accept(round_tmp_message_start_accept),
        .tmp_message_start_type(round_tmp_message_start_type),
        .flow_credit_available(round_flow_credit_available),
        .flow_message_count(round_flow_message_count),
        .flow_overflow_sticky(round_flow_overflow_sticky),
        .maintenance_waiting_for_r05(round_maintenance_waiting_for_r05),
        .market_health_stale(round_market_health_stale),
        .market_checksum_error_seen(round_market_checksum_error_seen),
        .market_recovery_seen(round_market_recovery_seen),
        .selected_book_valid(round_selected_book_valid),
        .selected_strategy_ready(round_selected_strategy_ready),
        .dbg_financial_decode_valid(dbg_financial_decode_valid),
        .dbg_market_decoder_packet_ok(dbg_market_decoder_packet_ok),
        .dbg_order_book_update_done(dbg_order_book_update_done),
        .dbg_selected_book_update_valid(dbg_selected_book_update_valid),
        .dbg_strategy_decision_valid(dbg_strategy_decision_valid),
        .dbg_order_intent_accepted(dbg_order_intent_accepted),
        .dbg_financial_encoder_order_accepted(dbg_financial_encoder_order_accepted),
        .dbg_financial_encoder_payload_first_valid(dbg_financial_encoder_payload_first_valid),
        .dbg_financial_encoder_payload_complete(dbg_financial_encoder_payload_complete)
    );

    assign round_maintenance_disconnect_request = round_maintenance_disconnect_request_int;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cm_rx_meta_valid <= 1'b0;
            cm_rx_meta_frame_type <= 2'd0;
            cm_rx_meta_dst_mac <= 48'd0;
            cm_rx_meta_src_mac <= 48'd0;
            cm_rx_meta_eth_type <= 16'd0;
            cm_rx_meta_ipv4_src_ip <= 32'd0;
            cm_rx_meta_ipv4_dst_ip <= 32'd0;
            cm_rx_meta_ipv4_protocol <= 8'd0;
            cm_rx_meta_l4_src_port <= 16'd0;
            cm_rx_meta_l4_dst_port <= 16'd0;
            cm_rx_meta_tcp_seq <= 32'd0;
            cm_rx_meta_tcp_ack <= 32'd0;
            cm_rx_meta_tcp_flags <= 8'd0;
            cm_rx_meta_payload_len <= 16'd0;
            cm_rx_frame_error_pulse <= 1'b0;
        end else begin
            cm_rx_meta_valid <= rx_meta_valid;
            cm_rx_meta_frame_type <= rx_meta_frame_type;
            cm_rx_meta_dst_mac <= rx_meta_dst_mac;
            cm_rx_meta_src_mac <= rx_meta_src_mac;
            cm_rx_meta_eth_type <= rx_meta_eth_type;
            cm_rx_meta_ipv4_src_ip <= rx_meta_ipv4_src_ip;
            cm_rx_meta_ipv4_dst_ip <= rx_meta_ipv4_dst_ip;
            cm_rx_meta_ipv4_protocol <= rx_meta_ipv4_protocol;
            cm_rx_meta_l4_src_port <= rx_meta_l4_src_port;
            cm_rx_meta_l4_dst_port <= rx_meta_l4_dst_port;
            cm_rx_meta_tcp_seq <= rx_meta_tcp_seq;
            cm_rx_meta_tcp_ack <= rx_meta_tcp_ack;
            cm_rx_meta_tcp_flags <= rx_meta_tcp_flags;
            cm_rx_meta_payload_len <= rx_meta_payload_len;
            cm_rx_frame_error_pulse <=
                (xgmii_rx_frame_done & xgmii_rx_frame_error) |
                (network_rx_frame_done & network_rx_frame_error);
        end
    end

    hft_unified_network_connection_manager #(
        .DATA_WIDTH(DATA_WIDTH),
        .KEEP_WIDTH(KEEP_WIDTH),
        .LOCAL_MAC(LOCAL_MAC),
        .REMOTE_MAC_FALLBACK(REMOTE_MAC),
        .LOCAL_IP(LOCAL_IP),
        .REMOTE_IP(REMOTE_IP),
        .TCP_LOCAL_PORT(TCP_LOCAL_PORT),
        .TCP_REMOTE_PORT(TCP_REMOTE_PORT),
        .LOCAL_INITIAL_SEQ(LOCAL_INITIAL_SEQ),
        .ARP_TIMEOUT_CYCLES(ARP_TIMEOUT_CYCLES),
        .ARP_MAX_RETRIES(ARP_MAX_RETRIES),
        .ACK_PIGGYBACK_DEADLINE_CYCLES(ACK_PIGGYBACK_DEADLINE_CYCLES)
    ) u_connection_manager (
        .clk(clk),
        .rst_n(rst_n),
        .connection_enable(connection_enable),
        .link_up(link_up),
        .clear_arp_cache(clear_arp_cache),
        .user_disconnect(manager_user_disconnect),
        .arp_rx_meta_valid(rx_meta_valid),
        .arp_rx_meta_frame_type(rx_meta_frame_type),
        .arp_rx_meta_opcode(rx_meta_arp_opcode),
        .arp_rx_meta_sender_mac(rx_meta_arp_sender_mac),
        .arp_rx_meta_sender_ip(rx_meta_arp_sender_ip),
        .arp_rx_meta_target_mac(rx_meta_arp_target_mac),
        .arp_rx_meta_target_ip(rx_meta_arp_target_ip),
        .tcp_rx_meta_valid(cm_rx_meta_valid),
        .tcp_rx_meta_frame_type(cm_rx_meta_frame_type),
        .tcp_rx_meta_dst_mac(cm_rx_meta_dst_mac),
        .tcp_rx_meta_src_mac(cm_rx_meta_src_mac),
        .tcp_rx_meta_eth_type(cm_rx_meta_eth_type),
        .tcp_rx_meta_ipv4_src_ip(cm_rx_meta_ipv4_src_ip),
        .tcp_rx_meta_ipv4_dst_ip(cm_rx_meta_ipv4_dst_ip),
        .tcp_rx_meta_ipv4_protocol(cm_rx_meta_ipv4_protocol),
        .tcp_rx_meta_l4_src_port(cm_rx_meta_l4_src_port),
        .tcp_rx_meta_l4_dst_port(cm_rx_meta_l4_dst_port),
        .tcp_rx_meta_tcp_seq(cm_rx_meta_tcp_seq),
        .tcp_rx_meta_tcp_ack(cm_rx_meta_tcp_ack),
        .tcp_rx_meta_tcp_flags(cm_rx_meta_tcp_flags),
        .tcp_rx_meta_payload_len(cm_rx_meta_payload_len),
        .tcp_rx_frame_error_pulse(cm_rx_frame_error_pulse),
        .arp_tvalid(arp_tvalid),
        .arp_tready(arp_tready),
        .arp_tdata(arp_tdata),
        .arp_tkeep(arp_tkeep),
        .arp_tlast(arp_tlast),
        .arp_tuser(arp_tuser),
        .tcp_cmd_valid(tcp_cmd_valid),
        .tcp_cmd_ready(tcp_cmd_ready),
        .tcp_cmd_flags(tcp_cmd_flags),
        .tcp_cmd_seq(tcp_cmd_seq),
        .tcp_cmd_ack(tcp_cmd_ack),
        .tcp_tx_done(tcp_xgmii_tx_done),
        .tcp_tx_error(tcp_xgmii_tx_error | tcp_builder_frame_error),
        .rst_cmd_valid(rst_cmd_valid),
        .rst_cmd_ready(rst_cmd_ready),
        .rst_cmd_flags(rst_cmd_flags),
        .rst_cmd_seq(rst_cmd_seq),
        .rst_cmd_ack(rst_cmd_ack),
        .rst_tx_done(rst_xgmii_tx_done),
        .rst_tx_error(rst_xgmii_tx_error | rst_builder_frame_error),
        .app_tx_start_accept(stream_start_accept),
        .app_tx_start_ack_num(rx_next_ack),
        .app_tx_done(app_xgmii_tx_done),
        .app_tx_payload_len(app_tx_payload_len_latched),
        .app_tx_error(app_xgmii_tx_error | app_builder_frame_error),
        .heartbeat_tx_done(heartbeat_xgmii_tx_done),
        .heartbeat_tx_payload_len(heartbeat_tx_payload_len_latched),
        .heartbeat_tx_error(heartbeat_xgmii_tx_error | heartbeat_builder_frame_error),
        .remote_mac_valid(arp_remote_mac_valid),
        .remote_mac(arp_remote_mac),
        .arp_request_pending(arp_request_pending),
        .arp_retry_exhausted(arp_retry_exhausted),
        .arp_state(arp_state),
        .arp_request_count(arp_request_count),
        .arp_reply_count(arp_reply_count),
        .arp_ignored_reply_count(arp_ignored_reply_count),
        .arp_timeout_count(arp_timeout_count),
        .arp_retry_count(arp_retry_count),
        .tcp_connected(tcp_connected),
        .network_ready(network_ready),
        .order_tx_enable(order_tx_enable),
        .tx_ready(tx_ready),
        .app_tx_enable(app_tx_enable),
        .tcp_payload_accept_pulse(tcp_payload_accept_pulse),
        .tcp_payload_reject_pulse(tcp_payload_reject_pulse),
        .tcp_state(runtime_state),
        .tx_next_seq(tx_next_seq),
        .rx_next_ack(rx_next_ack),
        .syn_tx_count(syn_tx_count),
        .final_ack_tx_count(final_ack_tx_count),
        .pure_ack_tx_count(pure_ack_tx_count),
        .app_tx_count(app_tx_count),
        .heartbeat_tx_count(heartbeat_tx_count),
        .rst_tx_count(rst_tx_count),
        .disconnect_ignored_count(disconnect_ignored_count),
        .ignored_rx_count(ignored_rx_count),
        .valid_synack_count(valid_synack_count),
        .error_count(runtime_error_count),
        .mandatory_ack_pending(mandatory_ack_pending),
        .mandatory_ack_deadline_count(mandatory_ack_deadline_count),
        .ack_piggyback_count(ack_piggyback_count),
        .app_wire_active(app_wire_active),
        .delivery_unknown(delivery_unknown),
        .delivery_unknown_count(delivery_unknown_count),
        .reconnect_count(reconnect_count)
    );

    hft_tcp_control_tx_builder #(
        .DATA_WIDTH(DATA_WIDTH),
        .KEEP_WIDTH(KEEP_WIDTH),
        .LOCAL_MAC(LOCAL_MAC),
        .REMOTE_MAC(REMOTE_MAC),
        .LOCAL_IP(LOCAL_IP),
        .REMOTE_IP(REMOTE_IP),
        .TCP_LOCAL_PORT(TCP_LOCAL_PORT),
        .TCP_REMOTE_PORT(TCP_REMOTE_PORT),
        .IP_ID(TCP_CONTROL_IP_ID)
    ) u_tcp_control_tx_builder (
        .clk(clk),
        .rst_n(rst_n),
        .runtime_remote_mac(arp_remote_mac),
        .cmd_valid(tcp_cmd_valid),
        .cmd_ready(tcp_cmd_ready),
        .cmd_tcp_flags(tcp_cmd_flags),
        .cmd_seq(tcp_cmd_seq),
        .cmd_ack(tcp_cmd_ack),
        .m_axis_tvalid(tcp_tvalid),
        .m_axis_tready(tcp_tready),
        .m_axis_tdata(tcp_tdata),
        .m_axis_tkeep(tcp_tkeep),
        .m_axis_tlast(tcp_tlast),
        .m_axis_tuser(tcp_tuser),
        .frame_done(tcp_builder_frame_done),
        .frame_error(tcp_builder_frame_error),
        .frame_len()
    );

    hft_tcp_control_tx_builder #(
        .DATA_WIDTH(DATA_WIDTH),
        .KEEP_WIDTH(KEEP_WIDTH),
        .LOCAL_MAC(LOCAL_MAC),
        .REMOTE_MAC(REMOTE_MAC),
        .LOCAL_IP(LOCAL_IP),
        .REMOTE_IP(REMOTE_IP),
        .TCP_LOCAL_PORT(TCP_LOCAL_PORT),
        .TCP_REMOTE_PORT(TCP_REMOTE_PORT),
        .IP_ID(RST_IP_ID)
    ) u_rst_control_tx_builder (
        .clk(clk),
        .rst_n(rst_n),
        .runtime_remote_mac(arp_remote_mac),
        .cmd_valid(rst_cmd_valid),
        .cmd_ready(rst_cmd_ready),
        .cmd_tcp_flags(rst_cmd_flags),
        .cmd_seq(rst_cmd_seq),
        .cmd_ack(rst_cmd_ack),
        .m_axis_tvalid(rst_tvalid),
        .m_axis_tready(rst_tready),
        .m_axis_tdata(rst_tdata),
        .m_axis_tkeep(rst_tkeep),
        .m_axis_tlast(rst_tlast),
        .m_axis_tuser(rst_tuser),
        .frame_done(rst_builder_frame_done),
        .frame_error(rst_builder_frame_error),
        .frame_len()
    );

    hft_heartbeat_placeholder_source #(
        .DATA_WIDTH(DATA_WIDTH),
        .KEEP_WIDTH(KEEP_WIDTH)
    ) u_heartbeat_placeholder_source (
        .clk(clk),
        .rst_n(rst_n),
        .enable(tcp_connected),
        .heartbeat_trigger(ENABLE_HEARTBEAT_PLACEHOLDER ? heartbeat_trigger : 1'b0),
        .heartbeat_tx_done(heartbeat_xgmii_tx_done),
        .heartbeat_tx_error(heartbeat_xgmii_tx_error | heartbeat_builder_frame_error),
        .payload_valid(heartbeat_payload_valid),
        .payload_ready(heartbeat_payload_ready),
        .payload_data(heartbeat_payload_data),
        .payload_keep(heartbeat_payload_keep),
        .payload_last(heartbeat_payload_last),
        .payload_len(heartbeat_payload_len),
        .heartbeat_pending(heartbeat_pending),
        .heartbeat_request_count(heartbeat_request_count),
        .heartbeat_sent_count(heartbeat_sent_count),
        .heartbeat_ignored_count(heartbeat_ignored_count),
        .heartbeat_error_count(heartbeat_error_count)
    );

    assign app_payload_len = round_tx_payload_len;
    assign app_pending = round_tx_valid & ~round_app_ready;
    assign app_request_count = app_tx_count;
    assign app_sent_count = app_tx_count;
    assign app_ignored_count = 32'd0;
    assign app_error_count = 32'd0;

    hft_network_tx_runtime_fast_path #(
        .MAX_PAYLOAD_BYTES(MAX_PAYLOAD_BYTES),
        .MAX_FRAME_BYTES(MAX_FRAME_BYTES),
        .DATA_WIDTH(DATA_WIDTH),
        .KEEP_WIDTH(KEEP_WIDTH),
        .LOCAL_MAC(LOCAL_MAC),
        .REMOTE_MAC(REMOTE_MAC),
        .LOCAL_IP(LOCAL_IP),
        .REMOTE_IP(REMOTE_IP),
        .TCP_LOCAL_PORT(TCP_LOCAL_PORT),
        .TCP_REMOTE_PORT(TCP_REMOTE_PORT),
        .IP_ID(HEARTBEAT_IP_ID)
    ) u_heartbeat_tx_builder (
        .clk(clk),
        .rst_n(rst_n),
        .runtime_remote_mac(arp_remote_mac),
        .seq_num(tx_next_seq),
        .ack_num(rx_next_ack),
        .app_valid(heartbeat_payload_valid),
        .app_ready(heartbeat_payload_ready),
        .app_data(heartbeat_payload_data),
        .app_keep(heartbeat_payload_keep),
        .app_last(heartbeat_payload_last),
        .m_axis_tvalid(heartbeat_tvalid_raw),
        .m_axis_tready(heartbeat_tready_raw),
        .m_axis_tdata(heartbeat_tdata),
        .m_axis_tkeep(heartbeat_tkeep),
        .m_axis_tlast(heartbeat_tlast),
        .m_axis_tuser(heartbeat_tuser),
        .frame_done(heartbeat_builder_frame_done),
        .frame_error(heartbeat_builder_frame_error),
        .frame_seq_num(heartbeat_builder_frame_seq_num),
        .frame_ack_num(heartbeat_builder_frame_ack_num),
        .frame_payload_len(heartbeat_builder_frame_payload_len),
        .frame_len(heartbeat_builder_frame_len_unused)
    );

    hft_network_tx_runtime_fast_path #(
        .MAX_PAYLOAD_BYTES(MAX_PAYLOAD_BYTES),
        .MAX_FRAME_BYTES(MAX_FRAME_BYTES),
        .DATA_WIDTH(DATA_WIDTH),
        .KEEP_WIDTH(KEEP_WIDTH),
        .LOCAL_MAC(LOCAL_MAC),
        .REMOTE_MAC(REMOTE_MAC),
        .LOCAL_IP(LOCAL_IP),
        .REMOTE_IP(REMOTE_IP),
        .TCP_LOCAL_PORT(TCP_LOCAL_PORT),
        .TCP_REMOTE_PORT(TCP_REMOTE_PORT),
        .IP_ID(APP_IP_ID)
    ) u_app_tx_builder (
        .clk(clk),
        .rst_n(rst_n),
        .runtime_remote_mac(arp_remote_mac),
        .seq_num(tx_next_seq),
        .ack_num(rx_next_ack),
        .app_valid(app_payload_valid & ~app_route_stream_selected),
        .app_ready(app_payload_ready_legacy),
        .app_data(app_payload_data),
        .app_keep(app_payload_keep),
        .app_last(app_payload_last),
        .m_axis_tvalid(app_tvalid_raw),
        .m_axis_tready(app_tready_raw),
        .m_axis_tdata(app_tdata),
        .m_axis_tkeep(app_tkeep),
        .m_axis_tlast(app_tlast),
        .m_axis_tuser(app_tuser),
        .frame_done(app_builder_frame_done_legacy),
        .frame_error(app_builder_frame_error_legacy),
        .frame_seq_num(app_builder_frame_seq_num_legacy),
        .frame_ack_num(app_builder_frame_ack_num_legacy),
        .frame_payload_len(app_builder_frame_payload_len_legacy),
        .frame_len(app_builder_frame_len_unused)
    );

    hft_r01_xgmii_stream_tx #(
        .LOCAL_MAC(LOCAL_MAC),
        .REMOTE_MAC(REMOTE_MAC),
        .LOCAL_IP(LOCAL_IP),
        .REMOTE_IP(REMOTE_IP),
        .TCP_LOCAL_PORT(TCP_LOCAL_PORT),
        .TCP_REMOTE_PORT(TCP_REMOTE_PORT),
        .IP_ID(APP_IP_ID)
    ) u_r01_xgmii_stream_tx (
        .clk(clk),
        .rst_n(rst_n),
        .runtime_remote_mac(arp_remote_mac),
        .enable(ENABLE_R01_TX_STREAM),
        .start_allowed(stream_start_allowed),
        .seq_num(tx_next_seq),
        .ack_num(rx_next_ack),
        .payload_sum(round_r01_tcp_payload_sum),
        .payload_sum_valid(round_r01_tcp_payload_sum_valid),
        .app_valid(app_payload_valid & app_route_stream_selected),
        .app_ready(stream_app_ready),
        .app_data(app_payload_data),
        .app_keep(app_payload_keep),
        .app_last(app_payload_last),
        .xgmii_txd(stream_xgmii_txd),
        .xgmii_txc(stream_xgmii_txc),
        .busy(stream_busy),
        .start_accept(stream_start_accept),
        .input_reject_pulse(stream_input_reject_pulse),
        .input_reject_code(stream_input_reject_code),
        .frame_start(stream_frame_start),
        .frame_done(stream_frame_done),
        .frame_error(stream_frame_error),
        .frame_len(stream_frame_len),
        .fcs_value(stream_fcs_value),
        .frame_seq_num(stream_frame_seq_num),
        .frame_ack_num(stream_frame_ack_num)
    );

    hft_axis_packet_arbiter #(
        .DATA_WIDTH(DATA_WIDTH),
        .KEEP_WIDTH(KEEP_WIDTH)
    ) u_axis_packet_arbiter (
        .clk(clk),
        .rst_n(rst_n),
        .rst_tvalid(rst_tvalid),
        .rst_tready(rst_tready),
        .rst_tdata(rst_tdata),
        .rst_tkeep(rst_tkeep),
        .rst_tlast(rst_tlast),
        .rst_tuser(rst_tuser),
        .arp_tvalid(arp_tvalid),
        .arp_tready(arp_tready),
        .arp_tdata(arp_tdata),
        .arp_tkeep(arp_tkeep),
        .arp_tlast(arp_tlast),
        .arp_tuser(arp_tuser),
        .tcp_tvalid(tcp_tvalid),
        .tcp_tready(tcp_tready),
        .tcp_tdata(tcp_tdata),
        .tcp_tkeep(tcp_tkeep),
        .tcp_tlast(tcp_tlast),
        .tcp_tuser(tcp_tuser),
        .heartbeat_tvalid(heartbeat_tvalid_to_arb),
        .heartbeat_tready(heartbeat_tready_from_arb),
        .heartbeat_tdata(heartbeat_tdata),
        .heartbeat_tkeep(heartbeat_tkeep),
        .heartbeat_tlast(heartbeat_tlast),
        .heartbeat_tuser(heartbeat_tuser),
        .app_tvalid(app_tvalid_to_arb),
        .app_tready(app_tready_from_arb),
        .app_tdata(app_tdata),
        .app_tkeep(app_tkeep),
        .app_tlast(app_tlast),
        .app_tuser(app_tuser),
        .m_axis_tvalid(arb_tvalid),
        .m_axis_tready(arb_tready),
        .m_axis_tdata(arb_tdata),
        .m_axis_tkeep(arb_tkeep),
        .m_axis_tlast(arb_tlast),
        .m_axis_tuser(arb_tuser),
        .active_select(arbiter_active_select),
        .rst_packet_count(arbiter_rst_packet_count),
        .arp_packet_count(arbiter_arp_packet_count),
        .tcp_packet_count(arbiter_tcp_packet_count),
        .heartbeat_packet_count(arbiter_heartbeat_packet_count),
        .app_packet_count(arbiter_app_packet_count_legacy)
    );

    hft_rmic_xgmii_tx_encoder_v1 #(
        .MAX_FRAME_BYTES(MAX_FRAME_BYTES),
        .DATA_WIDTH(DATA_WIDTH),
        .KEEP_WIDTH(KEEP_WIDTH)
    ) u_xgmii_tx_encoder (
        .clk(clk),
        .rst_n(rst_n),
        .s_axis_tvalid(arb_tvalid),
        .s_axis_tready(legacy_encoder_ready),
        .s_axis_tdata(arb_tdata),
        .s_axis_tkeep(arb_tkeep),
        .s_axis_tlast(arb_tlast),
        .s_axis_tuser(arb_tuser),
        .xgmii_txd(legacy_xgmii_txd),
        .xgmii_txc(legacy_xgmii_txc),
        .frame_done(legacy_xgmii_tx_frame_done),
        .frame_error(legacy_xgmii_tx_frame_error),
        .error_code(legacy_xgmii_tx_error_code),
        .frame_len(legacy_xgmii_tx_frame_len),
        .fcs_value(legacy_xgmii_tx_fcs_value)
    );
endmodule

module hft_rmic_axis_reverse_byte_order_64_e2e_v1 (
    input  wire        s_valid,
    output wire        s_ready,
    input  wire [63:0] s_data,
    input  wire [7:0]  s_keep,
    input  wire        s_last,

    output wire        m_valid,
    input  wire        m_ready,
    output wire [63:0] m_data,
    output wire [7:0]  m_keep,
    output wire        m_last
);
    assign s_ready = m_ready;
    assign m_valid = s_valid;
    assign m_last = s_last;

    assign m_data[63:56] = s_data[7:0];
    assign m_data[55:48] = s_data[15:8];
    assign m_data[47:40] = s_data[23:16];
    assign m_data[39:32] = s_data[31:24];
    assign m_data[31:24] = s_data[39:32];
    assign m_data[23:16] = s_data[47:40];
    assign m_data[15:8]  = s_data[55:48];
    assign m_data[7:0]   = s_data[63:56];

    assign m_keep[7] = s_keep[0];
    assign m_keep[6] = s_keep[1];
    assign m_keep[5] = s_keep[2];
    assign m_keep[4] = s_keep[3];
    assign m_keep[3] = s_keep[4];
    assign m_keep[2] = s_keep[5];
    assign m_keep[1] = s_keep[6];
    assign m_keep[0] = s_keep[7];
endmodule
