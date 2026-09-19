`timescale 1ns/1ps
`include "hft_rmic_accounting_defs.svh"
`include "hft_rmic_policy_defs.svh"

// I2 correctness-first multi-account / multi-product futures state owner.
//
// One mutation is in flight at a time. The state table is indexed by
// (account_id, product_id) and stored in an explicit XPM block RAM for Vivado;
// Icarus uses HFT_RMIC_BEHAVIORAL_RAM. A reset clears only configured_bits,
// making every stale RAM word inaccessible until host/recovery configuration
// explicitly restores that entry. This is intentional fail-closed behavior.
//
// Physical timing note:
//   The original two-state implementation evaluated quantity transitions,
//   wide margin multipliers, budget checks and BRAM writeback in the same
//   6.4-ns cycle. I2 post-route evidence showed a 12.952-ns BRAM->DSP->BRAM
//   path (WNS -6.866 ns). The state owner therefore uses explicit stages:
//
//     BRAM read -> capture -> transition/gross -> registered multiply
//               -> decision/writeback
//
//   Transaction throughput remains serialized by design; only response latency
//   increases. Accounting semantics and ready/valid behavior are unchanged.
//
// I5 optional L0 cache:
//   ENABLE_L0_FAST_CACHE adds a single coherent write-through hot-key record.
//   A hit bypasses both BRAM CAPTURE and PREP, entering ST_MARGIN directly.
//   Misses retain the original BRAM path, and reset/config/mutation coherence
//   preserves the backing BRAM as the authoritative full table.
module hft_rmic_futures_state_manager_v1 #(
    parameter integer NUM_ACCOUNTS = 16,
    parameter integer NUM_PRODUCTS = 16,
    parameter integer ACCOUNT_ID_W = 8,
    parameter integer PRODUCT_ID_W = 8,
    parameter integer QTY_W = 32,
    parameter integer MARGIN_W = 64,
    parameter integer ENABLE_L0_FAST_CACHE = 0
) (
    input  wire clk,
    input  wire rst_n,

    input  wire                         cfg_valid,
    output wire                         cfg_ready,
    input  wire [ACCOUNT_ID_W-1:0]      cfg_account_id,
    input  wire [PRODUCT_ID_W-1:0]      cfg_product_id,
    input  wire                         cfg_enabled,
    input  wire [MARGIN_W-1:0]          cfg_margin_budget,
    input  wire [MARGIN_W-1:0]          cfg_margin_per_contract,
    input  wire [QTY_W-1:0]             cfg_long_position,
    input  wire [QTY_W-1:0]             cfg_short_position,
    input  wire [QTY_W-1:0]             cfg_pending_open_long,
    input  wire [QTY_W-1:0]             cfg_pending_open_short,
    input  wire [QTY_W-1:0]             cfg_reserved_close_long,
    input  wire [QTY_W-1:0]             cfg_reserved_close_short,
    output reg                          cfg_done,
    output reg                          cfg_ok,
    output reg [7:0]                    cfg_reason_code,

    input  wire                         req_valid,
    output wire                         req_ready,
    input  wire [ACCOUNT_ID_W-1:0]      req_account_id,
    input  wire [PRODUCT_ID_W-1:0]      req_product_id,
    input  wire [2:0]                   req_event_kind,
    input  wire                         req_side,
    input  wire [7:0]                   req_position_effect,
    input  wire [QTY_W-1:0]             req_order_qty,
    input  wire [QTY_W-1:0]             req_fill_qty,
    input  wire [QTY_W-1:0]             req_release_qty,

    output reg                          rsp_valid,
    input  wire                         rsp_ready,
    output reg                          rsp_ok,
    output reg [1:0]                    rsp_reason_source,
    output reg [7:0]                    rsp_reason_code,
    output reg [ACCOUNT_ID_W-1:0]       rsp_account_id,
    output reg [PRODUCT_ID_W-1:0]       rsp_product_id,
    output reg                          rsp_entry_enabled,
    output reg [QTY_W-1:0]              rsp_long_position,
    output reg [QTY_W-1:0]              rsp_short_position,
    output reg [QTY_W-1:0]              rsp_pending_open_long,
    output reg [QTY_W-1:0]              rsp_pending_open_short,
    output reg [QTY_W-1:0]              rsp_reserved_close_long,
    output reg [QTY_W-1:0]              rsp_reserved_close_short,
    output reg [MARGIN_W-1:0]           rsp_required_margin_before,
    output reg [MARGIN_W-1:0]           rsp_required_margin_after
);
    localparam integer ENTRY_COUNT = NUM_ACCOUNTS * NUM_PRODUCTS;
    localparam integer ADDR_W = (ENTRY_COUNT <= 2) ? 1 : $clog2(ENTRY_COUNT);
    localparam integer REC_W = 1 + (2*MARGIN_W) + (6*QTY_W);
    localparam integer SUM_W = QTY_W + 3;
    localparam integer MARGIN_CALC_W = SUM_W + MARGIN_W;

    localparam integer REC_ENABLED_BIT = 0;
    localparam integer REC_MARGIN_BUDGET_LSB = 1;
    localparam integer REC_MARGIN_PER_CONTRACT_LSB = REC_MARGIN_BUDGET_LSB + MARGIN_W;
    localparam integer REC_LONG_LSB = REC_MARGIN_PER_CONTRACT_LSB + MARGIN_W;
    localparam integer REC_SHORT_LSB = REC_LONG_LSB + QTY_W;
    localparam integer REC_PENDING_LONG_LSB = REC_SHORT_LSB + QTY_W;
    localparam integer REC_PENDING_SHORT_LSB = REC_PENDING_LONG_LSB + QTY_W;
    localparam integer REC_RESERVED_LONG_LSB = REC_PENDING_SHORT_LSB + QTY_W;
    localparam integer REC_RESERVED_SHORT_LSB = REC_RESERVED_LONG_LSB + QTY_W;

    localparam [2:0] ST_IDLE    = 3'd0;
    localparam [2:0] ST_CAPTURE = 3'd1;
    localparam [2:0] ST_PREP    = 3'd2;
    localparam [2:0] ST_MARGIN  = 3'd3;
    localparam [2:0] ST_DECIDE  = 3'd4;

    reg [2:0] state;
    reg [ENTRY_COUNT-1:0] configured_bits;

    // Optional coherent L0 state cache for the hot account/product key.
    // It is write-through to the authoritative BRAM state table and is
    // invalidated by reset.  Generic I2/I3/I4 users leave it disabled.
    reg                  l0_valid;
    reg [ADDR_W-1:0]     l0_index;
    reg [REC_W-1:0]      l0_record;
    reg                  l0_configured;

    function automatic [ADDR_W-1:0] make_index;
        input [ACCOUNT_ID_W-1:0] account_id;
        input [PRODUCT_ID_W-1:0] product_id;
        begin
            make_index = (account_id * NUM_PRODUCTS) + product_id;
        end
    endfunction

    wire cfg_key_valid = (cfg_account_id < NUM_ACCOUNTS) &&
                         (cfg_product_id < NUM_PRODUCTS);
    wire req_key_valid = (req_account_id < NUM_ACCOUNTS) &&
                         (req_product_id < NUM_PRODUCTS);
    wire [ADDR_W-1:0] cfg_index = make_index(cfg_account_id, cfg_product_id);
    wire [ADDR_W-1:0] req_index = make_index(req_account_id, req_product_id);
    wire l0_hit = (ENABLE_L0_FAST_CACHE != 0) &&
                  l0_valid && req_key_valid && (l0_index == req_index);

    assign cfg_ready = (state == ST_IDLE) && !rsp_valid;
    wire cfg_fire = cfg_valid && cfg_ready;

    // Configuration owns an idle cycle when presented.
    assign req_ready = (state == ST_IDLE) && !rsp_valid && !cfg_valid;
    wire req_fire = req_valid && req_ready;

    reg [ACCOUNT_ID_W-1:0] req_account_latched;
    reg [PRODUCT_ID_W-1:0] req_product_latched;
    reg [ADDR_W-1:0] req_index_latched;
    reg req_key_valid_latched;
    reg [2:0] req_event_latched;
    reg req_side_latched;
    reg [7:0] req_position_effect_latched;
    reg [QTY_W-1:0] req_order_qty_latched;
    reg [QTY_W-1:0] req_fill_qty_latched;
    reg [QTY_W-1:0] req_release_qty_latched;

    wire req_is_query = (req_event_latched == `HFT_RMIC_ACCT_EVENT_QUERY);
    wire req_is_mutation = (req_event_latched == `HFT_RMIC_ACCT_EVENT_RESERVE) ||
                           (req_event_latched == `HFT_RMIC_ACCT_EVENT_FILL) ||
                           (req_event_latched == `HFT_RMIC_ACCT_EVENT_RELEASE);

    // ---------------------------------------------------------------------
    // State BRAM and first pipeline register.
    // ---------------------------------------------------------------------
    wire [REC_W-1:0] ram_rd_data;
    wire ram_rd_en = req_fire && req_key_valid && !l0_hit;
    wire [ADDR_W-1:0] ram_rd_addr = req_index;

    reg [REC_W-1:0] rec_latched;
    reg entry_configured_latched;

    wire rec_enabled = rec_latched[REC_ENABLED_BIT];
    wire [MARGIN_W-1:0] rec_margin_budget =
        rec_latched[REC_MARGIN_BUDGET_LSB +: MARGIN_W];
    wire [MARGIN_W-1:0] rec_margin_per_contract =
        rec_latched[REC_MARGIN_PER_CONTRACT_LSB +: MARGIN_W];
    wire [QTY_W-1:0] rec_long = rec_latched[REC_LONG_LSB +: QTY_W];
    wire [QTY_W-1:0] rec_short = rec_latched[REC_SHORT_LSB +: QTY_W];
    wire [QTY_W-1:0] rec_pending_long = rec_latched[REC_PENDING_LONG_LSB +: QTY_W];
    wire [QTY_W-1:0] rec_pending_short = rec_latched[REC_PENDING_SHORT_LSB +: QTY_W];
    wire [QTY_W-1:0] rec_reserved_long = rec_latched[REC_RESERVED_LONG_LSB +: QTY_W];
    wire [QTY_W-1:0] rec_reserved_short = rec_latched[REC_RESERVED_SHORT_LSB +: QTY_W];

    wire l0_enabled = l0_record[REC_ENABLED_BIT];
    wire [MARGIN_W-1:0] l0_margin_budget =
        l0_record[REC_MARGIN_BUDGET_LSB +: MARGIN_W];
    wire [MARGIN_W-1:0] l0_margin_per_contract =
        l0_record[REC_MARGIN_PER_CONTRACT_LSB +: MARGIN_W];
    wire [QTY_W-1:0] l0_long = l0_record[REC_LONG_LSB +: QTY_W];
    wire [QTY_W-1:0] l0_short = l0_record[REC_SHORT_LSB +: QTY_W];
    wire [QTY_W-1:0] l0_pending_long = l0_record[REC_PENDING_LONG_LSB +: QTY_W];
    wire [QTY_W-1:0] l0_pending_short = l0_record[REC_PENDING_SHORT_LSB +: QTY_W];
    wire [QTY_W-1:0] l0_reserved_long = l0_record[REC_RESERVED_LONG_LSB +: QTY_W];
    wire [QTY_W-1:0] l0_reserved_short = l0_record[REC_RESERVED_SHORT_LSB +: QTY_W];

    // ---------------------------------------------------------------------
    // Quantity/state transition stage. No wide margin multiply exists here.
    // ---------------------------------------------------------------------
    wire transition_ok;
    wire [7:0] transition_reason;
    wire transition_margin_check_required;
    wire [QTY_W-1:0] transition_next_long;
    wire [QTY_W-1:0] transition_next_short;
    wire [QTY_W-1:0] transition_next_pending_long;
    wire [QTY_W-1:0] transition_next_pending_short;
    wire [QTY_W-1:0] transition_next_reserved_long;
    wire [QTY_W-1:0] transition_next_reserved_short;
    wire [SUM_W-1:0] transition_gross_before;
    wire [SUM_W-1:0] transition_gross_after;

    hft_rmic_futures_transition_v1 #(
        .QTY_W(QTY_W)
    ) u_transition (
        .event_kind(req_event_latched),
        .side(req_side_latched),
        .position_effect(req_position_effect_latched),
        .order_qty(req_order_qty_latched),
        .fill_qty(req_fill_qty_latched),
        .release_qty(req_release_qty_latched),
        .long_position(rec_long),
        .short_position(rec_short),
        .pending_open_long(rec_pending_long),
        .pending_open_short(rec_pending_short),
        .reserved_close_long(rec_reserved_long),
        .reserved_close_short(rec_reserved_short),
        .transition_ok(transition_ok),
        .reason_code(transition_reason),
        .margin_check_required(transition_margin_check_required),
        .next_long_position(transition_next_long),
        .next_short_position(transition_next_short),
        .next_pending_open_long(transition_next_pending_long),
        .next_pending_open_short(transition_next_pending_short),
        .next_reserved_close_long(transition_next_reserved_long),
        .next_reserved_close_short(transition_next_reserved_short),
        .gross_before(transition_gross_before),
        .gross_after_candidate(transition_gross_after)
    );

    // Cache-hit transition uses the live request and cached record so the
    // BRAM CAPTURE and registered PREP stages can both be bypassed.
    wire fast_transition_ok;
    wire [7:0] fast_transition_reason;
    wire fast_transition_margin_check_required;
    wire [QTY_W-1:0] fast_transition_next_long;
    wire [QTY_W-1:0] fast_transition_next_short;
    wire [QTY_W-1:0] fast_transition_next_pending_long;
    wire [QTY_W-1:0] fast_transition_next_pending_short;
    wire [QTY_W-1:0] fast_transition_next_reserved_long;
    wire [QTY_W-1:0] fast_transition_next_reserved_short;
    wire [SUM_W-1:0] fast_transition_gross_before;
    wire [SUM_W-1:0] fast_transition_gross_after;

    hft_rmic_futures_transition_v1 #(
        .QTY_W(QTY_W)
    ) u_fast_transition (
        .event_kind(req_event_kind),
        .side(req_side),
        .position_effect(req_position_effect),
        .order_qty(req_order_qty),
        .fill_qty(req_fill_qty),
        .release_qty(req_release_qty),
        .long_position(l0_long),
        .short_position(l0_short),
        .pending_open_long(l0_pending_long),
        .pending_open_short(l0_pending_short),
        .reserved_close_long(l0_reserved_long),
        .reserved_close_short(l0_reserved_short),
        .transition_ok(fast_transition_ok),
        .reason_code(fast_transition_reason),
        .margin_check_required(fast_transition_margin_check_required),
        .next_long_position(fast_transition_next_long),
        .next_short_position(fast_transition_next_short),
        .next_pending_open_long(fast_transition_next_pending_long),
        .next_pending_open_short(fast_transition_next_pending_short),
        .next_reserved_close_long(fast_transition_next_reserved_long),
        .next_reserved_close_short(fast_transition_next_reserved_short),
        .gross_before(fast_transition_gross_before),
        .gross_after_candidate(fast_transition_gross_after)
    );

    reg prep_transition_ok;
    reg [7:0] prep_transition_reason;
    reg prep_margin_check_required;
    reg prep_entry_configured;
    reg prep_enabled;
    reg [MARGIN_W-1:0] prep_margin_budget;
    reg [MARGIN_W-1:0] prep_margin_per_contract;
    reg [SUM_W-1:0] prep_gross_before;
    reg [SUM_W-1:0] prep_gross_after;

    reg [QTY_W-1:0] prep_current_long;
    reg [QTY_W-1:0] prep_current_short;
    reg [QTY_W-1:0] prep_current_pending_long;
    reg [QTY_W-1:0] prep_current_pending_short;
    reg [QTY_W-1:0] prep_current_reserved_long;
    reg [QTY_W-1:0] prep_current_reserved_short;

    reg [QTY_W-1:0] prep_next_long;
    reg [QTY_W-1:0] prep_next_short;
    reg [QTY_W-1:0] prep_next_pending_long;
    reg [QTY_W-1:0] prep_next_pending_short;
    reg [QTY_W-1:0] prep_next_reserved_long;
    reg [QTY_W-1:0] prep_next_reserved_short;

    // ---------------------------------------------------------------------
    // Registered wide multiplication stage. These assignments intentionally
    // end at registers so Vivado can use DSP output pipelining rather than
    // chaining margin decision logic into a second multiplier.
    // ---------------------------------------------------------------------
    reg [MARGIN_CALC_W-1:0] margin_before_wide_reg;
    reg [MARGIN_CALC_W-1:0] margin_after_wide_reg;

    wire margin_before_overflow =
        |margin_before_wide_reg[MARGIN_CALC_W-1:MARGIN_W];
    wire margin_after_overflow =
        |margin_after_wide_reg[MARGIN_CALC_W-1:MARGIN_W];
    wire [MARGIN_W-1:0] margin_before_value = margin_before_wide_reg[MARGIN_W-1:0];
    wire [MARGIN_W-1:0] margin_after_value = margin_after_wide_reg[MARGIN_W-1:0];
    wire margin_after_exceeds_budget = margin_after_overflow ||
        (margin_after_value > prep_margin_budget);

    // ---------------------------------------------------------------------
    // Final decision stage. Rejected valid-key operations report unchanged
    // current state. Unconfigured/invalid keys never expose stale BRAM data.
    // ---------------------------------------------------------------------
    reg final_ok;
    reg [7:0] final_reason;
    reg final_entry_enabled;
    reg [QTY_W-1:0] final_long;
    reg [QTY_W-1:0] final_short;
    reg [QTY_W-1:0] final_pending_long;
    reg [QTY_W-1:0] final_pending_short;
    reg [QTY_W-1:0] final_reserved_long;
    reg [QTY_W-1:0] final_reserved_short;
    reg [MARGIN_W-1:0] final_margin_before;
    reg [MARGIN_W-1:0] final_margin_after;

    always @(*) begin
        final_ok = 1'b0;
        final_reason = `HFT_RMIC_POLICY_REASON_ACCOUNTING_STATE;
        final_entry_enabled = 1'b0;
        final_long = {QTY_W{1'b0}};
        final_short = {QTY_W{1'b0}};
        final_pending_long = {QTY_W{1'b0}};
        final_pending_short = {QTY_W{1'b0}};
        final_reserved_long = {QTY_W{1'b0}};
        final_reserved_short = {QTY_W{1'b0}};
        final_margin_before = {MARGIN_W{1'b0}};
        final_margin_after = {MARGIN_W{1'b0}};

        if (!req_key_valid_latched) begin
            final_reason = `HFT_RMIC_POLICY_REASON_STATE_KEY_INVALID;
        end else if (!prep_entry_configured) begin
            final_reason = `HFT_RMIC_POLICY_REASON_STATE_UNCONFIGURED;
        end else begin
            final_entry_enabled = prep_enabled;
            final_long = prep_current_long;
            final_short = prep_current_short;
            final_pending_long = prep_current_pending_long;
            final_pending_short = prep_current_pending_short;
            final_reserved_long = prep_current_reserved_long;
            final_reserved_short = prep_current_reserved_short;
            final_margin_before = margin_before_value;
            final_margin_after = margin_before_value;

            if (!prep_enabled) begin
                final_reason = `HFT_RMIC_POLICY_REASON_STATE_DISABLED;
            end else if (req_is_query) begin
                final_ok = 1'b1;
                final_reason = `HFT_RMIC_POLICY_REASON_PASS;
            end else if (!req_is_mutation) begin
                final_reason = `HFT_RMIC_POLICY_REASON_ACCOUNTING_STATE;
            end else if (!prep_transition_ok) begin
                final_reason = prep_transition_reason;
            end else if (prep_margin_check_required && margin_after_exceeds_budget) begin
                // OPEN reservation overflow and budget exceed both map to the
                // same v1 margin-limit reason, preserving the reference model.
                final_reason = `HFT_RMIC_POLICY_REASON_MARGIN_LIMIT;
            end else if (margin_after_overflow) begin
                // Non-reserve mutations can reveal an invalid configured state
                // width; preserve the original state-manager fail-closed code.
                final_reason = `HFT_RMIC_POLICY_REASON_POSITION_OVERFLOW;
            end else begin
                final_ok = 1'b1;
                final_reason = `HFT_RMIC_POLICY_REASON_PASS;
                final_long = prep_next_long;
                final_short = prep_next_short;
                final_pending_long = prep_next_pending_long;
                final_pending_short = prep_next_pending_short;
                final_reserved_long = prep_next_reserved_long;
                final_reserved_short = prep_next_reserved_short;
                final_margin_after = margin_after_value;
            end
        end
    end

    wire [REC_W-1:0] cfg_record = {
        cfg_reserved_close_short,
        cfg_reserved_close_long,
        cfg_pending_open_short,
        cfg_pending_open_long,
        cfg_short_position,
        cfg_long_position,
        cfg_margin_per_contract,
        cfg_margin_budget,
        cfg_enabled
    };

    wire [REC_W-1:0] commit_record = {
        final_reserved_short,
        final_reserved_long,
        final_pending_short,
        final_pending_long,
        final_short,
        final_long,
        prep_margin_per_contract,
        prep_margin_budget,
        prep_enabled
    };

    wire txn_commit = (state == ST_DECIDE) && req_key_valid_latched &&
                      prep_entry_configured && prep_enabled &&
                      req_is_mutation && final_ok;
    wire cfg_write = cfg_fire && cfg_key_valid;
    wire ram_wr_en = cfg_write || txn_commit;
    wire [ADDR_W-1:0] ram_wr_addr = cfg_write ? cfg_index : req_index_latched;
    wire [REC_W-1:0] ram_wr_data = cfg_write ? cfg_record : commit_record;

    hft_rmic_state_ram #(
        .DEPTH(ENTRY_COUNT), .ADDR_W(ADDR_W), .DATA_W(REC_W)
    ) u_state_ram (
        .clk(clk),
        .rd_en(ram_rd_en), .rd_addr(ram_rd_addr), .rd_data(ram_rd_data),
        .wr_en(ram_wr_en), .wr_addr(ram_wr_addr), .wr_data(ram_wr_data)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE;
            configured_bits <= {ENTRY_COUNT{1'b0}};
            l0_valid <= 1'b0;
            l0_index <= {ADDR_W{1'b0}};
            l0_record <= {REC_W{1'b0}};
            l0_configured <= 1'b0;

            cfg_done <= 1'b0;
            cfg_ok <= 1'b0;
            cfg_reason_code <= `HFT_RMIC_POLICY_REASON_PASS;

            req_account_latched <= {ACCOUNT_ID_W{1'b0}};
            req_product_latched <= {PRODUCT_ID_W{1'b0}};
            req_index_latched <= {ADDR_W{1'b0}};
            req_key_valid_latched <= 1'b0;
            req_event_latched <= `HFT_RMIC_ACCT_EVENT_QUERY;
            req_side_latched <= 1'b0;
            req_position_effect_latched <= 8'd0;
            req_order_qty_latched <= {QTY_W{1'b0}};
            req_fill_qty_latched <= {QTY_W{1'b0}};
            req_release_qty_latched <= {QTY_W{1'b0}};

            rec_latched <= {REC_W{1'b0}};
            entry_configured_latched <= 1'b0;

            prep_transition_ok <= 1'b0;
            prep_transition_reason <= `HFT_RMIC_POLICY_REASON_ACCOUNTING_STATE;
            prep_margin_check_required <= 1'b0;
            prep_entry_configured <= 1'b0;
            prep_enabled <= 1'b0;
            prep_margin_budget <= {MARGIN_W{1'b0}};
            prep_margin_per_contract <= {MARGIN_W{1'b0}};
            prep_gross_before <= {SUM_W{1'b0}};
            prep_gross_after <= {SUM_W{1'b0}};

            prep_current_long <= {QTY_W{1'b0}};
            prep_current_short <= {QTY_W{1'b0}};
            prep_current_pending_long <= {QTY_W{1'b0}};
            prep_current_pending_short <= {QTY_W{1'b0}};
            prep_current_reserved_long <= {QTY_W{1'b0}};
            prep_current_reserved_short <= {QTY_W{1'b0}};

            prep_next_long <= {QTY_W{1'b0}};
            prep_next_short <= {QTY_W{1'b0}};
            prep_next_pending_long <= {QTY_W{1'b0}};
            prep_next_pending_short <= {QTY_W{1'b0}};
            prep_next_reserved_long <= {QTY_W{1'b0}};
            prep_next_reserved_short <= {QTY_W{1'b0}};

            margin_before_wide_reg <= {MARGIN_CALC_W{1'b0}};
            margin_after_wide_reg <= {MARGIN_CALC_W{1'b0}};

            rsp_valid <= 1'b0;
            rsp_ok <= 1'b0;
            rsp_reason_source <= `HFT_RMIC_REASON_SRC_POLICY;
            rsp_reason_code <= `HFT_RMIC_POLICY_REASON_PASS;
            rsp_account_id <= {ACCOUNT_ID_W{1'b0}};
            rsp_product_id <= {PRODUCT_ID_W{1'b0}};
            rsp_entry_enabled <= 1'b0;
            rsp_long_position <= {QTY_W{1'b0}};
            rsp_short_position <= {QTY_W{1'b0}};
            rsp_pending_open_long <= {QTY_W{1'b0}};
            rsp_pending_open_short <= {QTY_W{1'b0}};
            rsp_reserved_close_long <= {QTY_W{1'b0}};
            rsp_reserved_close_short <= {QTY_W{1'b0}};
            rsp_required_margin_before <= {MARGIN_W{1'b0}};
            rsp_required_margin_after <= {MARGIN_W{1'b0}};
        end else begin
            cfg_done <= 1'b0;

            if (rsp_valid && rsp_ready)
                rsp_valid <= 1'b0;

            if (cfg_fire) begin
                cfg_done <= 1'b1;
                cfg_ok <= cfg_key_valid;
                cfg_reason_code <= cfg_key_valid ?
                    `HFT_RMIC_POLICY_REASON_PASS :
                    `HFT_RMIC_POLICY_REASON_STATE_KEY_INVALID;
                if (cfg_key_valid) begin
                    configured_bits[cfg_index] <= 1'b1;
                    if (ENABLE_L0_FAST_CACHE != 0) begin
                        l0_valid <= 1'b1;
                        l0_index <= cfg_index;
                        l0_record <= cfg_record;
                        l0_configured <= 1'b1;
                    end
                end
            end

            // Keep the L0 copy coherent with every successful state mutation.
            if ((ENABLE_L0_FAST_CACHE != 0) && txn_commit) begin
                l0_valid <= 1'b1;
                l0_index <= req_index_latched;
                l0_record <= commit_record;
                l0_configured <= 1'b1;
            end

            case (state)
                ST_IDLE: begin
                    if (req_fire) begin
                        req_account_latched <= req_account_id;
                        req_product_latched <= req_product_id;
                        req_index_latched <= req_index;
                        req_key_valid_latched <= req_key_valid;
                        req_event_latched <= req_event_kind;
                        req_side_latched <= req_side;
                        req_position_effect_latched <= req_position_effect;
                        req_order_qty_latched <= req_order_qty;
                        req_fill_qty_latched <= req_fill_qty;
                        req_release_qty_latched <= req_release_qty;

                        if (l0_hit) begin
                            // Directly materialize the PREP registers from the
                            // coherent cache.  This removes two hot-path cycles:
                            // BRAM CAPTURE and the registered PREP stage.
                            rec_latched <= l0_record;
                            entry_configured_latched <= l0_configured;

                            prep_transition_ok <= fast_transition_ok;
                            prep_transition_reason <= fast_transition_reason;
                            prep_margin_check_required <= fast_transition_margin_check_required;
                            prep_entry_configured <= l0_configured;
                            prep_enabled <= l0_enabled;
                            prep_margin_budget <= l0_margin_budget;
                            prep_margin_per_contract <= l0_margin_per_contract;
                            prep_gross_before <= fast_transition_gross_before;
                            prep_gross_after <= fast_transition_gross_after;

                            prep_current_long <= l0_long;
                            prep_current_short <= l0_short;
                            prep_current_pending_long <= l0_pending_long;
                            prep_current_pending_short <= l0_pending_short;
                            prep_current_reserved_long <= l0_reserved_long;
                            prep_current_reserved_short <= l0_reserved_short;

                            prep_next_long <= fast_transition_next_long;
                            prep_next_short <= fast_transition_next_short;
                            prep_next_pending_long <= fast_transition_next_pending_long;
                            prep_next_pending_short <= fast_transition_next_pending_short;
                            prep_next_reserved_long <= fast_transition_next_reserved_long;
                            prep_next_reserved_short <= fast_transition_next_reserved_short;
                            state <= ST_MARGIN;
                        end else begin
                            state <= ST_CAPTURE;
                        end
                    end
                end

                ST_CAPTURE: begin
                    // READ_LATENCY_B=1 updates ram_rd_data after the request
                    // handshake edge. Capture it one edge later before any
                    // arithmetic so BRAM clock-to-out is not on the DSP path.
                    rec_latched <= req_key_valid_latched ? ram_rd_data : {REC_W{1'b0}};
                    entry_configured_latched <= req_key_valid_latched &&
                                                configured_bits[req_index_latched];
                    if ((ENABLE_L0_FAST_CACHE != 0) && req_key_valid_latched) begin
                        l0_valid <= 1'b1;
                        l0_index <= req_index_latched;
                        l0_record <= ram_rd_data;
                        l0_configured <= configured_bits[req_index_latched];
                    end
                    state <= ST_PREP;
                end

                ST_PREP: begin
                    prep_transition_ok <= transition_ok;
                    prep_transition_reason <= transition_reason;
                    prep_margin_check_required <= transition_margin_check_required;
                    prep_entry_configured <= entry_configured_latched;
                    prep_enabled <= rec_enabled;
                    prep_margin_budget <= rec_margin_budget;
                    prep_margin_per_contract <= rec_margin_per_contract;
                    prep_gross_before <= transition_gross_before;
                    prep_gross_after <= transition_gross_after;

                    prep_current_long <= rec_long;
                    prep_current_short <= rec_short;
                    prep_current_pending_long <= rec_pending_long;
                    prep_current_pending_short <= rec_pending_short;
                    prep_current_reserved_long <= rec_reserved_long;
                    prep_current_reserved_short <= rec_reserved_short;

                    prep_next_long <= transition_next_long;
                    prep_next_short <= transition_next_short;
                    prep_next_pending_long <= transition_next_pending_long;
                    prep_next_pending_short <= transition_next_pending_short;
                    prep_next_reserved_long <= transition_next_reserved_long;
                    prep_next_reserved_short <= transition_next_reserved_short;
                    state <= ST_MARGIN;
                end

                ST_MARGIN: begin
                    margin_before_wide_reg <= prep_gross_before * prep_margin_per_contract;
                    margin_after_wide_reg <= prep_gross_after * prep_margin_per_contract;
                    state <= ST_DECIDE;
                end

                ST_DECIDE: begin
                    rsp_valid <= 1'b1;
                    rsp_ok <= final_ok;
                    rsp_reason_source <= `HFT_RMIC_REASON_SRC_POLICY;
                    rsp_reason_code <= final_reason;
                    rsp_account_id <= req_account_latched;
                    rsp_product_id <= req_product_latched;
                    rsp_entry_enabled <= final_entry_enabled;
                    rsp_long_position <= final_long;
                    rsp_short_position <= final_short;
                    rsp_pending_open_long <= final_pending_long;
                    rsp_pending_open_short <= final_pending_short;
                    rsp_reserved_close_long <= final_reserved_long;
                    rsp_reserved_close_short <= final_reserved_short;
                    rsp_required_margin_before <= final_margin_before;
                    rsp_required_margin_after <= final_margin_after;
                    state <= ST_IDLE;
                end

                default: begin
                    state <= ST_IDLE;
                end
            endcase
        end
    end

    initial begin
        if (NUM_ACCOUNTS < 1 || NUM_PRODUCTS < 1)
            $error("NUM_ACCOUNTS and NUM_PRODUCTS must be >= 1");
        if (ENTRY_COUNT > (1 << ADDR_W))
            $error("state-manager address width is insufficient");
    end
endmodule
