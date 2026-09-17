`timescale 1ns/1ps
`include "hft_rmic_contract.svh"
`include "hft_rmic_policy_defs.svh"
`include "taifex_tmp_v2187_defs.svh"

// Deterministic futures-accounting transition primitive for HFT_RMIC.
//
// IMPORTANT: this is a project risk-budget model, not an implementation of
// TAIFEX SPAN.  margin_per_contract and margin_budget are host-configured risk
// parameters.  The model intentionally supports only PositionEffect O/C in v1;
// D/A/7 remain fail-closed until their accounting semantics are specified.
//
// State meaning:
//   long_position / short_position        filled open positions
//   pending_open_long / pending_open_short accepted OPEN orders not yet filled
//   reserved_close_long / _short          accepted CLOSE orders not yet filled
//
// Required margin is conservatively defined as:
//   margin_per_contract *
//   (long_position + short_position + pending_open_long + pending_open_short)
// Close reservations do not increase margin demand.
module hft_rmic_futures_accounting_v1 #(
    parameter integer QTY_W = 32,
    parameter integer MARGIN_W = 64
) (
    input  wire [2:0] event_kind,
    input  wire       side,             // frozen RMIC normalized side: BUY=0, SELL=1
    input  wire [7:0] position_effect,  // TAIFEX character field
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
    localparam [2:0] EVENT_ORDER_RESERVE = 3'd0;
    localparam [2:0] EVENT_FILL          = 3'd1;
    localparam [2:0] EVENT_RELEASE       = 3'd2; // cancel/reject remaining quantity

    localparam integer SUM_W = QTY_W + 3;
    localparam integer MARGIN_CALC_W = SUM_W + MARGIN_W;

    wire is_buy  = (side == `HFT_RMIC_RMIC_SIDE_BUY);
    wire is_open = (position_effect == `HFT_RMIC_TAIFEX_POS_OPEN);
    wire is_close= (position_effect == `HFT_RMIC_TAIFEX_POS_CLOSE);

    wire [SUM_W-1:0] gross_before =
        {{(SUM_W-QTY_W){1'b0}}, long_position} +
        {{(SUM_W-QTY_W){1'b0}}, short_position} +
        {{(SUM_W-QTY_W){1'b0}}, pending_open_long} +
        {{(SUM_W-QTY_W){1'b0}}, pending_open_short};

    wire [SUM_W-1:0] gross_after =
        {{(SUM_W-QTY_W){1'b0}}, next_long_position} +
        {{(SUM_W-QTY_W){1'b0}}, next_short_position} +
        {{(SUM_W-QTY_W){1'b0}}, next_pending_open_long} +
        {{(SUM_W-QTY_W){1'b0}}, next_pending_open_short};

    wire [SUM_W-1:0] gross_open_candidate =
        gross_before + {{(SUM_W-QTY_W){1'b0}}, order_qty};

    wire [MARGIN_CALC_W-1:0] margin_before_wide = gross_before * margin_per_contract;
    wire [MARGIN_CALC_W-1:0] margin_after_wide = gross_after * margin_per_contract;
    wire [MARGIN_CALC_W-1:0] margin_candidate_wide = gross_open_candidate * margin_per_contract;

    assign required_margin_before = margin_before_wide[MARGIN_W-1:0];
    assign required_margin_after  = margin_after_wide[MARGIN_W-1:0];
    assign required_margin_before_overflow = |margin_before_wide[MARGIN_CALC_W-1:MARGIN_W];
    assign required_margin_after_overflow  = |margin_after_wide[MARGIN_CALC_W-1:MARGIN_W];

    wire candidate_margin_overflow = |margin_candidate_wide[MARGIN_CALC_W-1:MARGIN_W];
    wire candidate_margin_exceeds_budget = candidate_margin_overflow ||
        (margin_candidate_wide[MARGIN_W-1:0] > margin_budget);

    wire [QTY_W:0] pending_long_plus_order = {1'b0,pending_open_long} + {1'b0,order_qty};
    wire [QTY_W:0] pending_short_plus_order = {1'b0,pending_open_short} + {1'b0,order_qty};
    wire [QTY_W:0] close_long_plus_order = {1'b0,reserved_close_long} + {1'b0,order_qty};
    wire [QTY_W:0] close_short_plus_order = {1'b0,reserved_close_short} + {1'b0,order_qty};
    wire [QTY_W:0] long_plus_fill = {1'b0,long_position} + {1'b0,fill_qty};
    wire [QTY_W:0] short_plus_fill = {1'b0,short_position} + {1'b0,fill_qty};

    always @(*) begin
        event_ok = 1'b0;
        reason_code = `HFT_RMIC_POLICY_REASON_ACCOUNTING_STATE;

        next_long_position = long_position;
        next_short_position = short_position;
        next_pending_open_long = pending_open_long;
        next_pending_open_short = pending_open_short;
        next_reserved_close_long = reserved_close_long;
        next_reserved_close_short = reserved_close_short;

        case (event_kind)
            EVENT_ORDER_RESERVE: begin
                if (order_qty == {QTY_W{1'b0}}) begin
                    reason_code = `HFT_RMIC_POLICY_REASON_ACCOUNTING_STATE;
                end else if (is_open) begin
                    if (candidate_margin_exceeds_budget) begin
                        reason_code = `HFT_RMIC_POLICY_REASON_MARGIN_LIMIT;
                    end else if (is_buy) begin
                        if (pending_long_plus_order[QTY_W]) begin
                            reason_code = `HFT_RMIC_POLICY_REASON_POSITION_OVERFLOW;
                        end else begin
                            next_pending_open_long = pending_long_plus_order[QTY_W-1:0];
                            event_ok = 1'b1;
                            reason_code = `HFT_RMIC_POLICY_REASON_PASS;
                        end
                    end else begin
                        if (pending_short_plus_order[QTY_W]) begin
                            reason_code = `HFT_RMIC_POLICY_REASON_POSITION_OVERFLOW;
                        end else begin
                            next_pending_open_short = pending_short_plus_order[QTY_W-1:0];
                            event_ok = 1'b1;
                            reason_code = `HFT_RMIC_POLICY_REASON_PASS;
                        end
                    end
                end else if (is_close) begin
                    if (is_buy) begin
                        // BUY CLOSE reduces short position.
                        if ((close_short_plus_order[QTY_W]) ||
                            ({1'b0,short_position} < close_short_plus_order)) begin
                            reason_code = `HFT_RMIC_POLICY_REASON_CLOSE_SHORT_INSUFFICIENT;
                        end else begin
                            next_reserved_close_short = close_short_plus_order[QTY_W-1:0];
                            event_ok = 1'b1;
                            reason_code = `HFT_RMIC_POLICY_REASON_PASS;
                        end
                    end else begin
                        // SELL CLOSE reduces long position.
                        if ((close_long_plus_order[QTY_W]) ||
                            ({1'b0,long_position} < close_long_plus_order)) begin
                            reason_code = `HFT_RMIC_POLICY_REASON_CLOSE_LONG_INSUFFICIENT;
                        end else begin
                            next_reserved_close_long = close_long_plus_order[QTY_W-1:0];
                            event_ok = 1'b1;
                            reason_code = `HFT_RMIC_POLICY_REASON_PASS;
                        end
                    end
                end else begin
                    reason_code = `HFT_RMIC_POLICY_REASON_POSITION_EFFECT;
                end
            end

            EVENT_FILL: begin
                if (fill_qty == {QTY_W{1'b0}}) begin
                    reason_code = `HFT_RMIC_POLICY_REASON_ACCOUNTING_STATE;
                end else if (is_open) begin
                    if (is_buy) begin
                        if (pending_open_long < fill_qty) begin
                            reason_code = `HFT_RMIC_POLICY_REASON_ACCOUNTING_STATE;
                        end else if (long_plus_fill[QTY_W]) begin
                            reason_code = `HFT_RMIC_POLICY_REASON_POSITION_OVERFLOW;
                        end else begin
                            next_pending_open_long = pending_open_long - fill_qty;
                            next_long_position = long_plus_fill[QTY_W-1:0];
                            event_ok = 1'b1;
                            reason_code = `HFT_RMIC_POLICY_REASON_PASS;
                        end
                    end else begin
                        if (pending_open_short < fill_qty) begin
                            reason_code = `HFT_RMIC_POLICY_REASON_ACCOUNTING_STATE;
                        end else if (short_plus_fill[QTY_W]) begin
                            reason_code = `HFT_RMIC_POLICY_REASON_POSITION_OVERFLOW;
                        end else begin
                            next_pending_open_short = pending_open_short - fill_qty;
                            next_short_position = short_plus_fill[QTY_W-1:0];
                            event_ok = 1'b1;
                            reason_code = `HFT_RMIC_POLICY_REASON_PASS;
                        end
                    end
                end else if (is_close) begin
                    if (is_buy) begin
                        if ((reserved_close_short < fill_qty) || (short_position < fill_qty)) begin
                            reason_code = `HFT_RMIC_POLICY_REASON_ACCOUNTING_STATE;
                        end else begin
                            next_reserved_close_short = reserved_close_short - fill_qty;
                            next_short_position = short_position - fill_qty;
                            event_ok = 1'b1;
                            reason_code = `HFT_RMIC_POLICY_REASON_PASS;
                        end
                    end else begin
                        if ((reserved_close_long < fill_qty) || (long_position < fill_qty)) begin
                            reason_code = `HFT_RMIC_POLICY_REASON_ACCOUNTING_STATE;
                        end else begin
                            next_reserved_close_long = reserved_close_long - fill_qty;
                            next_long_position = long_position - fill_qty;
                            event_ok = 1'b1;
                            reason_code = `HFT_RMIC_POLICY_REASON_PASS;
                        end
                    end
                end else begin
                    reason_code = `HFT_RMIC_POLICY_REASON_POSITION_EFFECT;
                end
            end

            EVENT_RELEASE: begin
                if (is_open) begin
                    if (is_buy) begin
                        if (pending_open_long < release_qty) begin
                            reason_code = `HFT_RMIC_POLICY_REASON_ACCOUNTING_STATE;
                        end else begin
                            next_pending_open_long = pending_open_long - release_qty;
                            event_ok = 1'b1;
                            reason_code = `HFT_RMIC_POLICY_REASON_PASS;
                        end
                    end else begin
                        if (pending_open_short < release_qty) begin
                            reason_code = `HFT_RMIC_POLICY_REASON_ACCOUNTING_STATE;
                        end else begin
                            next_pending_open_short = pending_open_short - release_qty;
                            event_ok = 1'b1;
                            reason_code = `HFT_RMIC_POLICY_REASON_PASS;
                        end
                    end
                end else if (is_close) begin
                    if (is_buy) begin
                        if (reserved_close_short < release_qty) begin
                            reason_code = `HFT_RMIC_POLICY_REASON_ACCOUNTING_STATE;
                        end else begin
                            next_reserved_close_short = reserved_close_short - release_qty;
                            event_ok = 1'b1;
                            reason_code = `HFT_RMIC_POLICY_REASON_PASS;
                        end
                    end else begin
                        if (reserved_close_long < release_qty) begin
                            reason_code = `HFT_RMIC_POLICY_REASON_ACCOUNTING_STATE;
                        end else begin
                            next_reserved_close_long = reserved_close_long - release_qty;
                            event_ok = 1'b1;
                            reason_code = `HFT_RMIC_POLICY_REASON_PASS;
                        end
                    end
                end else begin
                    reason_code = `HFT_RMIC_POLICY_REASON_POSITION_EFFECT;
                end
            end

            default: begin
                reason_code = `HFT_RMIC_POLICY_REASON_ACCOUNTING_STATE;
            end
        endcase
    end
endmodule
