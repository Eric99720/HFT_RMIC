`timescale 1ns/1ps
`include "taifex_tmp_v2187_defs.svh"

// Lightweight side-band parser for the single field missing from the frozen
// HFT R02/R32 decoder: PositionEffect.
//
// The frozen decoder already owns checksum verification and extracts order ID,
// side, price, quantity, LastPx, LastQty, LeavesQty and report sequence.  This
// tap runs in parallel on the same accepted 64-bit TMP payload stream and only
// captures PositionEffect at the official fixed offsets:
//   R02 byte 75 -> beat 9, lane d3
//   R32 byte 95 -> beat 11, lane d7
//
// `last_*` remains stable until another packet is observed.  Integration logic
// must use the frozen HFT committed/de-duplicated report event as the mutation
// enable; tap_valid is metadata availability, not authorization to mutate state.
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
    output reg [7:0]             last_position_effect
);
    localparam [7:0] MSG_R02 = 8'd102;
    localparam [7:0] MSG_R32 = 8'd132;

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
    reg position_effect_seen;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            active <= 1'b0;
            beat_index <= 8'd0;
            msg_type <= 8'd0;
            position_effect <= 8'd0;
            position_effect_seen <= 1'b0;
            metadata_valid <= 1'b0;
            last_msg_type <= 8'd0;
            last_position_effect <= 8'd0;
        end else begin
            metadata_valid <= 1'b0;

            if (tap_valid) begin
                if (!active || beat_index == 8'd0) begin
                    active <= !tap_last;
                    beat_index <= tap_last ? 8'd0 : 8'd1;
                    msg_type <= 8'd0;
                    position_effect <= 8'd0;
                    position_effect_seen <= 1'b0;
                end else begin
                    active <= !tap_last;
                    beat_index <= tap_last ? 8'd0 : beat_index + 8'd1;
                end

                // Common TMP MessageType is absolute byte offset 12.
                if (beat_index == 8'd1)
                    msg_type <= d4;

                // R02 PositionEffect: byte 75 = beat 9 / d3.
                if ((msg_type == MSG_R02) && (beat_index == 8'd9) && tap_keep[4]) begin
                    position_effect <= d3;
                    position_effect_seen <= 1'b1;
                end

                // R32 PositionEffect: byte 95 = beat 11 / d7.
                if ((msg_type == MSG_R32) && (beat_index == 8'd11) && tap_keep[0]) begin
                    position_effect <= d7;
                    position_effect_seen <= 1'b1;
                end

                if (tap_last) begin
                    // The report packets are longer than the PositionEffect
                    // offsets, so the nonblocking-captured value is already
                    // available from an earlier beat here.
                    if (((msg_type == MSG_R02) || (msg_type == MSG_R32)) &&
                        position_effect_seen) begin
                        metadata_valid <= 1'b1;
                        last_msg_type <= msg_type;
                        last_position_effect <= position_effect;
                    end
                end
            end
        end
    end
endmodule
