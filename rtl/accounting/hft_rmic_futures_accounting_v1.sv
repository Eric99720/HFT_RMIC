`timescale 1ns/1ps
`include "hft_rmic_contract.svh"
`include "hft_rmic_policy_defs.svh"
`include "taifex_tmp_v2187_defs.svh"

// Deterministic futures-accounting transition primitive for HFT_RMIC.
//
// IMPORTANT: this is a project risk-budget model, not an implementation of
// TAIFEX SPAN. margin_per_contract and margin_budget are host-configured risk
// parameters. The model intentionally supports only PositionEffect O/C in v1;
// D/A/7 remain fail-closed until their accounting semantics are specified.
//
// The quantity transition is factored into hft_rmic_futures_transition_v1 so
// physical state owners can pipeline margin multiplication independently. This
// module remains combinational for the standalone reference-model regression.
module hft_rmic_futures_accounting_v1 #(
    parameter integer QTY_W = 32,
    parameter integer MARGIN_W = 64
) (
    input  wire [2:0] event_kind,
    input  wire       side,
    input  wire [7:0] position_effect,
    input  wire [QTY_W-1:0] order_qty,
    input  wire [QTY_W-1:0] fill_qty,
    input  wire [QTY_W-1:0] release_qty,

    input  wire [MARGIN_W-1:0] margin_budget,
    input  wire [MARGIN_W-1:0] margin_per_contract,

    input  wire [QTY_W-1:0] long_position,
    input  wire [QTY_W-1:0] short_position,
    input  wire [QTY_W-1:0] pending_open_long,
    input  wire [QTY_W-1:0] pending_open_short,
    input  wire [QTY_W-1:0] reserved_close_long,
    input  wire [QTY_W-1:0] reserved_close_short,

    output reg event_ok,
    output reg [7:0] reason_code,

    output reg [QTY_W-1:0] next_long_position,
    output reg [QTY_W-1:0] next_short_position,
    output reg [QTY_W-1:0] next_pending_open_long,
    output reg [QTY_W-1:0] next_pending_open_short,
    output reg [QTY_W-1:0] next_reserved_close_long,
    output reg [QTY_W-1:0] next_reserved_close_short,

    output wire [MARGIN_W-1:0] required_margin_before,
    output wire [MARGIN_W-1:0] required_margin_after,
    output wire required_margin_before_overflow,
    output wire required_margin_after_overflow
);
    localparam integer SUM_W = QTY_W + 3;
    localparam integer MARGIN_CALC_W = SUM_W + MARGIN_W;

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
        .event_kind(event_kind),
        .side(side),
        .position_effect(position_effect),
        .order_qty(order_qty),
        .fill_qty(fill_qty),
        .release_qty(release_qty),
        .long_position(long_position),
        .short_position(short_position),
        .pending_open_long(pending_open_long),
        .pending_open_short(pending_open_short),
        .reserved_close_long(reserved_close_long),
        .reserved_close_short(reserved_close_short),
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

    // Both products are independent. The old implementation formed a reserve
    // candidate margin, used it to decide event_ok, then let event_ok select the
    // next state that fed a second margin multiplier. Vivado consequently put
    // two wide DSP multipliers serially on the BRAM read-to-writeback path.
    wire [MARGIN_CALC_W-1:0] margin_before_wide =
        transition_gross_before * margin_per_contract;
    wire [MARGIN_CALC_W-1:0] margin_after_candidate_wide =
        transition_gross_after * margin_per_contract;

    wire margin_before_overflow =
        |margin_before_wide[MARGIN_CALC_W-1:MARGIN_W];
    wire margin_after_candidate_overflow =
        |margin_after_candidate_wide[MARGIN_CALC_W-1:MARGIN_W];
    wire margin_after_candidate_exceeds_budget =
        margin_after_candidate_overflow ||
        (margin_after_candidate_wide[MARGIN_W-1:0] > margin_budget);

    always @(*) begin
        event_ok = 1'b0;
        reason_code = transition_reason;

        // Rejected transitions expose unchanged state, matching the original
        // v1 contract and making atomicity visible to software/testbenches.
        next_long_position = long_position;
        next_short_position = short_position;
        next_pending_open_long = pending_open_long;
        next_pending_open_short = pending_open_short;
        next_reserved_close_long = reserved_close_long;
        next_reserved_close_short = reserved_close_short;

        if (transition_ok) begin
            if (transition_margin_check_required && margin_after_candidate_exceeds_budget) begin
                reason_code = `HFT_RMIC_POLICY_REASON_MARGIN_LIMIT;
            end else begin
                event_ok = 1'b1;
                reason_code = `HFT_RMIC_POLICY_REASON_PASS;
                next_long_position = transition_next_long;
                next_short_position = transition_next_short;
                next_pending_open_long = transition_next_pending_long;
                next_pending_open_short = transition_next_pending_short;
                next_reserved_close_long = transition_next_reserved_long;
                next_reserved_close_short = transition_next_reserved_short;
            end
        end
    end

    assign required_margin_before = margin_before_wide[MARGIN_W-1:0];
    assign required_margin_after = event_ok ?
        margin_after_candidate_wide[MARGIN_W-1:0] :
        margin_before_wide[MARGIN_W-1:0];

    assign required_margin_before_overflow = margin_before_overflow;
    assign required_margin_after_overflow = event_ok ?
        margin_after_candidate_overflow : margin_before_overflow;
endmodule
