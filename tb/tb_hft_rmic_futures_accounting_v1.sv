`timescale 1ns/1ps
`include "hft_rmic_contract.svh"
`include "hft_rmic_policy_defs.svh"
`include "taifex_tmp_v2187_defs.svh"

module tb_hft_rmic_futures_accounting_v1;
    localparam QTY_W = 32;
    localparam MARGIN_W = 64;

    reg [2:0] event_kind;
    reg side;
    reg [7:0] position_effect;
    reg [QTY_W-1:0] order_qty, fill_qty, release_qty;
    reg [MARGIN_W-1:0] margin_budget, margin_per_contract;

    reg [QTY_W-1:0] long_position, short_position;
    reg [QTY_W-1:0] pending_open_long, pending_open_short;
    reg [QTY_W-1:0] reserved_close_long, reserved_close_short;

    wire event_ok;
    wire [7:0] reason_code;
    wire [QTY_W-1:0] next_long_position, next_short_position;
    wire [QTY_W-1:0] next_pending_open_long, next_pending_open_short;
    wire [QTY_W-1:0] next_reserved_close_long, next_reserved_close_short;
    wire [MARGIN_W-1:0] required_margin_before, required_margin_after;
    wire required_margin_before_overflow, required_margin_after_overflow;

    hft_rmic_futures_accounting_v1 dut (.*);

    task fail;
        input [8*96-1:0] msg;
        begin
            $display("TEST_FAIL %0s", msg);
            $fatal(1);
        end
    endtask

    task commit_next;
        begin
            long_position = next_long_position;
            short_position = next_short_position;
            pending_open_long = next_pending_open_long;
            pending_open_short = next_pending_open_short;
            reserved_close_long = next_reserved_close_long;
            reserved_close_short = next_reserved_close_short;
            #1;
        end
    endtask

    task reserve_order;
        input order_side;
        input [7:0] pe;
        input [31:0] qty;
        begin
            event_kind = 3'd0;
            side = order_side;
            position_effect = pe;
            order_qty = qty;
            fill_qty = 0;
            release_qty = 0;
            #1;
        end
    endtask

    task apply_fill;
        input order_side;
        input [7:0] pe;
        input [31:0] qty;
        begin
            event_kind = 3'd1;
            side = order_side;
            position_effect = pe;
            order_qty = 0;
            fill_qty = qty;
            release_qty = 0;
            #1;
        end
    endtask

    task apply_release;
        input order_side;
        input [7:0] pe;
        input [31:0] qty;
        begin
            event_kind = 3'd2;
            side = order_side;
            position_effect = pe;
            order_qty = 0;
            fill_qty = 0;
            release_qty = qty;
            #1;
        end
    endtask

    initial begin
        margin_budget = 64'd1000;
        margin_per_contract = 64'd100;
        long_position = 0;
        short_position = 0;
        pending_open_long = 0;
        pending_open_short = 0;
        reserved_close_long = 0;
        reserved_close_short = 0;
        event_kind = 0;
        side = 0;
        position_effect = 0;
        order_qty = 0;
        fill_qty = 0;
        release_qty = 0;
        #1;

        // BUY OPEN 3: reserve gross margin for three future long contracts.
        reserve_order(`HFT_RMIC_RMIC_SIDE_BUY, `HFT_RMIC_TAIFEX_POS_OPEN, 3);
        if (!event_ok || next_pending_open_long != 3 || required_margin_after != 300)
            fail("BUY OPEN reservation");
        commit_next();

        // Partial fill two contracts: exposure remains three (2 filled + 1 pending).
        apply_fill(`HFT_RMIC_RMIC_SIDE_BUY, `HFT_RMIC_TAIFEX_POS_OPEN, 2);
        if (!event_ok || next_long_position != 2 || next_pending_open_long != 1 || required_margin_after != 300)
            fail("BUY OPEN partial fill");
        commit_next();

        // Cancel/reject the final unfilled contract.
        apply_release(`HFT_RMIC_RMIC_SIDE_BUY, `HFT_RMIC_TAIFEX_POS_OPEN, 1);
        if (!event_ok || next_pending_open_long != 0 || required_margin_after != 200)
            fail("BUY OPEN remaining release");
        commit_next();
        $display("HFT_RMIC_FUTURES_LONG_OPEN_PASS");

        // SELL OPEN must be legal without owning a long position.  This is the
        // key semantic difference from the frozen stock-like RMIC account model.
        reserve_order(`HFT_RMIC_RMIC_SIDE_SELL, `HFT_RMIC_TAIFEX_POS_OPEN, 4);
        if (!event_ok || next_pending_open_short != 4 || required_margin_after != 600)
            fail("SELL OPEN reservation");
        commit_next();
        apply_fill(`HFT_RMIC_RMIC_SIDE_SELL, `HFT_RMIC_TAIFEX_POS_OPEN, 4);
        if (!event_ok || next_short_position != 4 || next_pending_open_short != 0 || required_margin_after != 600)
            fail("SELL OPEN fill");
        commit_next();
        $display("HFT_RMIC_FUTURES_SHORT_OPEN_PASS");

        // SELL CLOSE consumes long position, not short position.
        reserve_order(`HFT_RMIC_RMIC_SIDE_SELL, `HFT_RMIC_TAIFEX_POS_CLOSE, 1);
        if (!event_ok || next_reserved_close_long != 1)
            fail("SELL CLOSE reserve long");
        commit_next();
        apply_fill(`HFT_RMIC_RMIC_SIDE_SELL, `HFT_RMIC_TAIFEX_POS_CLOSE, 1);
        if (!event_ok || next_long_position != 1 || next_reserved_close_long != 0 || required_margin_after != 500)
            fail("SELL CLOSE fill long");
        commit_next();

        // BUY CLOSE consumes short position.
        reserve_order(`HFT_RMIC_RMIC_SIDE_BUY, `HFT_RMIC_TAIFEX_POS_CLOSE, 2);
        if (!event_ok || next_reserved_close_short != 2)
            fail("BUY CLOSE reserve short");
        commit_next();
        apply_fill(`HFT_RMIC_RMIC_SIDE_BUY, `HFT_RMIC_TAIFEX_POS_CLOSE, 2);
        if (!event_ok || next_short_position != 2 || next_reserved_close_short != 0 || required_margin_after != 300)
            fail("BUY CLOSE fill short");
        commit_next();
        $display("HFT_RMIC_FUTURES_CLOSE_PASS");

        // Can't close more long contracts than are available after prior reservations.
        reserve_order(`HFT_RMIC_RMIC_SIDE_SELL, `HFT_RMIC_TAIFEX_POS_CLOSE, 2);
        if (event_ok || reason_code != `HFT_RMIC_POLICY_REASON_CLOSE_LONG_INSUFFICIENT)
            fail("insufficient long close must reject");
        $display("HFT_RMIC_FUTURES_CLOSE_LIMIT_PASS");

        // Current gross exposure is 3 contracts; eight additional opens require
        // 11*100 = 1100 > configured budget 1000.
        reserve_order(`HFT_RMIC_RMIC_SIDE_BUY, `HFT_RMIC_TAIFEX_POS_OPEN, 8);
        if (event_ok || reason_code != `HFT_RMIC_POLICY_REASON_MARGIN_LIMIT)
            fail("margin budget must reject");
        $display("HFT_RMIC_FUTURES_MARGIN_LIMIT_PASS");

        // v1 deliberately does not guess day-trade/FCM-offset/options semantics.
        reserve_order(`HFT_RMIC_RMIC_SIDE_BUY, `HFT_RMIC_TAIFEX_POS_DAYTRADE, 1);
        if (event_ok || reason_code != `HFT_RMIC_POLICY_REASON_POSITION_EFFECT)
            fail("unsupported position effect must fail closed");
        $display("HFT_RMIC_FUTURES_POSITION_EFFECT_FAIL_CLOSED_PASS");

        if (required_margin_before_overflow || required_margin_after_overflow)
            fail("unexpected margin width overflow");

        $display("HFT_RMIC_FUTURES_ACCOUNTING_V1_TB_PASS");
        $finish;
    end
endmodule
