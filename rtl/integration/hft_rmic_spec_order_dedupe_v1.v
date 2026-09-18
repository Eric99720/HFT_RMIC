`timescale 1ns/1ps

// Integration-owned duplicate guard for the speculative R01 prebuild path.
//
// The frozen speculative strategy compares its shadow book against the
// canonical book. With truly back-to-back market packets, the next packet can
// begin before the canonical book has reflected the prior commit, so the same
// decision can be emitted twice. This guard remembers the last speculative
// order transaction handed to RMIC and suppresses an identical consecutive
// request until the key changes or explicit recovery clears the history.
//
// The key intentionally includes PositionEffect and TIF. The same side/price
// may therefore be admitted when OPEN/CLOSE or order policy actually changes.
module hft_rmic_spec_order_dedupe_v1 #(
    parameter integer SYMBOL_WIDTH = 16,
    parameter integer PRICE_WIDTH  = 32,
    parameter integer QTY_WIDTH    = 32,
    parameter integer TYPE_WIDTH   = 4
) (
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         clear,

    input  wire                         s_valid,
    input  wire [SYMBOL_WIDTH-1:0]      s_symbol,
    input  wire                         s_side,
    input  wire [PRICE_WIDTH-1:0]       s_price,
    input  wire [QTY_WIDTH-1:0]         s_qty,
    input  wire [TYPE_WIDTH-1:0]        s_type,
    input  wire [7:0]                   s_tif,
    input  wire [7:0]                   s_position_effect,

    output wire                         m_valid,
    input  wire                         m_accept,
    output wire                         duplicate_blocked
);

    reg                                last_valid;
    reg [SYMBOL_WIDTH-1:0]             last_symbol;
    reg                                last_side;
    reg [PRICE_WIDTH-1:0]              last_price;
    reg [QTY_WIDTH-1:0]                last_qty;
    reg [TYPE_WIDTH-1:0]               last_type;
    reg [7:0]                          last_tif;
    reg [7:0]                          last_position_effect;

    wire same_key =
        (s_symbol          == last_symbol) &&
        (s_side            == last_side) &&
        (s_price           == last_price) &&
        (s_qty             == last_qty) &&
        (s_type            == last_type) &&
        (s_tif             == last_tif) &&
        (s_position_effect == last_position_effect);

    assign duplicate_blocked = s_valid && last_valid && same_key;
    assign m_valid = s_valid && !duplicate_blocked;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            last_valid <= 1'b0;
            last_symbol <= {SYMBOL_WIDTH{1'b0}};
            last_side <= 1'b0;
            last_price <= {PRICE_WIDTH{1'b0}};
            last_qty <= {QTY_WIDTH{1'b0}};
            last_type <= {TYPE_WIDTH{1'b0}};
            last_tif <= 8'd0;
            last_position_effect <= 8'd0;
        end else if (clear) begin
            last_valid <= 1'b0;
        end else if (m_valid && m_accept) begin
            last_valid <= 1'b1;
            last_symbol <= s_symbol;
            last_side <= s_side;
            last_price <= s_price;
            last_qty <= s_qty;
            last_type <= s_type;
            last_tif <= s_tif;
            last_position_effect <= s_position_effect;
        end
    end

endmodule
