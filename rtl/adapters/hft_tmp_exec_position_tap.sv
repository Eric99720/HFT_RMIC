`timescale 1ns/1ps
`include "taifex_tmp_v2187_defs.svh"

// Lightweight side-band parser for execution metadata not exposed by the
// frozen HFT R02/R32 decoder. The frozen decoder remains owner of checksum,
// MessageType, order ID, side, price, qty, LastPx, LastQty, LeavesQty and
// report sequence. This tap only captures PositionEffect and before_qty from
// the same accepted 64-bit payload stream.
//
// Official fixed offsets (TAIFEX TMP v2.18.7):
//   R02 PositionEffect byte 75 -> beat 9 / d3
//   R02 before_qty     bytes 94..95 -> beat 11 / d6,d7
//   R32 PositionEffect byte 95 -> beat 11 / d7
//   R32 before_qty     bytes 114..115 -> beat 14 / d2,d3
//
// metadata_valid means the side-band bytes were captured. It is NOT mutation
// authorization. Integration logic must require the frozen HFT committed/
// de-duplicated report event before applying account/order state changes.
module hft_tmp_exec_position_tap #(
    parameter integer DATA_WIDTH = 64,
    parameter integer KEEP_WIDTH = 8
) (
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire                  tap_valid,
    input  wire [DATA_WIDTH-1:0] tap_data,
    input  wire [KEEP_WIDTH-1:0] tap_keep,
    input  wire                  tap_last,

    output reg                   metadata_valid,
    output reg [7:0]             last_msg_type,
    output reg [7:0]             last_position_effect,
    output reg [15:0]            last_before_qty
);
    wire [7:0] d0 = tap_data[63:56];
    wire [7:0] d1 = tap_data[55:48];
    wire [7:0] d2 = tap_data[47:40];
    wire [7:0] d3 = tap_data[39:32];
    wire [7:0] d4 = tap_data[31:24];
    wire [7:0] d5 = tap_data[23:16];
    wire [7:0] d6 = tap_data[15:8];
    wire [7:0] d7 = tap_data[7:0];

    reg active;
    reg [7:0] beat_index;
    reg [7:0] msg_type;
    reg [7:0] position_effect;
    reg [15:0] before_qty;
    reg position_effect_seen;
    reg before_qty_seen;

    // tap_keep is intentionally not used for these fields. They occur on full
    // interior beats of R02/R32 and the frozen decoder itself uses the same
    // fixed-beat convention without lane-mask qualification.
    wire unused_keep = ^tap_keep;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            active <= 1'b0;
            beat_index <= 8'd0;
            msg_type <= 8'd0;
            position_effect <= 8'd0;
            before_qty <= 16'd0;
            position_effect_seen <= 1'b0;
            before_qty_seen <= 1'b0;
            metadata_valid <= 1'b0;
            last_msg_type <= 8'd0;
            last_position_effect <= 8'd0;
            last_before_qty <= 16'd0;
        end else begin
            metadata_valid <= 1'b0;

            if (tap_valid) begin
                if (!active || beat_index == 8'd0) begin
                    active <= !tap_last;
                    beat_index <= tap_last ? 8'd0 : 8'd1;
                    msg_type <= 8'd0;
                    position_effect <= 8'd0;
                    before_qty <= 16'd0;
                    position_effect_seen <= 1'b0;
                    before_qty_seen <= 1'b0;
                end else begin
                    active <= !tap_last;
                    beat_index <= tap_last ? 8'd0 : beat_index + 8'd1;
                end

                // Common TMP MessageType at absolute byte 12.
                if (beat_index == 8'd1)
                    msg_type <= d4;

                if ((msg_type == `HFT_RMIC_TAIFEX_MSG_R02) && (beat_index == 8'd9)) begin
                    position_effect <= d3;
                    position_effect_seen <= 1'b1;
                end
                if ((msg_type == `HFT_RMIC_TAIFEX_MSG_R02) && (beat_index == 8'd11)) begin
                    before_qty <= {d6,d7};
                    before_qty_seen <= 1'b1;
                end

                if ((msg_type == `HFT_RMIC_TAIFEX_MSG_R32) && (beat_index == 8'd11)) begin
                    position_effect <= d7;
                    position_effect_seen <= 1'b1;
                end
                if ((msg_type == `HFT_RMIC_TAIFEX_MSG_R32) && (beat_index == 8'd14)) begin
                    before_qty <= {d2,d3};
                    before_qty_seen <= 1'b1;
                end

                if (tap_last) begin
                    if (((msg_type == `HFT_RMIC_TAIFEX_MSG_R02) ||
                         (msg_type == `HFT_RMIC_TAIFEX_MSG_R32)) &&
                        position_effect_seen && before_qty_seen) begin
                        metadata_valid <= 1'b1;
                        last_msg_type <= msg_type;
                        last_position_effect <= position_effect;
                        last_before_qty <= before_qty;
                    end
                end
            end
        end
    end
endmodule
