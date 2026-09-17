`timescale 1ns/1ps
`include "hft_rmic_contract.svh"
`include "hft_rmic_policy_defs.svh"
`include "taifex_tmp_v2187_defs.svh"

// Pure quantity/state transition stage for the futures accounting model.
//
// This module deliberately excludes margin multiplication.  It produces a
// candidate next state plus gross-exposure counts so callers can pipeline the
// expensive margin arithmetic without duplicating OPEN/CLOSE semantics.
module hft_rmic_futures_transition_v1 #(
    parameter integer QTY_W = 32
) (
    input  wire [2:0] event_kind,
    input  wire       side,
    input  wire [7:0] position_effect,
    input  wire [QTY_W-1:0] order_qty,
    input  wire [QTY_W-1:0] fill_qty,
    input  wire [QTY_W-1:0] release_qty,

    input  wire [QTY_W-1:0] long_position,
    input  wire [QTY_W-1:0] short_position,
    input  wire [QTY_W-1:0] pending_open_long,
    input  wire [QTY_W-1:0] pending_open_short,
    input  wire [QTY_W-1:0] reserved_close_long,
    input  wire [QTY_W-1:0] reserved_close_short,

    output reg transition_ok,
    output reg [7:0] reason_code,
    output reg margin_check_required,

    output reg [QTY_W-1:0] next_long_position,
    output reg [QTY_W-1:0] next_short_position,
    output reg [QTY_W-1:0] next_pending_open_long,
    output reg [QTY_W-1:0] next_pending_open_short,
    output reg [QTY_W-1:0] next_reserved_close_long,
    output reg [QTY_W-1:0] next_reserved_close_short,

    output wire [QTY_W+2:0] gross_before,
    output wire [QTY_W+2:0] gross_after_candidate
);
    localparam [2:0] EVENT_ORDER_RESERVE = 3'd0;
    localparam [2:0] EVENT_FILL          = 3'd1;
    localparam [2:0] EVENT_RELEASE       = 3'd2;
    localparam integer SUM_W = QTY_W + 3;

    wire is_buy   = (side == `HFT_RMIC_RMIC_SIDE_BUY);
    wire is_open  = (position_effect == `HFT_RMIC_TAIFEX_POS_OPEN);
    wire is_close = (position_effect == `HFT_RMIC_TAIFEX_POS_CLOSE);

    wire [QTY_W:0] pending_long_plus_order = {1'b0,pending_open_long} + {1'b0,order_qty};
    wire [QTY_W:0] pending_short_plus_order = {1'b0,pending_open_short} + {1'b0,order_qty};
    wire [QTY_W:0] close_long_plus_order = {1'b0,reserved_close_long} + {1'b0,order_qty};
    wire [QTY_W:0] close_short_plus_order = {1'b0,reserved_close_short} + {1'b0,order_qty};
    wire [QTY_W:0] long_plus_fill = {1'b0,long_position} + {1'b0,fill_qty};
    wire [QTY_W:0] short_plus_fill = {1'b0,short_position} + {1'b0,fill_qty};

    assign gross_before =
        {{(SUM_W-QTY_W){1'b0}}, long_position} +
        {{(SUM_W-QTY_W){1'b0}}, short_position} +
        {{(SUM_W-QTY_W){1'b0}}, pending_open_long} +
        {{(SUM_W-QTY_W){1'b0}}, pending_open_short};

    assign gross_after_candidate =
        {{(SUM_W-QTY_W){1'b0}}, next_long_position} +
        {{(SUM_W-QTY_W){1'b0}}, next_short_position} +
        {{(SUM_W-QTY_W){1'b0}}, next_pending_open_long} +
        {{(SUM_W-QTY_W){1'b0}}, next_pending_open_short};

    always @(*) begin
        transition_ok = 1'b0;
        reason_code = `HFT_RMIC_POLICY_REASON_ACCOUNTING_STATE;
        margin_check_required = 1'b0;

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
                    if (is_buy) begin
                        if (pending_long_plus_order[QTY_W]) begin
                            reason_code = `HFT_RMIC_POLICY_REASON_POSITION_OVERFLOW;
                        end else begin
                            next_pending_open_long = pending_long_plus_order[QTY_W-1:0];
                            transition_ok = 1'b1;
                            margin_check_required = 1'b1;
                            reason_code = `HFT_RMIC_POLICY_REASON_PASS;
                        end
                    end else begin
                        if (pending_short_plus_order[QTY_W]) begin
                            reason_code = `HFT_RMIC_POLICY_REASON_POSITION_OVERFLOW;
                        end else begin
                            next_pending_open_short = pending_short_plus_order[QTY_W-1:0];
                            transition_ok = 1'b1;
                            margin_check_required = 1'b1;
                            reason_code = `HFT_RMIC_POLICY_REASON_PASS;
                        end
                    end
                end else if (is_close) begin
                    if (is_buy) begin
                        if (close_short_plus_order[QTY_W] ||
                            ({1'b0,short_position} < close_short_plus_order)) begin
                            reason_code = `HFT_RMIC_POLICY_REASON_CLOSE_SHORT_INSUFFICIENT;
                        end else begin
                            next_reserved_close_short = close_short_plus_order[QTY_W-1:0];
                            transition_ok = 1'b1;
                            reason_code = `HFT_RMIC_POLICY_REASON_PASS;
                        end
                    end else begin
                        if (close_long_plus_order[QTY_W] ||
                            ({1'b0,long_position} < close_long_plus_order)) begin
                            reason_code = `HFT_RMIC_POLICY_REASON_CLOSE_LONG_INSUFFICIENT;
                        end else begin
                            next_reserved_close_long = close_long_plus_order[QTY_W-1:0];
                            transition_ok = 1'b1;
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
                            transition_ok = 1'b1;
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
                            transition_ok = 1'b1;
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
                            transition_ok = 1'b1;
                            reason_code = `HFT_RMIC_POLICY_REASON_PASS;
                        end
                    end else begin
                        if ((reserved_close_long < fill_qty) || (long_position < fill_qty)) begin
                            reason_code = `HFT_RMIC_POLICY_REASON_ACCOUNTING_STATE;
                        end else begin
                            next_reserved_close_long = reserved_close_long - fill_qty;
                            next_long_position = long_position - fill_qty;
                            transition_ok = 1'b1;
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
                            transition_ok = 1'b1;
                            reason_code = `HFT_RMIC_POLICY_REASON_PASS;
                        end
                    end else begin
                        if (pending_open_short < release_qty) begin
                            reason_code = `HFT_RMIC_POLICY_REASON_ACCOUNTING_STATE;
                        end else begin
                            next_pending_open_short = pending_open_short - release_qty;
                            transition_ok = 1'b1;
                            reason_code = `HFT_RMIC_POLICY_REASON_PASS;
                        end
                    end
                end else if (is_close) begin
                    if (is_buy) begin
                        if (reserved_close_short < release_qty) begin
                            reason_code = `HFT_RMIC_POLICY_REASON_ACCOUNTING_STATE;
                        end else begin
                            next_reserved_close_short = reserved_close_short - release_qty;
                            transition_ok = 1'b1;
                            reason_code = `HFT_RMIC_POLICY_REASON_PASS;
                        end
                    end else begin
                        if (reserved_close_long < release_qty) begin
                            reason_code = `HFT_RMIC_POLICY_REASON_ACCOUNTING_STATE;
                        end else begin
                            next_reserved_close_long = reserved_close_long - release_qty;
                            transition_ok = 1'b1;
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
