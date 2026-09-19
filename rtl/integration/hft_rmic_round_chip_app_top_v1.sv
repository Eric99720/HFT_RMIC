`timescale 1ns/1ps
// HFT_RMIC I5 integration-owned derivative.
// Provenance: deps/hft-full-system-fpga/rtl/top/hft_round_chip_app_top.v
// pinned at 50217fad1fd580f8c451ba893f9035f4be1dc21a.
// Frozen application/session behavior is retained; risk admission and committed
// execution reconciliation are inserted without modifying upstream sources.
`include "hft_pkg.vh"
`include "round_chip_defs.vh"

// hft_round_chip_app_top
// ----------------------
// Application-layer round-chip integration prototype:
//   financial decoder/RX wrapper -> selected order book -> dummy trading logic
//   -> decoder/encoder bridge -> external financial encoder session top.
//
// This wrapper intentionally excludes network MAC/UDP/TCP framing. The encoder
// output is the application payload stream.
module hft_rmic_round_chip_app_top_v1 #(
    parameter PRICE_WIDTH = `RC_PRICE_WIDTH,
    parameter QTY_WIDTH = `RC_QTY_WIDTH,
    parameter SYMBOL_WIDTH = `RC_SYMBOL_WIDTH,
    parameter ORDER_WIDTH = `RC_ORDER_WIDTH,
    parameter DATA_WIDTH = `RC_DATA_WIDTH,
    parameter KEEP_WIDTH = `RC_KEEP_WIDTH,
    parameter PAYLOAD_LEN_WIDTH = `RC_PAYLOAD_LEN_WIDTH,
    parameter ENABLE_SPECULATIVE_MARKET_DECODE = 1'b0,
    parameter ENABLE_SPECULATIVE_APP_PATH = 1'b0,
    parameter ENABLE_R01_PREBUILD = 1'b0,
    parameter ENABLE_TMP_SESSION_CLOSURE = 1'b0,
    parameter ENABLE_TMP_REPLAY = 1'b0,
    parameter ENABLE_TMP_MAINTENANCE = 1'b0,
    parameter ENABLE_TMP_FLOW_CONTROL = 1'b0,
    parameter integer TMP_RATE_WINDOW_CYCLES = 156250000,
    parameter integer MAINTENANCE_CLOCK_HZ = 156250000,
    parameter integer R05_TIMEOUT_CYCLES = 781250000
) (
    input  wire                         clk,
    input  wire                         rst_n,

    input  wire                         market_in_valid,
    output wire                         market_in_ready,
    input  wire [DATA_WIDTH-1:0]        market_in_data,
    input  wire [KEEP_WIDTH-1:0]        market_in_keep,
    input  wire                         market_in_last,

    input  wire                         spec_market_in_valid,
    input  wire [DATA_WIDTH-1:0]        spec_market_in_data,
    input  wire [KEEP_WIDTH-1:0]        spec_market_in_keep,
    input  wire                         spec_market_in_last,
    input  wire                         spec_market_commit,
    input  wire                         spec_market_squash,

    input  wire                         order_in_valid,
    output wire                         order_in_ready,
    input  wire [DATA_WIDTH-1:0]        order_in_data,
    input  wire [KEEP_WIDTH-1:0]        order_in_keep,
    input  wire                         order_in_last,

    input  wire [1:0]                   selected_book_id,
    input  wire                         force_market_symbol_en,
    input  wire [SYMBOL_WIDTH-1:0]      force_market_symbol,

    input  wire                         strategy_enable,
    input  wire [PRICE_WIDTH-1:0]       txf_yesterday_close_price,
    input  wire [PRICE_WIDTH-1:0]       mxf_yesterday_close_price,
    input  wire [PRICE_WIDTH-1:0]       tmf_yesterday_close_price,
    input  wire [PRICE_WIDTH-1:0]       threshold_ticks,
    input  wire [QTY_WIDTH-1:0]         fixed_order_qty,

    input  wire                         tcp_connected,
    input  wire                         order_tx_enable,
    input  wire                         network_ready,
    input  wire                         tx_ready,
    input  wire                         session_end_request,

    input  wire [31:0]                  msg_epoch_s,
    input  wire [15:0]                  msg_ms,
    input  wire [15:0]                  fcm_id,
    input  wire [15:0]                  session_id,
    input  wire [15:0]                  cm_id,
    input  wire [15:0]                  body_fcm_id,
    input  wire [63:0]                  user_define,
    input  wire [159:0]                 symbol_text,
    input  wire [7:0]                   order_source,
    input  wire [23:0]                  info_source,
    input  wire [31:0]                  r01_msg_seq_num,
    input  wire [7:0]                   l20_version,
    input  wire [7:0]                   l40_status_code,
    input  wire [7:0]                   l40_ap_code,
    input  wire [7:0]                   l40_key_value,
    input  wire [31:0]                  l40_request_start_seq,
    input  wire [7:0]                   l40_cancel_order_sec,
    input  wire [7:0]                   l60_status_code,

    input  wire [7:0]                   cfg_time_in_force,
    input  wire [7:0]                   cfg_position_effect,
    input  wire [7:0]                   cfg_investor_flag,
    input  wire [31:0]                  cfg_investor_acno,
    input  wire [31:0]                  cfg_order_id_base,
    input  wire [39:0]                  cfg_order_no,
    input  wire [15:0]                  cfg_symbol_slot,
    input  wire [7:0]                   cfg_order_flags,

    // HFT_RMIC host/recovery configuration.
    input  wire                         risk_integration_ready,
    input  wire                         risk_accounting_ready,
    input  wire                         risk_global_kill,
    input  wire                         risk_recovery_clear,
    input  wire [255:0]                 risk_order_type_allow_mask,
    input  wire [255:0]                 risk_tif_allow_mask,
    input  wire [255:0]                 risk_position_effect_allow_mask,
    input  wire                         risk_account_cfg_we,
    input  wire [3:0]                   risk_account_cfg_index,
    input  wire                         risk_account_cfg_valid,
    input  wire [31:0]                  risk_account_cfg_key,
    input  wire [7:0]                   risk_account_cfg_value,
    input  wire                         risk_product_cfg_we,
    input  wire [3:0]                   risk_product_cfg_index,
    input  wire                         risk_product_cfg_valid,
    input  wire [15:0]                  risk_product_cfg_key,
    input  wire [7:0]                   risk_product_cfg_value,
    input  wire                         risk_state_cfg_valid,
    output wire                         risk_state_cfg_ready,
    input  wire [7:0]                   risk_state_cfg_account_id,
    input  wire [7:0]                   risk_state_cfg_product_id,
    input  wire                         risk_state_cfg_enabled,
    input  wire [63:0]                  risk_state_cfg_margin_budget,
    input  wire [63:0]                  risk_state_cfg_margin_per_contract,
    input  wire [15:0]                  risk_state_cfg_long_position,
    input  wire [15:0]                  risk_state_cfg_short_position,
    input  wire [15:0]                  risk_state_cfg_pending_open_long,
    input  wire [15:0]                  risk_state_cfg_pending_open_short,
    input  wire [15:0]                  risk_state_cfg_reserved_close_long,
    input  wire [15:0]                  risk_state_cfg_reserved_close_short,
    output wire                         risk_state_cfg_done,
    output wire                         risk_state_cfg_ok,
    output wire [7:0]                   risk_state_cfg_reason_code,
    output wire                         risk_store_init_done,
    output wire [1:0]                   risk_transaction_owner,
    output wire                         risk_recovery_required,
    output wire                         risk_reject_valid,
    output wire [31:0]                  risk_reject_order_id,
    output wire [1:0]                   risk_reject_reason_source,
    output wire [7:0]                   risk_reject_reason_code,
    output wire                         risk_exec_result_valid,
    output wire                         risk_exec_result_ok,
    output wire [1:0]                   risk_exec_result_reason_source,
    output wire [7:0]                   risk_exec_result_reason_code,
    output wire [31:0]                  risk_exec_result_order_id,
    output wire [15:0]                  risk_exec_result_remaining_qty,
    output wire                         risk_exec_metadata_error,
    output wire                         risk_exec_queue_overflow,

    // Direct application-layer helpers for smoke simulation. When disabled,
    // the top uses hft_rx_order_book_top outputs.
    input  wire                         direct_session_en,
    input  wire                         direct_order_packet_ok,
    input  wire                         direct_order_packet_bad,
    input  wire                         direct_order_error_valid,
    input  wire                         direct_l10_valid,
    input  wire                         direct_l30_valid,
    input  wire [7:0]                   direct_l30_status_code,
    input  wire [15:0]                  direct_l30_append_no,
    input  wire [31:0]                  direct_l30_end_out_bound_num,
    input  wire [7:0]                   direct_l30_system_type,
    input  wire [7:0]                   direct_l30_encrypt_method,
    input  wire                         direct_l50_valid,
    input  wire [7:0]                   direct_l50_status_code,
    input  wire [7:0]                   direct_l50_heartbt_int,
    input  wire [15:0]                  direct_l50_max_flow_ctrl_cnt,
    input  wire                         direct_l41_valid,
    input  wire                         direct_l80_valid,
    input  wire [7:0]                   direct_l80_status_code,
    input  wire                         direct_r04_valid,
    input  wire                         direct_r05_valid,
    input  wire [7:0]                   direct_r05_status_code,

    input  wire                         direct_order_intent_en,
    input  wire                         direct_order_intent_valid,
    output wire                         direct_order_intent_ready,
    input  wire [SYMBOL_WIDTH-1:0]      direct_order_intent_symbol,
    input  wire                         direct_order_intent_side,
    input  wire [PRICE_WIDTH-1:0]       direct_order_intent_price,
    input  wire [QTY_WIDTH-1:0]         direct_order_intent_qty,
    input  wire [3:0]                   direct_order_intent_type,
    input  wire [7:0]                   direct_order_intent_tif,
    input  wire [7:0]                   direct_order_intent_flags,

    output wire [DATA_WIDTH-1:0]        tx_data,
    output wire [KEEP_WIDTH-1:0]        tx_keep,
    output wire                         tx_valid,
    output wire                         tx_last,
    output wire [PAYLOAD_LEN_WIDTH-1:0] tx_payload_len,
    output wire                         tx_complete,

    output wire                         session_ready,
    output wire [3:0]                   session_state,
    output wire                         session_disconnect_request,
    output wire                         maintenance_disconnect_request,
    output wire                         session_end_complete,
    output wire                         session_end_error,
    output wire                         session_end_in_progress,
    output wire                         app_subsystem_ready,
    output wire                         connection_status_valid,
    output wire                         r05_req_valid_seen,
    output wire                         strategy_order_valid_seen,
    output wire                         encoder_order_accepted,
    output wire                         round_chip_error,
    output wire                         bridge_r04_pending,
    output wire                         bridge_order_pending,
    output wire                         bridge_strategy_order_valid,
    output wire                         encoder_strategy_order_ready,
    output wire                         inbound_checksum_ok,
    output wire                         tmp_message_start_accept,
    output wire [7:0]                   tmp_message_start_type,
    output wire                         flow_credit_available,
    output wire [15:0]                  flow_message_count,
    output wire                         flow_overflow_sticky,
    output wire                         maintenance_waiting_for_r05,
    output wire                         market_health_stale,
    output wire                         market_checksum_error_seen,
    output wire                         market_recovery_seen,
    output wire                         selected_book_valid,
    output wire                         selected_strategy_ready,
    output wire                         dbg_financial_decode_valid,
    output wire                         dbg_market_decoder_packet_ok,
    output wire                         dbg_order_book_update_done,
    output wire                         dbg_selected_book_update_valid,
    output wire                         dbg_strategy_decision_valid,
    output wire                         dbg_order_intent_accepted,
    output wire                         dbg_financial_encoder_order_accepted,
    output wire                         dbg_financial_encoder_payload_first_valid,
    output wire                         dbg_financial_encoder_payload_complete,
    output wire [31:0]                  r01_tcp_payload_sum,
    output wire                         r01_tcp_payload_sum_valid
);

    wire encoder_rst = ~rst_n;

    wire order_packet_ok;
    wire order_packet_bad;
    wire order_error_valid;
    wire market_packet_ok;
    wire market_packet_bad;
    wire market_error_valid;
    wire [7:0] market_error_code;
    wire decoder_market_valid;
    wire [7:0] decoder_market_msg_type;
    wire rx_l10_valid;
    wire rx_l30_valid;
    wire [7:0] rx_l30_status_code;
    wire [15:0] rx_l30_append_no;
    wire [31:0] rx_l30_end_out_bound_num;
    wire [7:0] rx_l30_system_type;
    wire [7:0] rx_l30_encrypt_method;
    wire rx_l41_valid;
    wire rx_l50_valid;
    wire [7:0] rx_l50_status_code;
    wire [7:0] rx_l50_heartbt_int;
    wire [15:0] rx_l50_max_flow_ctrl_cnt;
    wire rx_r04_valid;
    wire rx_r05_valid;
    wire [7:0] rx_r05_status_code;
    wire rx_l80_valid;
    wire [7:0] rx_l80_status_code;
    wire rx_r05_req_valid;
    wire rx_app_subsystem_ready;
    wire rx_connection_status_valid;
    wire rx_replay_chunk_commit;
    wire rx_replay_chunk_is_eof;
    wire rx_replay_error;
    wire [7:0] rx_replay_error_code;
    wire [31:0] rx_last_committed_report_seq;
    wire rx_risk_commit_valid;
    wire [7:0] rx_risk_commit_msg_type;
    wire [7:0] rx_risk_commit_status_code;
    wire [7:0] rx_risk_commit_exec_type;
    wire [31:0] rx_risk_commit_order_id;
    wire rx_risk_commit_side;
    wire [7:0] rx_risk_commit_position_effect;
    wire [31:0] rx_risk_commit_order_price;
    wire [15:0] rx_risk_commit_last_qty;
    wire [15:0] rx_risk_commit_leaves_qty;
    wire [15:0] rx_risk_commit_before_qty;
    wire [31:0] rx_risk_commit_report_seq;
    wire rx_risk_commit_is_replay;
    wire rx_risk_commit_metadata_error;

    wire risk_legacy_ready;
    wire risk_prebuild_accept;
    wire risk_source_valid;
    wire risk_source_ready;
    wire [ORDER_WIDTH-1:0] risk_source_data;
    wire risk_source_prebuild;
    wire risk_accepted_valid;
    wire [ORDER_WIDTH-1:0] risk_accepted_data;
    wire [31:0] risk_accepted_order_id;
    wire shared_recovery_required;
    reg  risk_exec_metadata_error_sticky;
    wire bridge_error_i;
    wire execq_valid, execq_ready;
    wire [7:0] execq_msg_type, execq_status_code, execq_exec_type;
    wire [31:0] execq_order_id, execq_order_price;
    wire execq_side;
    wire [7:0] execq_position_effect;
    wire [15:0] execq_last_qty, execq_leaves_qty, execq_before_qty;
    wire execq_overflow_sticky;
    wire [3:0] execq_occupancy;

    wire selected_book_update_valid;
    wire selected_book_stale;
    wire selected_book_crossed;
    wire rx_selected_strategy_ready;
    wire [PRICE_WIDTH-1:0] selected_best_bid_price;
    wire [QTY_WIDTH-1:0] selected_best_bid_qty;
    wire [PRICE_WIDTH-1:0] selected_best_ask_price;
    wire [QTY_WIDTH-1:0] selected_best_ask_qty;
    wire [PRICE_WIDTH-1:0] selected_spread;
    wire [5*PRICE_WIDTH-1:0] selected_bid_prices_flat;
    wire [5*QTY_WIDTH-1:0] selected_bid_qtys_flat;
    wire [5*PRICE_WIDTH-1:0] selected_ask_prices_flat;
    wire [5*QTY_WIDTH-1:0] selected_ask_qtys_flat;
    wire spec_candidate_valid;
    wire [7:0] spec_candidate_msg_type;
    wire [2:0] spec_candidate_action;
    wire spec_candidate_side;
    wire [2:0] spec_candidate_level;
    wire [PRICE_WIDTH-1:0] spec_candidate_price;
    wire [QTY_WIDTH-1:0] spec_candidate_qty;
    wire [31:0] spec_candidate_seq;
    wire [7:0] spec_candidate_entry_index, spec_candidate_entry_count;
    wire spec_shadow_pending, spec_shadow_decision_valid, spec_shadow_side;
    wire [PRICE_WIDTH-1:0] spec_shadow_price;
    wire [QTY_WIDTH-1:0] spec_shadow_qty;
    wire [SYMBOL_WIDTH-1:0] spec_shadow_symbol;
    wire [3:0] spec_shadow_type;
    wire spec_shadow_lookahead_valid, spec_shadow_lookahead_side;
    wire [PRICE_WIDTH-1:0] spec_shadow_lookahead_price;
    wire [QTY_WIDTH-1:0] spec_shadow_lookahead_qty;
    wire [SYMBOL_WIDTH-1:0] spec_shadow_lookahead_symbol;
    wire [3:0] spec_shadow_lookahead_type;
    wire [7:0] spec_shadow_reason, spec_shadow_updates;
    wire spec_shadow_cleared;

    wire trading_order_intent_valid;
    wire trading_order_intent_ready;
    wire [SYMBOL_WIDTH-1:0] trading_order_intent_symbol;
    wire trading_order_intent_side;
    wire [PRICE_WIDTH-1:0] trading_order_intent_price;
    wire [QTY_WIDTH-1:0] trading_order_intent_qty;
    wire [3:0] trading_order_intent_type;
    wire [7:0] trading_reason_code;

    wire bridge_order_intent_valid;
    wire bridge_order_intent_ready;
    wire [SYMBOL_WIDTH-1:0] bridge_order_intent_symbol;
    wire bridge_order_intent_side;
    wire [PRICE_WIDTH-1:0] bridge_order_intent_price;
    wire [QTY_WIDTH-1:0] bridge_order_intent_qty;
    wire [3:0] bridge_order_intent_type;
    wire [7:0] bridge_order_intent_tif;
    wire [7:0] bridge_order_intent_flags;

    wire encoder_l10_valid;
    wire encoder_l30_valid;
    wire encoder_l50_valid;
    wire encoder_l41_valid;
    wire encoder_l80_valid;
    wire [7:0] encoder_l80_status_code;
    wire encoder_r04_valid;
    wire encoder_r04_ready;
    wire [7:0] encoder_l30_status_code;
    wire [15:0] encoder_l30_append_no;
    wire [31:0] encoder_l30_end_out_bound_num;
    wire [7:0] encoder_l30_system_type;
    wire [7:0] encoder_l30_encrypt_method;
    wire [7:0] encoder_l50_status_code;
    wire [7:0] encoder_l50_heartbt_int;
    wire [15:0] encoder_l50_max_flow_ctrl_cnt;
    wire [ORDER_WIDTH-1:0] encoder_strategy_order_data;
    wire [ORDER_WIDTH-1:0] prebuilt_order_data;
    wire encoder_manual_order_ready;
    wire encoder_fifo_full;
    wire encoder_fifo_empty;
    wire encoder_busy;
    wire encoder_payload_active;
    wire encoder_error_overflow;
    wire [31:0] accepted_order_count;
    wire [31:0] sent_order_count;
    wire [31:0] sent_r01_count;
    wire [31:0] sent_r05_count;
    wire [31:0] sent_r04_count;
    wire [31:0] dropped_order_count;
    wire encoder_login_error;
    wire [7:0] encoder_login_error_code;
    wire [7:0] encoder_login_tx_message_type;
    wire [1:0] encoder_tx_mux_active_source;
    wire [31:0] encoder_sent_login_count;
    wire market_snapshot_recovery;
    wire market_snapshot_event;

    reg market_health_stale_r;
    reg market_checksum_error_seen_r;
    reg market_recovery_seen_r;
    reg market_snapshot_seen_in_packet_r;
    reg trading_order_intent_valid_d;
    reg tx_valid_d;
    reg spec_market_in_valid_d;
    reg spec_commit_seen;
    reg spec_release_pending;
    reg suppress_legacy_pending;

    reg [SYMBOL_WIDTH-1:0] selected_symbol_id;
    reg [PRICE_WIDTH-1:0] selected_close_price;

    always @(*) begin
        case (selected_book_id)
            2'd0: begin
                selected_symbol_id = `RC_SYMBOL_TXF;
                selected_close_price = txf_yesterday_close_price;
            end
            2'd1: begin
                selected_symbol_id = `RC_SYMBOL_MXF;
                selected_close_price = mxf_yesterday_close_price;
            end
            2'd2: begin
                selected_symbol_id = `RC_SYMBOL_TMF;
                selected_close_price = tmf_yesterday_close_price;
            end
            default: begin
                selected_symbol_id = 16'h4344;
                selected_close_price = txf_yesterday_close_price;
            end
        endcase
    end

    hft_rmic_rx_order_book_top_v1 #(
        .ENABLE_SPECULATIVE_MARKET_DECODE(ENABLE_SPECULATIVE_MARKET_DECODE),
        .ENABLE_TMP_REPLAY(ENABLE_TMP_REPLAY),
        .SYMBOL0(`RC_SYMBOL_TXF),
        .SYMBOL1(`RC_SYMBOL_MXF),
        .SYMBOL2(`RC_SYMBOL_TMF),
        .SYMBOL3(16'h4344)
    ) u_rx_order_book (
        .clk(clk),
        .rst_n(rst_n),
        .market_in_valid(market_in_valid),
        .market_in_ready(market_in_ready),
        .market_in_data(market_in_data),
        .market_in_keep(market_in_keep),
        .market_in_last(market_in_last),
        .spec_market_in_valid(ENABLE_SPECULATIVE_MARKET_DECODE ? spec_market_in_valid : 1'b0),
        .spec_market_in_data(ENABLE_SPECULATIVE_MARKET_DECODE ? spec_market_in_data : {DATA_WIDTH{1'b0}}),
        .spec_market_in_keep(ENABLE_SPECULATIVE_MARKET_DECODE ? spec_market_in_keep : {KEEP_WIDTH{1'b0}}),
        .spec_market_in_last(ENABLE_SPECULATIVE_MARKET_DECODE ? spec_market_in_last : 1'b0),
        .spec_market_commit(ENABLE_SPECULATIVE_MARKET_DECODE ? spec_market_commit : 1'b0),
        .spec_market_squash(ENABLE_SPECULATIVE_MARKET_DECODE ? spec_market_squash : 1'b0),
        .order_in_valid(order_in_valid),
        .order_in_ready(order_in_ready),
        .order_in_data(order_in_data),
        .order_in_keep(order_in_keep),
        .order_in_last(order_in_last),
        .selected_book_id(selected_book_id),
        .force_market_symbol_en(force_market_symbol_en),
        .force_market_symbol(force_market_symbol),
        .market_packet_ok(market_packet_ok),
        .market_packet_bad(market_packet_bad),
        .market_error_valid(market_error_valid),
        .market_error_code(market_error_code),
        .order_packet_ok(order_packet_ok),
        .order_packet_bad(order_packet_bad),
        .order_error_valid(order_error_valid),
        .order_error_code(),
        .product_info_valid(),
        .i010_product_id(),
        .i010_symbol_code(),
        .i010_product_enable(),
        .market_sequence_reset_seen(),
        .i002_sequence_value(),
        .session_event_valid(),
        .session_msg_type(),
        .l10_valid(rx_l10_valid),
        .l30_valid(rx_l30_valid),
        .l30_status_code(rx_l30_status_code),
        .l30_append_no(rx_l30_append_no),
        .l30_end_out_bound_num(rx_l30_end_out_bound_num),
        .l30_system_type(rx_l30_system_type),
        .l30_encrypt_method(rx_l30_encrypt_method),
        .l41_valid(rx_l41_valid),
        .l50_valid(rx_l50_valid),
        .l50_status_code(rx_l50_status_code),
        .l50_heartbt_int(rx_l50_heartbt_int),
        .l50_max_flow_ctrl_cnt(rx_l50_max_flow_ctrl_cnt),
        .l80_valid(rx_l80_valid),
        .l80_status_code(rx_l80_status_code),
        .r04_valid(rx_r04_valid),
        .r05_valid(rx_r05_valid),
        .r05_status_code(rx_r05_status_code),
        .r05_req_valid(rx_r05_req_valid),
        .app_subsystem_ready(rx_app_subsystem_ready),
        .connection_status_valid(rx_connection_status_valid),
        .selected_book_valid(selected_book_valid),
        .selected_book_update_valid(selected_book_update_valid),
        .selected_book_stale(selected_book_stale),
        .selected_book_crossed(selected_book_crossed),
        .selected_strategy_ready(rx_selected_strategy_ready),
        .selected_best_bid_price(selected_best_bid_price),
        .selected_best_bid_qty(selected_best_bid_qty),
        .selected_best_ask_price(selected_best_ask_price),
        .selected_best_ask_qty(selected_best_ask_qty),
        .selected_spread(selected_spread),
        .selected_bid_price_level_flat(selected_bid_prices_flat),
        .selected_bid_qty_level_flat(selected_bid_qtys_flat),
        .selected_ask_price_level_flat(selected_ask_prices_flat),
        .selected_ask_qty_level_flat(selected_ask_qtys_flat),
        .all_book_valid(),
        .all_book_stale(),
        .all_book_crossed(),
        .all_strategy_ready(),
        .last_trade_valid(),
        .last_trade_price(),
        .last_trade_qty(),
        .last_trade_price_bcd(),
        .last_trade_qty_bcd(),
        .last_trade_seq(),
        .order_state_valid(),
        .last_order_rejected(),
        .last_order_filled(),
        .last_order_partially_filled(),
        .last_order_id(),
        .last_order_no(),
        .last_order_status(),
        .last_exec_type(),
        .last_order_price(),
        .last_order_qty(),
        .last_last_price(),
        .last_last_qty(),
        .last_leaves_qty(),
        .last_report_seq(rx_last_committed_report_seq),
        .replay_chunk_commit(rx_replay_chunk_commit),
        .replay_chunk_is_eof(rx_replay_chunk_is_eof),
        .replay_error(rx_replay_error),
        .replay_error_code(rx_replay_error_code),
        .symbol_hit(),
        .unmatched_symbol(),
        .decoder_market_valid(decoder_market_valid),
        .decoder_market_msg_type(decoder_market_msg_type),
        .decoder_market_action(),
        .decoder_market_side(),
        .decoder_market_level(),
        .decoder_market_price(),
        .decoder_market_qty(),
        .decoder_market_entry_index(),
        .decoder_market_entry_count(),
        .spec_candidate_valid(spec_candidate_valid),
        .spec_candidate_msg_type(spec_candidate_msg_type),
        .spec_candidate_action(spec_candidate_action),
        .spec_candidate_side(spec_candidate_side),
        .spec_candidate_level(spec_candidate_level),
        .spec_candidate_price(spec_candidate_price),
        .spec_candidate_qty(spec_candidate_qty),
        .spec_candidate_seq(spec_candidate_seq),
        .spec_candidate_entry_index(spec_candidate_entry_index),
        .spec_candidate_entry_count(spec_candidate_entry_count),
        .decoder_order_valid(),
        .decoder_order_msg_type(),
        .risk_commit_valid(rx_risk_commit_valid),
        .risk_commit_msg_type(rx_risk_commit_msg_type),
        .risk_commit_status_code(rx_risk_commit_status_code),
        .risk_commit_exec_type(rx_risk_commit_exec_type),
        .risk_commit_order_id(rx_risk_commit_order_id),
        .risk_commit_side(rx_risk_commit_side),
        .risk_commit_position_effect(rx_risk_commit_position_effect),
        .risk_commit_order_price(rx_risk_commit_order_price),
        .risk_commit_last_qty(rx_risk_commit_last_qty),
        .risk_commit_leaves_qty(rx_risk_commit_leaves_qty),
        .risk_commit_before_qty(rx_risk_commit_before_qty),
        .risk_commit_report_seq(rx_risk_commit_report_seq),
        .risk_commit_is_replay(rx_risk_commit_is_replay),
        .risk_commit_metadata_error(rx_risk_commit_metadata_error)
    );

    hft_speculative_book_strategy u_speculative_book_strategy (
        .clk(clk), .rst_n(rst_n),
        .packet_start(ENABLE_SPECULATIVE_APP_PATH && spec_market_in_valid && !spec_market_in_valid_d),
        .squash_valid(ENABLE_SPECULATIVE_APP_PATH && spec_market_squash),
        .candidate_valid(ENABLE_SPECULATIVE_APP_PATH && spec_candidate_valid),
        .candidate_msg_type(spec_candidate_msg_type), .candidate_action(spec_candidate_action),
        .candidate_side(spec_candidate_side), .candidate_level(spec_candidate_level),
        .candidate_price(spec_candidate_price), .candidate_qty(spec_candidate_qty),
        .candidate_entry_index(spec_candidate_entry_index), .candidate_entry_count(spec_candidate_entry_count),
        .canonical_bid_prices_flat(selected_bid_prices_flat), .canonical_bid_qtys_flat(selected_bid_qtys_flat),
        .canonical_ask_prices_flat(selected_ask_prices_flat), .canonical_ask_qtys_flat(selected_ask_qtys_flat),
        .symbol_id(selected_symbol_id), .yesterday_close_price(selected_close_price),
        .threshold_ticks(threshold_ticks), .fixed_order_qty(fixed_order_qty),
        .candidate_pending(spec_shadow_pending), .candidate_decision_valid(spec_shadow_decision_valid),
        .candidate_decision_side(spec_shadow_side), .candidate_decision_price(spec_shadow_price),
        .candidate_decision_qty(spec_shadow_qty), .candidate_decision_symbol(spec_shadow_symbol),
        .candidate_decision_type(spec_shadow_type), .candidate_reason_code(spec_shadow_reason),
        .candidate_lookahead_valid(spec_shadow_lookahead_valid),
        .candidate_lookahead_side(spec_shadow_lookahead_side),
        .candidate_lookahead_price(spec_shadow_lookahead_price),
        .candidate_lookahead_qty(spec_shadow_lookahead_qty),
        .candidate_lookahead_symbol(spec_shadow_lookahead_symbol),
        .candidate_lookahead_type(spec_shadow_lookahead_type),
        .shadow_update_count(spec_shadow_updates), .shadow_cleared(spec_shadow_cleared)
    );

    simple_close_price_trading_logic u_selected_book_trading_logic (
        .clk(clk),
        .rst_n(rst_n),
        .strategy_enable(strategy_enable),
        .symbol_id(selected_symbol_id),
        .book_valid(selected_book_valid),
        .book_stale(selected_book_stale),
        .book_crossed(selected_book_crossed),
        .strategy_ready(selected_strategy_ready),
        .best_bid_price(selected_best_bid_price),
        .best_bid_qty(selected_best_bid_qty),
        .best_ask_price(selected_best_ask_price),
        .best_ask_qty(selected_best_ask_qty),
        .spread(selected_spread),
        .yesterday_close_price(selected_close_price),
        .threshold_ticks(threshold_ticks),
        .fixed_order_qty(fixed_order_qty),
        .order_intent_ready(trading_order_intent_ready),
        .order_intent_valid(trading_order_intent_valid),
        .order_intent_symbol(trading_order_intent_symbol),
        .order_intent_side(trading_order_intent_side),
        .order_intent_price(trading_order_intent_price),
        .order_intent_qty(trading_order_intent_qty),
        .order_intent_type(trading_order_intent_type),
        .trading_reason_code(trading_reason_code)
    );

    wire use_spec_intent = ENABLE_SPECULATIVE_APP_PATH && spec_release_pending && !ENABLE_R01_PREBUILD;
    wire spec_prebuild_decision_valid = spec_shadow_lookahead_valid ||
                                        spec_shadow_decision_valid;
    wire spec_prebuild_side = spec_shadow_lookahead_valid ?
                              spec_shadow_lookahead_side : spec_shadow_side;
    wire [PRICE_WIDTH-1:0] spec_prebuild_price = spec_shadow_lookahead_valid ?
                                                 spec_shadow_lookahead_price : spec_shadow_price;
    wire [QTY_WIDTH-1:0] spec_prebuild_qty = spec_shadow_lookahead_valid ?
                                             spec_shadow_lookahead_qty : spec_shadow_qty;
    wire [SYMBOL_WIDTH-1:0] spec_prebuild_symbol = spec_shadow_lookahead_valid ?
                                                   spec_shadow_lookahead_symbol : spec_shadow_symbol;
    wire [3:0] spec_prebuild_type = spec_shadow_lookahead_valid ?
                                    spec_shadow_lookahead_type : spec_shadow_type;
    wire prebuild_raw_valid = ENABLE_R01_PREBUILD && ENABLE_SPECULATIVE_APP_PATH &&
                              spec_prebuild_decision_valid &&
                              (spec_release_pending || spec_commit_seen || spec_market_commit);
    wire prebuild_direct_valid;
    wire prebuild_duplicate_block;
    wire prebuild_direct_accept = risk_prebuild_accept;
    wire prebuild_decision_consumed = prebuild_direct_accept || prebuild_duplicate_block;

    // Back-to-back committed market packets can overlap the canonical-book
    // update latency. The frozen speculative strategy may therefore recreate
    // the same order from the same market state before canonical state catches
    // up. Suppress only an identical consecutive speculative order key; a
    // changed side/price/qty/type/TIF/PositionEffect remains a new decision.
    hft_rmic_spec_order_dedupe_v1 #(
        .SYMBOL_WIDTH(SYMBOL_WIDTH),
        .PRICE_WIDTH(PRICE_WIDTH),
        .QTY_WIDTH(QTY_WIDTH),
        .TYPE_WIDTH(4)
    ) u_i5_spec_order_dedupe (
        .clk(clk),
        .rst_n(rst_n),
        .clear(risk_recovery_clear),
        .s_valid(prebuild_raw_valid),
        .s_symbol(spec_prebuild_symbol),
        .s_side(spec_prebuild_side),
        .s_price(spec_prebuild_price),
        .s_qty(spec_prebuild_qty),
        .s_type(spec_prebuild_type),
        .s_tif(cfg_time_in_force),
        .s_position_effect(cfg_position_effect),
        .m_valid(prebuild_direct_valid),
        .m_accept(risk_prebuild_accept),
        .duplicate_blocked(prebuild_duplicate_block)
    );
    // When R01 prebuild is active, the speculative shadow decision is the
    // sole order-intent owner. The canonical dummy strategy is deliberately
    // drained but never forwarded to the bridge; it is level-sensitive to a
    // usable book and would otherwise regenerate the same order after the one
    // matching post-commit pulse had been consumed.
    wire allow_legacy_intent = !ENABLE_SPECULATIVE_APP_PATH ||
                               (!ENABLE_R01_PREBUILD && !suppress_legacy_pending);
    wire order_session_gate = !ENABLE_TMP_SESSION_CLOSURE || session_ready;
    assign bridge_order_intent_valid = order_session_gate &&
                                       (direct_order_intent_en ? direct_order_intent_valid :
                                        use_spec_intent ? 1'b1 : (trading_order_intent_valid && allow_legacy_intent));
    assign bridge_order_intent_symbol = direct_order_intent_en ? direct_order_intent_symbol : use_spec_intent ? spec_shadow_symbol : trading_order_intent_symbol;
    assign bridge_order_intent_side = direct_order_intent_en ? direct_order_intent_side : use_spec_intent ? spec_shadow_side : trading_order_intent_side;
    assign bridge_order_intent_price = direct_order_intent_en ? direct_order_intent_price : use_spec_intent ? spec_shadow_price : trading_order_intent_price;
    assign bridge_order_intent_qty = direct_order_intent_en ? direct_order_intent_qty : use_spec_intent ? spec_shadow_qty : trading_order_intent_qty;
    assign bridge_order_intent_type = direct_order_intent_en ? direct_order_intent_type : use_spec_intent ? spec_shadow_type : trading_order_intent_type;
    assign bridge_order_intent_tif = direct_order_intent_en ? direct_order_intent_tif : cfg_time_in_force;
    assign bridge_order_intent_flags = direct_order_intent_en ? direct_order_intent_flags : 8'd0;
    assign direct_order_intent_ready = (direct_order_intent_en && order_session_gate) ? bridge_order_intent_ready : 1'b0;
    assign trading_order_intent_ready = direct_order_intent_en ? 1'b0 :
                                        ENABLE_R01_PREBUILD ? 1'b1 :
                                        suppress_legacy_pending ? 1'b1 :
                                        use_spec_intent ? 1'b0 : bridge_order_intent_ready;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            spec_market_in_valid_d <= 1'b0;
            spec_commit_seen <= 1'b0;
            spec_release_pending <= 1'b0;
            suppress_legacy_pending <= 1'b0;
        end else begin
            spec_market_in_valid_d <= spec_market_in_valid;
            if (!ENABLE_SPECULATIVE_APP_PATH || spec_market_squash) begin
                spec_commit_seen <= 1'b0;
                spec_release_pending <= 1'b0;
                suppress_legacy_pending <= 1'b0;
            end else begin
                if (spec_market_in_valid && !spec_market_in_valid_d)
                    spec_commit_seen <= 1'b0;
                if (spec_market_commit)
                    spec_commit_seen <= 1'b1;
                if ((spec_commit_seen || spec_market_commit) && spec_shadow_pending && spec_prebuild_decision_valid) begin
                    spec_release_pending <= ENABLE_R01_PREBUILD ? !prebuild_decision_consumed : 1'b1;
                    spec_commit_seen <= 1'b0;
                    if (ENABLE_R01_PREBUILD && prebuild_decision_consumed)
                        suppress_legacy_pending <= 1'b1;
                end
                if (spec_release_pending && (ENABLE_R01_PREBUILD ? prebuild_decision_consumed : bridge_order_intent_ready)) begin
                    spec_release_pending <= 1'b0;
                    suppress_legacy_pending <= 1'b1;
                end
                if (suppress_legacy_pending && trading_order_intent_valid) begin
                    suppress_legacy_pending <= 1'b0;
                end
            end
        end
    end

    hft_decoder_encoder_bridge #(.ENABLE_PREBUILD_SUPPORT(ENABLE_R01_PREBUILD)) u_decoder_encoder_bridge (
        .clk(clk),
        .rst_n(rst_n),
        .order_packet_ok(direct_session_en ? direct_order_packet_ok : order_packet_ok),
        .order_packet_bad(direct_session_en ? direct_order_packet_bad : order_packet_bad),
        .order_error_valid(direct_session_en ? direct_order_error_valid : order_error_valid),
        .decoder_l10_valid(direct_session_en ? direct_l10_valid : rx_l10_valid),
        .decoder_l30_valid(direct_session_en ? direct_l30_valid : rx_l30_valid),
        .decoder_l30_status_code(direct_session_en ? direct_l30_status_code : rx_l30_status_code),
        .decoder_l30_append_no(direct_session_en ? direct_l30_append_no : rx_l30_append_no),
        .decoder_l30_end_out_bound_num(direct_session_en ? direct_l30_end_out_bound_num : rx_l30_end_out_bound_num),
        .decoder_l30_system_type(direct_session_en ? direct_l30_system_type : rx_l30_system_type),
        .decoder_l30_encrypt_method(direct_session_en ? direct_l30_encrypt_method : rx_l30_encrypt_method),
        .decoder_l50_valid(direct_session_en ? direct_l50_valid : rx_l50_valid),
        .decoder_l50_status_code(direct_session_en ? direct_l50_status_code : rx_l50_status_code),
        .decoder_l50_heartbt_int(direct_session_en ? direct_l50_heartbt_int : rx_l50_heartbt_int),
        .decoder_l50_max_flow_ctrl_cnt(direct_session_en ? direct_l50_max_flow_ctrl_cnt : rx_l50_max_flow_ctrl_cnt),
        .decoder_l41_valid(direct_session_en ? direct_l41_valid : rx_l41_valid),
        .decoder_l80_valid(ENABLE_TMP_SESSION_CLOSURE ?
                           (direct_session_en ? direct_l80_valid : rx_l80_valid) : 1'b0),
        .decoder_l80_status_code(ENABLE_TMP_SESSION_CLOSURE ?
                                (direct_session_en ? direct_l80_status_code : rx_l80_status_code) : 8'd0),
        .decoder_r04_valid(direct_session_en ? direct_r04_valid : rx_r04_valid),
        .inbound_checksum_ok(inbound_checksum_ok),
        .encoder_l10_valid(encoder_l10_valid),
        .encoder_l30_valid(encoder_l30_valid),
        .encoder_l50_valid(encoder_l50_valid),
        .encoder_l41_valid(encoder_l41_valid),
        .encoder_l80_valid(encoder_l80_valid),
        .encoder_l80_status_code(encoder_l80_status_code),
        .encoder_r04_valid(encoder_r04_valid),
        .encoder_r04_ready(encoder_r04_ready),
        .encoder_l30_status_code(encoder_l30_status_code),
        .encoder_l30_append_no(encoder_l30_append_no),
        .encoder_l30_end_out_bound_num(encoder_l30_end_out_bound_num),
        .encoder_l30_system_type(encoder_l30_system_type),
        .encoder_l30_encrypt_method(encoder_l30_encrypt_method),
        .encoder_l50_status_code(encoder_l50_status_code),
        .encoder_l50_heartbt_int(encoder_l50_heartbt_int),
        .encoder_l50_max_flow_ctrl_cnt(encoder_l50_max_flow_ctrl_cnt),
        .order_intent_valid(bridge_order_intent_valid),
        .order_intent_ready(bridge_order_intent_ready),
        .order_intent_symbol(bridge_order_intent_symbol),
        .order_intent_side(bridge_order_intent_side),
        .order_intent_price(bridge_order_intent_price),
        .order_intent_qty(bridge_order_intent_qty),
        .order_intent_type(bridge_order_intent_type),
        .order_intent_tif(bridge_order_intent_tif),
        .order_intent_flags(bridge_order_intent_flags),
        .cfg_time_in_force(cfg_time_in_force),
        .cfg_position_effect(cfg_position_effect),
        .cfg_investor_flag(cfg_investor_flag),
        .cfg_investor_acno(cfg_investor_acno),
        .cfg_order_id_base(cfg_order_id_base),
        .cfg_order_no(cfg_order_no),
        .cfg_symbol_slot(cfg_symbol_slot),
        .cfg_order_flags(cfg_order_flags),
        .encoder_strategy_order_valid(bridge_strategy_order_valid),
        .encoder_strategy_order_ready(risk_legacy_ready),
        .encoder_strategy_order_data(encoder_strategy_order_data),
        .prebuild_candidate_valid(ENABLE_R01_PREBUILD && spec_prebuild_decision_valid),
        .prebuild_candidate_symbol(spec_prebuild_symbol),
        .prebuild_candidate_side(spec_prebuild_side),
        .prebuild_candidate_price(spec_prebuild_price),
        .prebuild_candidate_qty(spec_prebuild_qty),
        .prebuild_candidate_type(spec_prebuild_type),
        .prebuild_candidate_tif(cfg_time_in_force),
        .prebuild_candidate_flags(8'd0),
        .prebuilt_order_accept(prebuild_direct_accept),
        .prebuilt_order_data(prebuilt_order_data),
        .r04_pending(bridge_r04_pending),
        .order_pending(bridge_order_pending),
        .r05_req_valid_seen(r05_req_valid_seen),
        .strategy_order_valid_seen(strategy_order_valid_seen),
        .bridge_error(bridge_error_i)
    );

    hft_rmic_exec_commit_fifo_v1 #(.DEPTH(8), .PTR_W(3)) u_i5_exec_fifo (
        .clk(clk), .rst_n(rst_n),
        .flush(risk_recovery_clear && (risk_transaction_owner == 2'd0)),
        .s_valid(rx_risk_commit_valid && !rx_risk_commit_metadata_error),
        .s_ready(),
        .s_msg_type(rx_risk_commit_msg_type),
        .s_status_code(rx_risk_commit_status_code),
        .s_exec_type(rx_risk_commit_exec_type),
        .s_order_id(rx_risk_commit_order_id),
        .s_side(rx_risk_commit_side),
        .s_position_effect(rx_risk_commit_position_effect),
        .s_order_price(rx_risk_commit_order_price),
        .s_last_qty(rx_risk_commit_last_qty),
        .s_leaves_qty(rx_risk_commit_leaves_qty),
        .s_before_qty(rx_risk_commit_before_qty),
        .m_valid(execq_valid), .m_ready(execq_ready),
        .m_msg_type(execq_msg_type), .m_status_code(execq_status_code),
        .m_exec_type(execq_exec_type), .m_order_id(execq_order_id),
        .m_side(execq_side), .m_position_effect(execq_position_effect),
        .m_order_price(execq_order_price), .m_last_qty(execq_last_qty),
        .m_leaves_qty(execq_leaves_qty), .m_before_qty(execq_before_qty),
        .overflow_sticky(execq_overflow_sticky), .occupancy(execq_occupancy)
    );

    hft_rmic_dual_order_source_v1 #(.ORDER_WIDTH(ORDER_WIDTH)) u_i5_order_source (
        .legacy_valid(bridge_strategy_order_valid),
        .legacy_ready(risk_legacy_ready),
        .legacy_data(encoder_strategy_order_data),
        .prebuild_valid(ENABLE_R01_PREBUILD ? prebuild_direct_valid : 1'b0),
        .prebuild_accept(risk_prebuild_accept),
        .prebuild_data(prebuilt_order_data),
        .risk_valid(risk_source_valid),
        .risk_ready(risk_source_ready),
        .risk_data(risk_source_data),
        .risk_source_prebuild(risk_source_prebuild)
    );

    hft_rmic_shared_core_v1 #(
        .ORDER_WIDTH(ORDER_WIDTH), .QTY_W(16), .MARGIN_W(64),
        .ENABLE_HOT_MAP_CACHE(1),
        .ENABLE_PARALLEL_CL_ADMISSION(1),
        .ENABLE_L0_STATE_CACHE(1)
    ) u_i5_risk (
        .clk(clk), .rst_n(rst_n),
        .integration_ready(risk_integration_ready && !risk_exec_metadata_error_sticky && !execq_overflow_sticky),
        .accounting_ready(risk_accounting_ready),
        .global_kill(risk_global_kill),
        .recovery_clear(risk_recovery_clear),
        .recovery_required(shared_recovery_required),
        .store_init_done(risk_store_init_done),
        .transaction_owner(risk_transaction_owner),
        .order_type_allow_mask(risk_order_type_allow_mask),
        .tif_allow_mask(risk_tif_allow_mask),
        .position_effect_allow_mask(risk_position_effect_allow_mask),
        .account_cfg_we(risk_account_cfg_we),
        .account_cfg_index(risk_account_cfg_index),
        .account_cfg_valid(risk_account_cfg_valid),
        .account_cfg_key(risk_account_cfg_key),
        .account_cfg_value(risk_account_cfg_value),
        .product_cfg_we(risk_product_cfg_we),
        .product_cfg_index(risk_product_cfg_index),
        .product_cfg_valid(risk_product_cfg_valid),
        .product_cfg_key(risk_product_cfg_key),
        .product_cfg_value(risk_product_cfg_value),
        .hot_account_key(cfg_investor_acno),
        .hot_product_key(cfg_symbol_slot),
        .cfg_valid(risk_state_cfg_valid),
        .cfg_ready(risk_state_cfg_ready),
        .cfg_account_id(risk_state_cfg_account_id),
        .cfg_product_id(risk_state_cfg_product_id),
        .cfg_enabled(risk_state_cfg_enabled),
        .cfg_margin_budget(risk_state_cfg_margin_budget),
        .cfg_margin_per_contract(risk_state_cfg_margin_per_contract),
        .cfg_long_position(risk_state_cfg_long_position),
        .cfg_short_position(risk_state_cfg_short_position),
        .cfg_pending_open_long(risk_state_cfg_pending_open_long),
        .cfg_pending_open_short(risk_state_cfg_pending_open_short),
        .cfg_reserved_close_long(risk_state_cfg_reserved_close_long),
        .cfg_reserved_close_short(risk_state_cfg_reserved_close_short),
        .cfg_done(risk_state_cfg_done),
        .cfg_ok(risk_state_cfg_ok),
        .cfg_reason_code(risk_state_cfg_reason_code),
        .order_valid(risk_source_valid),
        .order_ready(risk_source_ready),
        .order_data(risk_source_data),
        .accepted_order_valid(risk_accepted_valid),
        .accepted_order_ready(encoder_strategy_order_ready),
        .accepted_order_data(risk_accepted_data),
        .accepted_order_id(risk_accepted_order_id),
        .reject_valid(risk_reject_valid),
        .reject_ready(1'b1),
        .reject_order_id(risk_reject_order_id),
        .reject_reason_source(risk_reject_reason_source),
        .reject_reason_code(risk_reject_reason_code),
        .exec_commit_valid(execq_valid),
        .exec_commit_ready(execq_ready),
        .exec_commit_msg_type(execq_msg_type),
        .exec_commit_status_code(execq_status_code),
        .exec_commit_exec_type(execq_exec_type),
        .exec_commit_order_id(execq_order_id),
        .exec_commit_side(execq_side),
        .exec_commit_position_effect(execq_position_effect),
        .exec_commit_order_price(execq_order_price),
        .exec_commit_last_qty(execq_last_qty),
        .exec_commit_leaves_qty(execq_leaves_qty),
        .exec_commit_before_qty(execq_before_qty),
        .exec_result_valid(risk_exec_result_valid),
        .exec_result_ready(1'b1),
        .exec_result_ok(risk_exec_result_ok),
        .exec_result_reason_source(risk_exec_result_reason_source),
        .exec_result_reason_code(risk_exec_result_reason_code),
        .exec_result_order_id(risk_exec_result_order_id),
        .exec_result_remaining_qty(risk_exec_result_remaining_qty)
    );

    assign risk_recovery_required = shared_recovery_required | risk_exec_metadata_error_sticky | execq_overflow_sticky;
    assign risk_exec_metadata_error = rx_risk_commit_metadata_error;
    assign risk_exec_queue_overflow = execq_overflow_sticky;

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n)
            risk_exec_metadata_error_sticky <= 1'b0;
        else if(risk_recovery_clear && (risk_transaction_owner == 2'd0))
            risk_exec_metadata_error_sticky <= 1'b0;
        else if(rx_risk_commit_metadata_error)
            risk_exec_metadata_error_sticky <= 1'b1;
    end

    financial_protocol_encoder_session_top #(
        .ALLOW_STRATEGY_BYPASS_WITHOUT_TX_READY(ENABLE_R01_PREBUILD),
        .ENABLE_TMP_MAINTENANCE(ENABLE_TMP_MAINTENANCE),
        .ENABLE_TMP_FLOW_CONTROL(ENABLE_TMP_FLOW_CONTROL),
        .TMP_RATE_WINDOW_CYCLES(TMP_RATE_WINDOW_CYCLES),
        .MAINTENANCE_CLOCK_HZ(MAINTENANCE_CLOCK_HZ),
        .R05_TIMEOUT_CYCLES(R05_TIMEOUT_CYCLES)
    ) u_financial_encoder (
        .clk(clk),
        .rst(encoder_rst),
        .tcp_connected(tcp_connected),
        .order_tx_enable(order_tx_enable),
        .inbound_checksum_ok(inbound_checksum_ok),
        .l10_valid(encoder_l10_valid),
        .l30_valid(encoder_l30_valid),
        .l50_valid(encoder_l50_valid),
        .l41_valid(encoder_l41_valid),
        .l41_replay_complete(ENABLE_TMP_REPLAY ? rx_replay_chunk_commit : 1'b0),
        .l41_replay_is_eof(ENABLE_TMP_REPLAY ? rx_replay_chunk_is_eof : 1'b0),
        .l41_replay_error(ENABLE_TMP_REPLAY ? rx_replay_error : 1'b0),
        .l80_valid(encoder_l80_valid),
        .l80_status_code(encoder_l80_status_code),
        .session_end_request(ENABLE_TMP_SESSION_CLOSURE ? session_end_request : 1'b0),
        .l30_status_code(encoder_l30_status_code),
        .l30_append_no(encoder_l30_append_no),
        .l30_end_out_bound_num(encoder_l30_end_out_bound_num),
        .l30_system_type(encoder_l30_system_type),
        .l30_encrypt_method(encoder_l30_encrypt_method),
        .l50_status_code(encoder_l50_status_code),
        .l50_heartbt_int(encoder_l50_heartbt_int),
        .l50_max_flow_ctrl_cnt(encoder_l50_max_flow_ctrl_cnt),
        .l20_version(l20_version),
        .l40_status_code(l40_status_code),
        .l40_ap_code(l40_ap_code),
        .l40_key_value(l40_key_value),
        .l40_request_start_seq(ENABLE_TMP_REPLAY ? rx_last_committed_report_seq : l40_request_start_seq),
        .l40_cancel_order_sec(l40_cancel_order_sec),
        .l60_status_code(l60_status_code),
        .manual_order_valid(1'b0),
        .manual_order_ready(encoder_manual_order_ready),
        .manual_order_data({ORDER_WIDTH{1'b0}}),
        .strategy_order_valid(risk_accepted_valid),
        .strategy_order_ready(encoder_strategy_order_ready),
        .strategy_order_data(risk_accepted_data),
        .r04_valid(encoder_r04_valid),
        .r04_ready(encoder_r04_ready),
        .r05_valid(ENABLE_TMP_MAINTENANCE ?
                   (direct_session_en ? direct_r05_valid : rx_r05_valid) : 1'b0),
        .r05_status_code(direct_session_en ? direct_r05_status_code : rx_r05_status_code),
        .committed_tmp_rx_activity(ENABLE_TMP_MAINTENANCE &&
                                   (direct_session_en ? direct_order_packet_ok : order_packet_ok)),
        .msg_epoch_s(msg_epoch_s),
        .msg_ms(msg_ms),
        .fcm_id(fcm_id),
        .session_id(session_id),
        .cm_id(cm_id),
        .body_fcm_id(body_fcm_id),
        .user_define(user_define),
        .symbol_text(symbol_text),
        .order_source(order_source),
        .info_source(info_source),
        .r01_msg_seq_num(r01_msg_seq_num),
        .network_ready(network_ready),
        .tx_data(tx_data),
        .tx_keep(tx_keep),
        .tx_valid(tx_valid),
        .tx_ready(tx_ready),
        .tx_last(tx_last),
        .tx_payload_len(tx_payload_len),
        .tx_complete(tx_complete),
        .session_ready(session_ready),
        .session_state(session_state),
        .login_error(encoder_login_error),
        .login_error_code(encoder_login_error_code),
        .session_disconnect_request(session_disconnect_request),
        .session_end_complete(session_end_complete),
        .session_end_error(session_end_error),
        .session_end_in_progress(session_end_in_progress),
        .login_tx_message_type(encoder_login_tx_message_type),
        .maintenance_disconnect_request(maintenance_disconnect_request),
        .tmp_message_start_accept(tmp_message_start_accept),
        .tmp_message_start_type(tmp_message_start_type),
        .flow_credit_available(flow_credit_available),
        .flow_message_count(flow_message_count),
        .flow_overflow_sticky(flow_overflow_sticky),
        .maintenance_waiting_for_r05(maintenance_waiting_for_r05),
        .tx_mux_active_source(encoder_tx_mux_active_source),
        .sent_login_count(encoder_sent_login_count),
        .fifo_full(encoder_fifo_full),
        .fifo_empty(encoder_fifo_empty),
        .encoder_busy(encoder_busy),
        .payload_active(encoder_payload_active),
        .error_overflow(encoder_error_overflow),
        .accepted_order_count(accepted_order_count),
        .sent_order_count(sent_order_count),
        .sent_r01_count(sent_r01_count),
        .sent_r05_count(sent_r05_count),
        .sent_r04_count(sent_r04_count),
        .dropped_order_count(dropped_order_count),
        .r01_tcp_payload_sum(r01_tcp_payload_sum),
        .r01_tcp_payload_sum_valid(r01_tcp_payload_sum_valid)
    );

    assign round_chip_error = bridge_error_i | risk_recovery_required;
    assign app_subsystem_ready = session_ready | rx_app_subsystem_ready;
    assign connection_status_valid = rx_connection_status_valid | r05_req_valid_seen;
    assign encoder_order_accepted = (accepted_order_count != 32'd0) || (sent_r01_count != 32'd0);
    assign market_snapshot_event = decoder_market_valid &&
                                   (decoder_market_msg_type == `HFT_MSG_BOOK_SNAP);
    assign market_snapshot_recovery = market_packet_ok &&
                                      (market_snapshot_seen_in_packet_r || market_snapshot_event);
    assign selected_strategy_ready = rx_selected_strategy_ready && !market_health_stale_r;
    assign dbg_financial_decode_valid = decoder_market_valid;
    assign dbg_market_decoder_packet_ok = market_packet_ok;
    assign dbg_order_book_update_done = selected_book_update_valid;
    assign dbg_selected_book_update_valid = selected_book_update_valid;
    assign dbg_strategy_decision_valid = trading_order_intent_valid & ~trading_order_intent_valid_d;
    assign dbg_order_intent_accepted = bridge_order_intent_valid & bridge_order_intent_ready;
    assign dbg_financial_encoder_order_accepted = risk_accepted_valid & encoder_strategy_order_ready;
    assign dbg_financial_encoder_payload_first_valid = tx_valid & ~tx_valid_d;
    assign dbg_financial_encoder_payload_complete = tx_complete;
    assign market_health_stale = market_health_stale_r;
    assign market_checksum_error_seen = market_checksum_error_seen_r;
    assign market_recovery_seen = market_recovery_seen_r;

    always @(posedge clk) begin
        if (!rst_n) begin
            market_health_stale_r <= 1'b0;
            market_checksum_error_seen_r <= 1'b0;
            market_recovery_seen_r <= 1'b0;
        end else begin
            if (market_packet_bad || market_error_valid) begin
                market_health_stale_r <= 1'b1;
                market_checksum_error_seen_r <= 1'b1;
            end else if (market_snapshot_recovery) begin
                market_health_stale_r <= 1'b0;
                market_recovery_seen_r <= 1'b1;
            end
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            market_snapshot_seen_in_packet_r <= 1'b0;
        end else begin
            if (market_packet_ok || market_packet_bad || market_error_valid)
                market_snapshot_seen_in_packet_r <= 1'b0;
            else if (market_snapshot_event)
                market_snapshot_seen_in_packet_r <= 1'b1;
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            trading_order_intent_valid_d <= 1'b0;
            tx_valid_d <= 1'b0;
        end else begin
            trading_order_intent_valid_d <= trading_order_intent_valid;
            tx_valid_d <= tx_valid;
        end
    end

endmodule
