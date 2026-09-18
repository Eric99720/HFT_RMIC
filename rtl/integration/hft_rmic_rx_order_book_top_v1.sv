`timescale 1ns / 1ps
// HFT_RMIC I5 integration-owned derivative.
// Provenance: deps/hft-full-system-fpga/rtl/order_book/hft_rx_order_book_top.v
// pinned at 50217fad1fd580f8c451ba893f9035f4be1dc21a.
// Frozen decoder/order-book/replay wiring is retained; I5 only adds keyed
// futures metadata taps and committed risk-event outputs. Do not edit the
// upstream source to implement this integration.

`include "hft_pkg.vh"
`include "taifex_tmp_v2187_defs.svh"

// RX-to-order-book Day 1 integration wrapper.
//
// This wrapper keeps the existing decoder and order-book subsystem intact:
//   market payload stream -> financial_decoder_fast_dual_path_top.market path
//                         -> order_book_multi_symbol_system_top.market input
//   order payload stream  -> financial_decoder_fast_dual_path_top.order path
//                         -> order_book_multi_symbol_system_top.order input
//
// Current wrapper uses forced/default market_symbol as a project assumption
// because financial decoder symbol table / product-id-to-instrument mapping is
// not finalized. Future work: connect decoder PROD-ID / symbol table output to
// market_symbol.
module hft_rmic_rx_order_book_top_v1 #(
    parameter integer BOOK_COUNT = 4,
    parameter integer BOOK_LEVELS = `HFT_LEVEL_NUM,
    parameter integer SYMBOL_WIDTH = `HFT_SYMBOL_WIDTH,
    parameter integer DATA_WIDTH = `HFT_DATA_WIDTH,
    parameter integer KEEP_WIDTH = `HFT_KEEP_WIDTH,
    parameter integer PRICE_WIDTH = `HFT_PRICE_WIDTH,
    parameter integer QTY_WIDTH = `HFT_QTY_WIDTH,
    parameter integer SEQ_WIDTH = `HFT_SEQ_WIDTH,
    parameter integer ERR_WIDTH = `HFT_ERR_WIDTH,
    parameter ENABLE_SPECULATIVE_MARKET_DECODE = 1'b0,
    parameter ENABLE_TMP_REPLAY = 1'b0,
    parameter [SYMBOL_WIDTH-1:0] DEFAULT_MARKET_SYMBOL = 16'h5458,
    parameter [SYMBOL_WIDTH-1:0] SYMBOL0 = 16'h5458,
    parameter [SYMBOL_WIDTH-1:0] SYMBOL1 = 16'h4d58,
    parameter [SYMBOL_WIDTH-1:0] SYMBOL2 = 16'h4142,
    parameter [SYMBOL_WIDTH-1:0] SYMBOL3 = 16'h4344
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

    output wire                         market_packet_ok,
    output wire                         market_packet_bad,
    output wire                         market_error_valid,
    output wire [ERR_WIDTH-1:0]         market_error_code,
    output wire                         order_packet_ok,
    output wire                         order_packet_bad,
    output wire                         order_error_valid,
    output wire [ERR_WIDTH-1:0]         order_error_code,

    output wire                         product_info_valid,
    output wire [15:0]                  i010_product_id,
    output wire [15:0]                  i010_symbol_code,
    output wire                         i010_product_enable,
    output wire                         market_sequence_reset_seen,
    output wire [31:0]                  i002_sequence_value,
    output wire                         session_event_valid,
    output wire [7:0]                   session_msg_type,
    output wire                         l10_valid,
    output wire                         l30_valid,
    output wire [7:0]                   l30_status_code,
    output wire [15:0]                  l30_append_no,
    output wire [31:0]                  l30_end_out_bound_num,
    output wire [7:0]                   l30_system_type,
    output wire [7:0]                   l30_encrypt_method,
    output wire                         l41_valid,
    output wire                         l50_valid,
    output wire [7:0]                   l50_status_code,
    output wire [7:0]                   l50_heartbt_int,
    output wire [15:0]                  l50_max_flow_ctrl_cnt,
    output wire                         l80_valid,
    output wire [7:0]                   l80_status_code,
    output wire                         r04_valid,
    output wire                         r05_valid,
    output wire [7:0]                   r05_status_code,
    output wire                         r05_req_valid,
    output wire                         app_subsystem_ready,
    output wire                         connection_status_valid,

    output wire                         selected_book_valid,
    output wire                         selected_book_update_valid,
    output wire                         selected_book_stale,
    output wire                         selected_book_crossed,
    output wire                         selected_strategy_ready,
    output wire [PRICE_WIDTH-1:0]       selected_best_bid_price,
    output wire [QTY_WIDTH-1:0]         selected_best_bid_qty,
    output wire [PRICE_WIDTH-1:0]       selected_best_ask_price,
    output wire [QTY_WIDTH-1:0]         selected_best_ask_qty,
    output wire [PRICE_WIDTH-1:0]       selected_spread,
    // Selected full-level output for downstream trading logic feature extraction
    // and waveform/debug visibility. Level 1 is the least significant slice.
    output wire [BOOK_LEVELS*PRICE_WIDTH-1:0] selected_bid_price_level_flat,
    output wire [BOOK_LEVELS*QTY_WIDTH-1:0]   selected_bid_qty_level_flat,
    output wire [BOOK_LEVELS*PRICE_WIDTH-1:0] selected_ask_price_level_flat,
    output wire [BOOK_LEVELS*QTY_WIDTH-1:0]   selected_ask_qty_level_flat,

    output wire [BOOK_COUNT-1:0]        all_book_valid,
    output wire [BOOK_COUNT-1:0]        all_book_stale,
    output wire [BOOK_COUNT-1:0]        all_book_crossed,
    output wire [BOOK_COUNT-1:0]        all_strategy_ready,

    output wire                         last_trade_valid,
    output wire [PRICE_WIDTH-1:0]       last_trade_price,
    output wire [QTY_WIDTH-1:0]         last_trade_qty,
    output reg  [39:0]                  last_trade_price_bcd,
    output reg  [31:0]                  last_trade_qty_bcd,
    output wire [SEQ_WIDTH-1:0]         last_trade_seq,

    output wire                         order_state_valid,
    output wire                         last_order_rejected,
    output wire                         last_order_filled,
    output wire                         last_order_partially_filled,
    output wire [63:0]                  last_order_id,
    output wire [63:0]                  last_order_no,
    output reg  [`HFT_STATUS_WIDTH-1:0] last_order_status,
    output reg  [`HFT_STATUS_WIDTH-1:0] last_exec_type,
    output reg  [PRICE_WIDTH-1:0]       last_order_price,
    output reg  [QTY_WIDTH-1:0]         last_order_qty,
    output reg  [PRICE_WIDTH-1:0]       last_last_price,
    output reg  [QTY_WIDTH-1:0]         last_last_qty,
    output reg  [QTY_WIDTH-1:0]         last_leaves_qty,
    output wire [SEQ_WIDTH-1:0]         last_report_seq,
    output wire                         replay_chunk_commit,
    output wire                         replay_chunk_is_eof,
    output wire                         replay_error,
    output wire [ERR_WIDTH-1:0]         replay_error_code,

    output wire                         symbol_hit,
    output wire                         unmatched_symbol,

    output wire                         decoder_market_valid,
    output wire [`HFT_MSG_TYPE_WIDTH-1:0] decoder_market_msg_type,
    output wire [`HFT_ACTION_WIDTH-1:0] decoder_market_action,
    output wire                         decoder_market_side,
    output wire [`HFT_LEVEL_WIDTH-1:0]  decoder_market_level,
    output wire [PRICE_WIDTH-1:0]       decoder_market_price,
    output wire [QTY_WIDTH-1:0]         decoder_market_qty,
    output wire [7:0]                   decoder_market_entry_index,
    output wire [7:0]                   decoder_market_entry_count,
    output wire                         spec_candidate_valid,
    output wire [`HFT_MSG_TYPE_WIDTH-1:0] spec_candidate_msg_type,
    output wire [`HFT_ACTION_WIDTH-1:0] spec_candidate_action,
    output wire                         spec_candidate_side,
    output wire [`HFT_LEVEL_WIDTH-1:0]  spec_candidate_level,
    output wire [PRICE_WIDTH-1:0]       spec_candidate_price,
    output wire [QTY_WIDTH-1:0]         spec_candidate_qty,
    output wire [SEQ_WIDTH-1:0]         spec_candidate_seq,
    output wire [7:0]                   spec_candidate_entry_index,
    output wire [7:0]                   spec_candidate_entry_count,
    output wire                         decoder_order_valid,
    output wire [7:0]                   decoder_order_msg_type,

    // I5 committed execution event for the shared futures risk core.
    output wire                         risk_commit_valid,
    output wire [7:0]                   risk_commit_msg_type,
    output wire [7:0]                   risk_commit_status_code,
    output wire [7:0]                   risk_commit_exec_type,
    output wire [31:0]                  risk_commit_order_id,
    output wire                         risk_commit_side,
    output wire [7:0]                   risk_commit_position_effect,
    output wire [31:0]                  risk_commit_order_price,
    output wire [15:0]                  risk_commit_last_qty,
    output wire [15:0]                  risk_commit_leaves_qty,
    output wire [15:0]                  risk_commit_before_qty,
    output wire [31:0]                  risk_commit_report_seq,
    output wire                         risk_commit_is_replay,
    output wire                         risk_commit_metadata_error
);

    wire legacy_market_in_ready;

    wire legacy_market_valid;
    wire [`HFT_MSG_TYPE_WIDTH-1:0] legacy_market_msg_type;
    wire [`HFT_ACTION_WIDTH-1:0] legacy_market_action;
    wire legacy_market_side;
    wire [`HFT_LEVEL_WIDTH-1:0] legacy_market_level;
    wire [PRICE_WIDTH-1:0] legacy_market_price;
    wire [QTY_WIDTH-1:0] legacy_market_qty;
    wire [SEQ_WIDTH-1:0] legacy_market_seq;
    wire [SEQ_WIDTH-1:0] legacy_market_prod_seq;
    wire [7:0] legacy_market_entry_index;
    wire [7:0] legacy_market_entry_count;
    wire [39:0] legacy_market_price_bcd;
    wire [31:0] legacy_market_qty_bcd;
    wire legacy_market_ctrl_valid_unused;
    wire [`HFT_MSG_TYPE_WIDTH-1:0] legacy_market_ctrl_msg_type_unused;
    wire legacy_i002_valid_unused;
    wire legacy_i010_valid_unused;
    wire [31:0] legacy_i002_sequence_value;
    wire legacy_i002_sequence_reset_unused;
    wire legacy_market_sequence_reset_seen;
    wire [15:0] legacy_i010_product_id;
    wire [15:0] legacy_i010_symbol_code;
    wire legacy_i010_product_enable;
    wire legacy_product_info_valid;
    wire legacy_market_packet_ok;
    wire legacy_market_packet_bad;
    wire legacy_market_error_valid;
    wire [ERR_WIDTH-1:0] legacy_market_error_code;

    wire spec_market_valid;
    wire [`HFT_MSG_TYPE_WIDTH-1:0] spec_market_msg_type;
    wire [`HFT_ACTION_WIDTH-1:0] spec_market_action;
    wire spec_market_side;
    wire [`HFT_LEVEL_WIDTH-1:0] spec_market_level;
    wire [PRICE_WIDTH-1:0] spec_market_price;
    wire [QTY_WIDTH-1:0] spec_market_qty;
    wire [SEQ_WIDTH-1:0] spec_market_seq;
    wire [SEQ_WIDTH-1:0] spec_market_prod_seq;
    wire [7:0] spec_market_entry_index;
    wire [7:0] spec_market_entry_count;
    wire [39:0] spec_market_price_bcd;
    wire [31:0] spec_market_qty_bcd;
    wire spec_market_ctrl_valid_unused;
    wire [`HFT_MSG_TYPE_WIDTH-1:0] spec_market_ctrl_msg_type_unused;
    wire spec_i002_valid_unused;
    wire spec_i010_valid_unused;
    wire [31:0] spec_i002_sequence_value;
    wire spec_i002_sequence_reset_unused;
    wire spec_market_sequence_reset_seen;
    wire [15:0] spec_i010_product_id;
    wire [15:0] spec_i010_symbol_code;
    wire spec_i010_product_enable;
    wire spec_product_info_valid;
    wire spec_market_packet_ok;
    wire spec_market_packet_bad;
    wire spec_market_error_valid;
    wire [ERR_WIDTH-1:0] spec_market_error_code;
    wire spec_event_overflow_unused;

    wire selected_market_valid =
        ENABLE_SPECULATIVE_MARKET_DECODE ? spec_market_valid : legacy_market_valid;
    wire [`HFT_MSG_TYPE_WIDTH-1:0] selected_market_msg_type =
        ENABLE_SPECULATIVE_MARKET_DECODE ? spec_market_msg_type : legacy_market_msg_type;
    wire [`HFT_ACTION_WIDTH-1:0] selected_market_action =
        ENABLE_SPECULATIVE_MARKET_DECODE ? spec_market_action : legacy_market_action;
    wire selected_market_side =
        ENABLE_SPECULATIVE_MARKET_DECODE ? spec_market_side : legacy_market_side;
    wire [`HFT_LEVEL_WIDTH-1:0] selected_market_level =
        ENABLE_SPECULATIVE_MARKET_DECODE ? spec_market_level : legacy_market_level;
    wire [PRICE_WIDTH-1:0] selected_market_price =
        ENABLE_SPECULATIVE_MARKET_DECODE ? spec_market_price : legacy_market_price;
    wire [QTY_WIDTH-1:0] selected_market_qty =
        ENABLE_SPECULATIVE_MARKET_DECODE ? spec_market_qty : legacy_market_qty;
    wire [SEQ_WIDTH-1:0] selected_market_seq =
        ENABLE_SPECULATIVE_MARKET_DECODE ? spec_market_seq : legacy_market_seq;
    wire [SEQ_WIDTH-1:0] selected_market_prod_seq =
        ENABLE_SPECULATIVE_MARKET_DECODE ? spec_market_prod_seq : legacy_market_prod_seq;
    wire [7:0] selected_market_entry_index =
        ENABLE_SPECULATIVE_MARKET_DECODE ? spec_market_entry_index : legacy_market_entry_index;
    wire [7:0] selected_market_entry_count =
        ENABLE_SPECULATIVE_MARKET_DECODE ? spec_market_entry_count : legacy_market_entry_count;
    wire [39:0] selected_market_price_bcd =
        ENABLE_SPECULATIVE_MARKET_DECODE ? spec_market_price_bcd : legacy_market_price_bcd;
    wire [31:0] selected_market_qty_bcd =
        ENABLE_SPECULATIVE_MARKET_DECODE ? spec_market_qty_bcd : legacy_market_qty_bcd;

    wire [SEQ_WIDTH-1:0] decoder_order_seq;
    wire [39:0] decoder_order_no;
    wire [31:0] decoder_order_id;
    wire [`HFT_STATUS_WIDTH-1:0] decoder_order_status;
    wire [`HFT_STATUS_WIDTH-1:0] decoder_order_exec_type;
    wire decoder_order_side;
    wire [PRICE_WIDTH-1:0] decoder_order_price;
    wire [QTY_WIDTH-1:0] decoder_order_qty;
    wire [PRICE_WIDTH-1:0] decoder_order_last_price;
    wire [QTY_WIDTH-1:0] decoder_order_last_qty;
    wire [QTY_WIDTH-1:0] decoder_order_leaves_qty;
    wire [31:0] decoder_order_report_seq;
    wire replay_order_valid;
    wire [7:0] replay_order_msg_type;
    wire [SEQ_WIDTH-1:0] replay_order_seq;
    wire [39:0] replay_order_no;
    wire [31:0] replay_order_id;
    wire [`HFT_STATUS_WIDTH-1:0] replay_order_status;
    wire [`HFT_STATUS_WIDTH-1:0] replay_order_exec_type;
    wire replay_order_side;
    wire [PRICE_WIDTH-1:0] replay_order_price;
    wire [QTY_WIDTH-1:0] replay_order_qty;
    wire [PRICE_WIDTH-1:0] replay_order_last_price;
    wire [QTY_WIDTH-1:0] replay_order_last_qty;
    wire [QTY_WIDTH-1:0] replay_order_leaves_qty;
    wire [31:0] replay_order_report_seq;
    wire replay_decoder_packet_bad;
    wire replay_decoder_error_valid;
    wire [ERR_WIDTH-1:0] replay_decoder_error_code;
    wire replay_stream_valid, replay_stream_ready, replay_stream_last;
    wire [DATA_WIDTH-1:0] replay_stream_data;
    wire [KEEP_WIDTH-1:0] replay_stream_keep;
    wire replay_owner_commit, replay_owner_commit_is_replay;
    wire replay_owner_duplicate, replay_owner_error;
    wire [ERR_WIDTH-1:0] replay_owner_error_code;
    wire [SEQ_WIDTH-1:0] owner_last_committed_seq;
    wire replay_busy;

    // I5 side-band futures metadata.  The same parser observes both the live
    // order-report stream and the replay stream produced by the frozen replay
    // engine.  Mutation authority remains the frozen report-sequence owner.
    wire live_meta_valid;
    wire [7:0] live_meta_msg_type;
    wire [31:0] live_meta_order_id;
    wire [31:0] live_meta_report_seq;
    wire [7:0] live_meta_position_effect;
    wire [15:0] live_meta_before_qty;
    wire replay_meta_valid;
    wire [7:0] replay_meta_msg_type;
    wire [31:0] replay_meta_order_id;
    wire [31:0] replay_meta_report_seq;
    wire [7:0] replay_meta_position_effect;
    wire [15:0] replay_meta_before_qty;
    wire decoder_session_startup_seen_unused;
    wire decoder_session_login_seen_unused;
    wire [7:0] decoder_r04_status_code_unused;
    wire [31:0] decoder_r04_session_seq_unused;

    wire common_error_valid_unused;
    wire [ERR_WIDTH-1:0] common_error_code_unused;

    wire [SYMBOL_WIDTH-1:0] ob_market_symbol =
        force_market_symbol_en ? force_market_symbol : DEFAULT_MARKET_SYMBOL;

    wire live_report_candidate = decoder_order_valid &&
        ((decoder_order_msg_type == 8'd102) || (decoder_order_msg_type == 8'd132) ||
         (decoder_order_msg_type == 8'd122));
    wire owner_candidate_valid = ENABLE_TMP_REPLAY && (replay_order_valid || live_report_candidate);
    wire owner_candidate_replay = replay_order_valid;
    wire committed_from_replay = replay_owner_commit && replay_owner_commit_is_replay;
    wire committed_from_live_report = replay_owner_commit && !replay_owner_commit_is_replay;
    wire committed_live_nonreport = decoder_order_valid && !live_report_candidate;
    wire committed_order_valid = ENABLE_TMP_REPLAY ?
        (committed_from_replay || committed_from_live_report || committed_live_nonreport) : decoder_order_valid;
    wire use_replay_fields = ENABLE_TMP_REPLAY && committed_from_replay;
    wire [7:0] committed_order_msg_type = use_replay_fields ? replay_order_msg_type : decoder_order_msg_type;
    wire [SEQ_WIDTH-1:0] committed_order_seq = use_replay_fields ? replay_order_seq : decoder_order_seq;
    wire [39:0] committed_order_no = use_replay_fields ? replay_order_no : decoder_order_no;
    wire [31:0] committed_order_id = use_replay_fields ? replay_order_id : decoder_order_id;
    wire [`HFT_STATUS_WIDTH-1:0] committed_order_status = use_replay_fields ? replay_order_status : decoder_order_status;
    wire [`HFT_STATUS_WIDTH-1:0] committed_order_exec_type = use_replay_fields ? replay_order_exec_type : decoder_order_exec_type;
    wire committed_order_side = use_replay_fields ? replay_order_side : decoder_order_side;
    wire [PRICE_WIDTH-1:0] committed_order_price = use_replay_fields ? replay_order_price : decoder_order_price;
    wire [QTY_WIDTH-1:0] committed_order_qty = use_replay_fields ? replay_order_qty : decoder_order_qty;
    wire [PRICE_WIDTH-1:0] committed_order_last_price = use_replay_fields ? replay_order_last_price : decoder_order_last_price;
    wire [QTY_WIDTH-1:0] committed_order_last_qty = use_replay_fields ? replay_order_last_qty : decoder_order_last_qty;
    wire [QTY_WIDTH-1:0] committed_order_leaves_qty = use_replay_fields ? replay_order_leaves_qty : decoder_order_leaves_qty;
    wire [31:0] committed_order_report_seq = use_replay_fields ? replay_order_report_seq : decoder_order_report_seq;

    wire [63:0] ob_order_no = {24'd0, committed_order_no};
    wire [63:0] ob_order_id = {32'd0, committed_order_id};
    wire [SEQ_WIDTH-1:0] ob_order_report_seq = committed_order_report_seq[SEQ_WIDTH-1:0];
    reg [SEQ_WIDTH-1:0] legacy_last_report_seq;
    assign last_report_seq = ENABLE_TMP_REPLAY ? owner_last_committed_seq : legacy_last_report_seq;

    // Preserve the pre-SC2B registered last-seen behavior for legacy/test
    // configurations.  The active replay configuration instead exposes the
    // persistent committed owner above.
    always @(posedge clk) begin
        if (!rst_n)
            legacy_last_report_seq <= {SEQ_WIDTH{1'b0}};
        else if (!ENABLE_TMP_REPLAY && decoder_order_valid)
            legacy_last_report_seq <= decoder_order_report_seq[SEQ_WIDTH-1:0];
    end

    assign market_in_ready = ENABLE_SPECULATIVE_MARKET_DECODE ? 1'b1 : legacy_market_in_ready;

    assign decoder_market_valid = selected_market_valid;
    assign decoder_market_msg_type = selected_market_msg_type;
    assign decoder_market_action = selected_market_action;
    assign decoder_market_side = selected_market_side;
    assign decoder_market_level = selected_market_level;
    assign decoder_market_price = selected_market_price;
    assign decoder_market_qty = selected_market_qty;
    assign decoder_market_entry_index = selected_market_entry_index;
    assign decoder_market_entry_count = selected_market_entry_count;

    assign market_packet_ok =
        ENABLE_SPECULATIVE_MARKET_DECODE ? spec_market_packet_ok : legacy_market_packet_ok;
    assign market_packet_bad =
        ENABLE_SPECULATIVE_MARKET_DECODE ? spec_market_packet_bad : legacy_market_packet_bad;
    assign market_error_valid =
        ENABLE_SPECULATIVE_MARKET_DECODE ? spec_market_error_valid : legacy_market_error_valid;
    assign market_error_code =
        ENABLE_SPECULATIVE_MARKET_DECODE ? spec_market_error_code : legacy_market_error_code;
    assign product_info_valid =
        ENABLE_SPECULATIVE_MARKET_DECODE ? spec_product_info_valid : legacy_product_info_valid;
    assign i010_product_id =
        ENABLE_SPECULATIVE_MARKET_DECODE ? spec_i010_product_id : legacy_i010_product_id;
    assign i010_symbol_code =
        ENABLE_SPECULATIVE_MARKET_DECODE ? spec_i010_symbol_code : legacy_i010_symbol_code;
    assign i010_product_enable =
        ENABLE_SPECULATIVE_MARKET_DECODE ? spec_i010_product_enable : legacy_i010_product_enable;
    assign market_sequence_reset_seen =
        ENABLE_SPECULATIVE_MARKET_DECODE ? spec_market_sequence_reset_seen : legacy_market_sequence_reset_seen;
    assign i002_sequence_value =
        ENABLE_SPECULATIVE_MARKET_DECODE ? spec_i002_sequence_value : legacy_i002_sequence_value;

    financial_decoder_fast_dual_path_top #(
        .DATA_WIDTH(DATA_WIDTH),
        .KEEP_WIDTH(KEEP_WIDTH),
        .MSG_TYPE_WIDTH(`HFT_MSG_TYPE_WIDTH),
        .ACTION_WIDTH(`HFT_ACTION_WIDTH),
        .SEQ_WIDTH(SEQ_WIDTH),
        .PRICE_WIDTH(PRICE_WIDTH),
        .QTY_WIDTH(QTY_WIDTH),
        .LEVEL_WIDTH(`HFT_LEVEL_WIDTH),
        .STATUS_WIDTH(`HFT_STATUS_WIDTH),
        .ERR_WIDTH(ERR_WIDTH),
        .OUTPUT_RAW_BCD(1'b0)
    ) u_financial_decoder (
        .clk(clk),
        .rst_n(rst_n),
        .market_in_valid(ENABLE_SPECULATIVE_MARKET_DECODE ? 1'b0 : market_in_valid),
        .market_in_ready(legacy_market_in_ready),
        .market_in_data(market_in_data),
        .market_in_keep(market_in_keep),
        .market_in_last(market_in_last),
        .order_in_valid(order_in_valid),
        .order_in_ready(order_in_ready),
        .order_in_data(order_in_data),
        .order_in_keep(order_in_keep),
        .order_in_last(order_in_last),
        .market_valid(legacy_market_valid),
        .market_msg_type(legacy_market_msg_type),
        .market_seq(legacy_market_seq),
        .market_action(legacy_market_action),
        .market_side(legacy_market_side),
        .market_level(legacy_market_level),
        .market_price(legacy_market_price),
        .market_price_bcd(legacy_market_price_bcd),
        .market_qty(legacy_market_qty),
        .market_qty_bcd(legacy_market_qty_bcd),
        .market_prod_seq(legacy_market_prod_seq),
        .market_entry_index(legacy_market_entry_index),
        .market_entry_count(legacy_market_entry_count),
        .market_ctrl_valid(legacy_market_ctrl_valid_unused),
        .market_ctrl_msg_type(legacy_market_ctrl_msg_type_unused),
        .i002_valid(legacy_i002_valid_unused),
        .i010_valid(legacy_i010_valid_unused),
        .i002_sequence_value(legacy_i002_sequence_value),
        .i002_sequence_reset(legacy_i002_sequence_reset_unused),
        .market_sequence_reset_seen(legacy_market_sequence_reset_seen),
        .i010_product_id(legacy_i010_product_id),
        .i010_symbol_code(legacy_i010_symbol_code),
        .i010_product_enable(legacy_i010_product_enable),
        .product_info_valid(legacy_product_info_valid),
        .order_valid(decoder_order_valid),
        .order_msg_type(decoder_order_msg_type),
        .order_seq(decoder_order_seq),
        .order_no(decoder_order_no),
        .order_id(decoder_order_id),
        .order_status(decoder_order_status),
        .order_exec_type(decoder_order_exec_type),
        .order_side(decoder_order_side),
        .order_price(decoder_order_price),
        .order_qty(decoder_order_qty),
        .order_last_price(decoder_order_last_price),
        .order_last_qty(decoder_order_last_qty),
        .order_leaves_qty(decoder_order_leaves_qty),
        .order_report_seq(decoder_order_report_seq),
        .session_event_valid(session_event_valid),
        .session_msg_type(session_msg_type),
        .l10_valid(l10_valid),
        .l30_valid(l30_valid),
        .l30_status_code(l30_status_code),
        .l30_append_no(l30_append_no),
        .l30_end_out_bound_num(l30_end_out_bound_num),
        .l30_system_type(l30_system_type),
        .l30_encrypt_method(l30_encrypt_method),
        .l41_valid(l41_valid),
        .l50_valid(l50_valid),
        .l50_status_code(l50_status_code),
        .l50_heartbt_int(l50_heartbt_int),
        .l50_max_flow_ctrl_cnt(l50_max_flow_ctrl_cnt),
        .l80_valid(l80_valid),
        .l80_status_code(l80_status_code),
        .r04_valid(r04_valid),
        .r05_valid(r05_valid),
        .r05_status_code(r05_status_code),
        .session_startup_seen(decoder_session_startup_seen_unused),
        .session_login_seen(decoder_session_login_seen_unused),
        .app_subsystem_ready(app_subsystem_ready),
        .connection_status_valid(connection_status_valid),
        .r05_req_valid(r05_req_valid),
        .r04_status_code(decoder_r04_status_code_unused),
        .r04_session_seq(decoder_r04_session_seq_unused),
        .market_packet_ok(legacy_market_packet_ok),
        .market_packet_bad(legacy_market_packet_bad),
        .market_error_valid(legacy_market_error_valid),
        .market_error_code(legacy_market_error_code),
        .order_packet_ok(order_packet_ok),
        .order_packet_bad(order_packet_bad),
        .order_error_valid(order_error_valid),
        .order_error_code(order_error_code),
        .common_error_valid(common_error_valid_unused),
        .common_error_code(common_error_code_unused)
    );

    hft_tmp_exec_metadata_tap_v2 u_i5_live_exec_meta (
        .clk(clk), .rst_n(rst_n),
        .tap_valid(order_in_valid && order_in_ready),
        .tap_data(order_in_data), .tap_keep(order_in_keep), .tap_last(order_in_last),
        .metadata_valid(live_meta_valid), .last_msg_type(live_meta_msg_type),
        .last_order_id(live_meta_order_id), .last_report_seq(live_meta_report_seq),
        .last_position_effect(live_meta_position_effect),
        .last_before_qty(live_meta_before_qty)
    );

    hft_tmp_exec_metadata_tap_v2 u_i5_replay_exec_meta (
        .clk(clk), .rst_n(rst_n),
        .tap_valid(ENABLE_TMP_REPLAY && replay_stream_valid && replay_stream_ready),
        .tap_data(replay_stream_data), .tap_keep(replay_stream_keep),
        .tap_last(replay_stream_last),
        .metadata_valid(replay_meta_valid), .last_msg_type(replay_meta_msg_type),
        .last_order_id(replay_meta_order_id), .last_report_seq(replay_meta_report_seq),
        .last_position_effect(replay_meta_position_effect),
        .last_before_qty(replay_meta_before_qty)
    );

    // Match the futures-only sideband against the frozen committed event.
    // This module owns the short-lived live/replay metadata cache so the same
    // contract is covered independently by CI.
    hft_rmic_committed_exec_event_adapter_v1 #(.QTY_W(16)) u_i5_commit_adapter (
        .clk(clk), .rst_n(rst_n),
        .live_meta_valid(live_meta_valid),
        .live_meta_msg_type(live_meta_msg_type),
        .live_meta_order_id(live_meta_order_id),
        .live_meta_report_seq(live_meta_report_seq),
        .live_meta_position_effect(live_meta_position_effect),
        .live_meta_before_qty(live_meta_before_qty),
        .replay_meta_valid(replay_meta_valid),
        .replay_meta_msg_type(replay_meta_msg_type),
        .replay_meta_order_id(replay_meta_order_id),
        .replay_meta_report_seq(replay_meta_report_seq),
        .replay_meta_position_effect(replay_meta_position_effect),
        .replay_meta_before_qty(replay_meta_before_qty),
        .committed_valid(committed_order_valid),
        .committed_from_replay(committed_from_replay),
        .committed_msg_type(committed_order_msg_type),
        .committed_status_code(committed_order_status),
        .committed_exec_type(committed_order_exec_type),
        .committed_order_id(committed_order_id),
        .committed_side(committed_order_side),
        .committed_order_price(committed_order_price),
        .committed_last_qty(committed_order_last_qty[15:0]),
        .committed_leaves_qty(committed_order_leaves_qty[15:0]),
        .committed_report_seq(committed_order_report_seq),
        .risk_commit_valid(risk_commit_valid),
        .risk_commit_msg_type(risk_commit_msg_type),
        .risk_commit_status_code(risk_commit_status_code),
        .risk_commit_exec_type(risk_commit_exec_type),
        .risk_commit_order_id(risk_commit_order_id),
        .risk_commit_side(risk_commit_side),
        .risk_commit_position_effect(risk_commit_position_effect),
        .risk_commit_order_price(risk_commit_order_price),
        .risk_commit_last_qty(risk_commit_last_qty),
        .risk_commit_leaves_qty(risk_commit_leaves_qty),
        .risk_commit_before_qty(risk_commit_before_qty),
        .risk_commit_report_seq(risk_commit_report_seq),
        .risk_commit_is_replay(risk_commit_is_replay),
        .metadata_error(risk_commit_metadata_error)
    );

    hft_l41_replay_engine #(
        .DATA_WIDTH(DATA_WIDTH), .KEEP_WIDTH(KEEP_WIDTH), .ERR_WIDTH(ERR_WIDTH)
    ) u_l41_replay_engine (
        .clk(clk), .rst_n(rst_n),
        .tap_valid(ENABLE_TMP_REPLAY && order_in_valid && order_in_ready),
        .tap_data(order_in_data), .tap_keep(order_in_keep), .tap_last(order_in_last),
        .l41_commit(ENABLE_TMP_REPLAY && l41_valid),
        .report_valid(replay_stream_valid), .report_ready(replay_stream_ready),
        .report_data(replay_stream_data), .report_keep(replay_stream_keep),
        .report_last(replay_stream_last),
        .report_result_valid(replay_owner_commit | replay_owner_duplicate | replay_owner_error |
                             replay_decoder_packet_bad | replay_decoder_error_valid),
        .report_result_ok(replay_owner_commit | replay_owner_duplicate),
        .chunk_commit(replay_chunk_commit), .chunk_is_eof(replay_chunk_is_eof),
        .replay_error(replay_error), .replay_error_code(replay_error_code),
        .replay_busy(replay_busy)
    );

    tmp_order_fast_decoder #(
        .DATA_WIDTH(DATA_WIDTH), .KEEP_WIDTH(KEEP_WIDTH), .SEQ_WIDTH(SEQ_WIDTH),
        .PRICE_WIDTH(PRICE_WIDTH), .QTY_WIDTH(QTY_WIDTH),
        .STATUS_WIDTH(`HFT_STATUS_WIDTH), .ERR_WIDTH(ERR_WIDTH)
    ) u_replay_order_decoder (
        .clk(clk), .rst_n(rst_n), .in_valid(ENABLE_TMP_REPLAY && replay_stream_valid),
        .in_ready(replay_stream_ready), .in_data(replay_stream_data),
        .in_keep(replay_stream_keep), .in_last(replay_stream_last),
        .order_valid(replay_order_valid), .order_msg_type(replay_order_msg_type),
        .order_seq(replay_order_seq), .order_no(replay_order_no),
        .order_status(replay_order_status), .order_exec_type(replay_order_exec_type),
        .order_id(replay_order_id), .order_side(replay_order_side),
        .order_price(replay_order_price), .order_qty(replay_order_qty),
        .order_last_price(replay_order_last_price), .order_last_qty(replay_order_last_qty),
        .order_leaves_qty(replay_order_leaves_qty), .order_report_seq(replay_order_report_seq),
        .session_event_valid(), .session_msg_type(), .l10_valid(), .l30_valid(),
        .l30_status_code(), .l30_append_no(), .l30_end_out_bound_num(),
        .l30_system_type(), .l30_encrypt_method(), .l41_valid(), .l50_valid(),
        .l50_status_code(), .l50_heartbt_int(), .l50_max_flow_ctrl_cnt(),
        .l80_valid(), .l80_status_code(), .r04_valid(), .r05_valid(),
        .r05_status_code(), .session_startup_seen(),
        .session_login_seen(), .app_subsystem_ready(), .connection_status_valid(),
        .r05_req_valid(), .r04_status_code(), .r04_session_seq(), .packet_ok(),
        .packet_bad(replay_decoder_packet_bad), .error_valid(replay_decoder_error_valid),
        .error_code(replay_decoder_error_code), .latency_cycles()
    );

    hft_report_sequence_owner #(
        .SEQ_WIDTH(SEQ_WIDTH), .ERR_WIDTH(ERR_WIDTH)
    ) u_report_sequence_owner (
        .clk(clk), .rst_n(rst_n), .candidate_valid(owner_candidate_valid),
        .candidate_msg_type(owner_candidate_replay ? replay_order_msg_type : decoder_order_msg_type),
        .candidate_seq(owner_candidate_replay ? replay_order_seq : decoder_order_seq),
        .candidate_is_replay(owner_candidate_replay), .commit_valid(replay_owner_commit),
        .commit_is_replay(replay_owner_commit_is_replay),
        .duplicate_drop(replay_owner_duplicate), .error_valid(replay_owner_error),
        .error_code(replay_owner_error_code), .last_committed_seq(owner_last_committed_seq)
    );

    hft_market_speculative_commit_decoder #(
        .DATA_WIDTH(DATA_WIDTH),
        .KEEP_WIDTH(KEEP_WIDTH),
        .MSG_TYPE_WIDTH(`HFT_MSG_TYPE_WIDTH),
        .ACTION_WIDTH(`HFT_ACTION_WIDTH),
        .SEQ_WIDTH(SEQ_WIDTH),
        .PRICE_WIDTH(PRICE_WIDTH),
        .QTY_WIDTH(QTY_WIDTH),
        .LEVEL_WIDTH(`HFT_LEVEL_WIDTH),
        .ERR_WIDTH(ERR_WIDTH),
        .EVENT_FIFO_DEPTH(5)
    ) u_speculative_market_decoder (
        .clk(clk),
        .rst_n(rst_n),
        .spec_valid(ENABLE_SPECULATIVE_MARKET_DECODE ? spec_market_in_valid : 1'b0),
        .spec_data(ENABLE_SPECULATIVE_MARKET_DECODE ? spec_market_in_data : {DATA_WIDTH{1'b0}}),
        .spec_keep(ENABLE_SPECULATIVE_MARKET_DECODE ? spec_market_in_keep : {KEEP_WIDTH{1'b0}}),
        .spec_last(ENABLE_SPECULATIVE_MARKET_DECODE ? spec_market_in_last : 1'b0),
        .commit_valid(ENABLE_SPECULATIVE_MARKET_DECODE ? spec_market_commit : 1'b0),
        .squash_valid(ENABLE_SPECULATIVE_MARKET_DECODE ? spec_market_squash : 1'b0),
        .market_valid(spec_market_valid),
        .market_msg_type(spec_market_msg_type),
        .market_action(spec_market_action),
        .market_side(spec_market_side),
        .market_level(spec_market_level),
        .market_price(spec_market_price),
        .market_qty(spec_market_qty),
        .market_seq(spec_market_seq),
        .market_prod_seq(spec_market_prod_seq),
        .market_entry_index(spec_market_entry_index),
        .market_entry_count(spec_market_entry_count),
        .market_price_bcd(spec_market_price_bcd),
        .market_qty_bcd(spec_market_qty_bcd),
        .market_ctrl_valid(spec_market_ctrl_valid_unused),
        .market_ctrl_msg_type(spec_market_ctrl_msg_type_unused),
        .i002_valid(spec_i002_valid_unused),
        .i010_valid(spec_i010_valid_unused),
        .i002_sequence_value(spec_i002_sequence_value),
        .i002_sequence_reset(spec_i002_sequence_reset_unused),
        .market_sequence_reset_seen(spec_market_sequence_reset_seen),
        .i010_product_id(spec_i010_product_id),
        .i010_symbol_code(spec_i010_symbol_code),
        .i010_product_enable(spec_i010_product_enable),
        .product_info_valid(spec_product_info_valid),
        .packet_ok(spec_market_packet_ok),
        .packet_bad(spec_market_packet_bad),
        .error_valid(spec_market_error_valid),
        .error_code(spec_market_error_code),
        .event_overflow(spec_event_overflow_unused)
        ,.candidate_valid(spec_candidate_valid)
        ,.candidate_msg_type(spec_candidate_msg_type)
        ,.candidate_action(spec_candidate_action)
        ,.candidate_side(spec_candidate_side)
        ,.candidate_level(spec_candidate_level)
        ,.candidate_price(spec_candidate_price)
        ,.candidate_qty(spec_candidate_qty)
        ,.candidate_seq(spec_candidate_seq)
        ,.candidate_entry_index(spec_candidate_entry_index)
        ,.candidate_entry_count(spec_candidate_entry_count)
    );

    order_book_multi_symbol_system_top #(
        .BOOK_COUNT(BOOK_COUNT),
        .BOOK_LEVELS(BOOK_LEVELS),
        .SYMBOL_WIDTH(SYMBOL_WIDTH),
        .PRICE_WIDTH(PRICE_WIDTH),
        .QTY_WIDTH(QTY_WIDTH),
        .SEQ_WIDTH(SEQ_WIDTH),
        .SYMBOL0(SYMBOL0),
        .SYMBOL1(SYMBOL1),
        .SYMBOL2(SYMBOL2),
        .SYMBOL3(SYMBOL3)
    ) u_order_book_system (
        .clk(clk),
        .rst_n(rst_n),
        .market_valid(selected_market_valid),
        .market_symbol(ob_market_symbol),
        .market_msg_type(selected_market_msg_type),
        .market_action(selected_market_action),
        .market_side(selected_market_side),
        .market_level(selected_market_level),
        .market_price(selected_market_price),
        .market_price_bcd(selected_market_price_bcd),
        .market_qty(selected_market_qty),
        .market_qty_bcd(selected_market_qty_bcd),
        .market_seq(selected_market_seq),
        .market_prod_seq(selected_market_prod_seq),
        .market_entry_index(selected_market_entry_index),
        .market_entry_count(selected_market_entry_count),
        .order_valid(committed_order_valid),
        .order_msg_type(committed_order_msg_type),
        .order_seq(committed_order_seq),
        .order_no(ob_order_no),
        .order_id(ob_order_id),
        .order_status(committed_order_status),
        .order_exec_type(committed_order_exec_type),
        .order_side(committed_order_side),
        .order_price(committed_order_price),
        .order_qty(committed_order_qty),
        .order_last_price(committed_order_last_price),
        .order_last_qty(committed_order_last_qty),
        .order_leaves_qty(committed_order_leaves_qty),
        .order_report_seq(ob_order_report_seq),
        .selected_book_id(selected_book_id),
        .symbol_hit(symbol_hit),
        .unmatched_symbol(unmatched_symbol),
        .selected_book_valid(selected_book_valid),
        .selected_book_update_valid(selected_book_update_valid),
        .selected_book_stale(selected_book_stale),
        .selected_book_crossed(selected_book_crossed),
        .selected_strategy_ready(selected_strategy_ready),
        .selected_best_bid_price(selected_best_bid_price),
        .selected_best_bid_qty(selected_best_bid_qty),
        .selected_best_ask_price(selected_best_ask_price),
        .selected_best_ask_qty(selected_best_ask_qty),
        .selected_spread(selected_spread),
        .selected_bid_price_level_flat(selected_bid_price_level_flat),
        .selected_bid_qty_level_flat(selected_bid_qty_level_flat),
        .selected_ask_price_level_flat(selected_ask_price_level_flat),
        .selected_ask_qty_level_flat(selected_ask_qty_level_flat),
        .all_book_valid(all_book_valid),
        .all_book_stale(all_book_stale),
        .all_book_crossed(all_book_crossed),
        .all_strategy_ready(all_strategy_ready),
        .last_trade_valid(last_trade_valid),
        .last_trade_seq(last_trade_seq),
        .last_trade_price(last_trade_price),
        .last_trade_qty(last_trade_qty),
        .last_order_valid(order_state_valid),
        .last_order_msg_type(),
        .last_order_no(last_order_no),
        .last_order_id(last_order_id),
        .last_order_rejected(last_order_rejected),
        .last_order_filled(last_order_filled),
        .last_order_partially_filled(last_order_partially_filled)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            last_trade_price_bcd <= 40'd0;
            last_trade_qty_bcd <= 32'd0;
            last_order_status <= {`HFT_STATUS_WIDTH{1'b0}};
            last_exec_type <= {`HFT_STATUS_WIDTH{1'b0}};
            last_order_price <= {PRICE_WIDTH{1'b0}};
            last_order_qty <= {QTY_WIDTH{1'b0}};
            last_last_price <= {PRICE_WIDTH{1'b0}};
            last_last_qty <= {QTY_WIDTH{1'b0}};
            last_leaves_qty <= {QTY_WIDTH{1'b0}};
        end else begin
            if (selected_market_valid && (selected_market_msg_type == `HFT_MSG_TRADE)) begin
                last_trade_price_bcd <= selected_market_price_bcd;
                last_trade_qty_bcd <= selected_market_qty_bcd;
            end

            if (committed_order_valid) begin
                last_order_status <= committed_order_status;
                last_exec_type <= committed_order_exec_type;
                last_order_price <= committed_order_price;
                last_order_qty <= committed_order_qty;
                last_last_price <= committed_order_last_price;
                last_last_qty <= committed_order_last_qty;
                last_leaves_qty <= committed_order_leaves_qty;
            end
        end
    end

endmodule
