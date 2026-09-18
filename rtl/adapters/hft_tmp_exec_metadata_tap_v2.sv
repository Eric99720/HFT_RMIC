`timescale 1ns/1ps
`include "taifex_tmp_v2187_defs.svh"

// I5 execution-metadata tap with identity fields.
//
// The frozen order decoder already owns checksum and the common execution
// fields.  This side-band parser captures only the futures metadata that is
// missing from that interface plus order_id/report_seq so a later committed
// live/replay event can be matched explicitly instead of relying on cycle
// coincidence.
module hft_tmp_exec_metadata_tap_v2 #(
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
    output reg [31:0]            last_order_id,
    output reg [31:0]            last_report_seq,
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
    reg [31:0] order_id;
    reg [31:0] report_seq;
    reg [7:0] position_effect;
    reg [15:0] before_qty;
    reg order_id_seen, report_seq_seen, position_effect_seen, before_qty_seen;

    wire unused_keep = ^tap_keep;

    // In the real frozen TMP stream, R02/R32 may assert tap_last on the
    // same beat that carries the final report-sequence bytes.  Nonblocking
    // assignments below do not make report_seq_seen/report_seq visible until
    // after this clock edge, so terminal-beat completion must be recognized
    // explicitly from the current beat.
    wire r02_report_seq_this_beat =
        (msg_type == `HFT_RMIC_TAIFEX_MSG_R02) && (beat_index == 8'd16);
    wire r32_report_seq_this_beat =
        (msg_type == `HFT_RMIC_TAIFEX_MSG_R32) && (beat_index == 8'd18);
    wire report_seq_complete_now =
        report_seq_seen || r02_report_seq_this_beat || r32_report_seq_this_beat;
    wire [31:0] report_seq_value_now = r02_report_seq_this_beat ?
        {report_seq[31:24], d0, d1, d2} :
        (r32_report_seq_this_beat ? {d3, d4, d5, d6} : report_seq);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            active <= 1'b0;
            beat_index <= 8'd0;
            msg_type <= 8'd0;
            order_id <= 32'd0;
            report_seq <= 32'd0;
            position_effect <= 8'd0;
            before_qty <= 16'd0;
            order_id_seen <= 1'b0;
            report_seq_seen <= 1'b0;
            position_effect_seen <= 1'b0;
            before_qty_seen <= 1'b0;
            metadata_valid <= 1'b0;
            last_msg_type <= 8'd0;
            last_order_id <= 32'd0;
            last_report_seq <= 32'd0;
            last_position_effect <= 8'd0;
            last_before_qty <= 16'd0;
        end else begin
            metadata_valid <= 1'b0;
            if (tap_valid) begin
                if (!active || beat_index == 8'd0) begin
                    active <= !tap_last;
                    beat_index <= tap_last ? 8'd0 : 8'd1;
                    msg_type <= 8'd0;
                    order_id <= 32'd0;
                    report_seq <= 32'd0;
                    position_effect <= 8'd0;
                    before_qty <= 16'd0;
                    order_id_seen <= 1'b0;
                    report_seq_seen <= 1'b0;
                    position_effect_seen <= 1'b0;
                    before_qty_seen <= 1'b0;
                end else begin
                    active <= !tap_last;
                    beat_index <= tap_last ? 8'd0 : beat_index + 8'd1;
                end

                if (beat_index == 8'd1)
                    msg_type <= d4;

                if (((msg_type == `HFT_RMIC_TAIFEX_MSG_R02) ||
                     (msg_type == `HFT_RMIC_TAIFEX_MSG_R32)) &&
                    (beat_index == 8'd3)) begin
                    order_id <= {d4,d5,d6,d7};
                    order_id_seen <= 1'b1;
                end

                if (msg_type == `HFT_RMIC_TAIFEX_MSG_R02) begin
                    if (beat_index == 8'd9) begin
                        position_effect <= d3;
                        position_effect_seen <= 1'b1;
                    end
                    if (beat_index == 8'd11) begin
                        before_qty <= {d6,d7};
                        before_qty_seen <= 1'b1;
                    end
                    if (beat_index == 8'd15)
                        report_seq[31:24] <= d7;
                    if (beat_index == 8'd16) begin
                        report_seq[23:0] <= {d0,d1,d2};
                        report_seq_seen <= 1'b1;
                    end
                end

                if (msg_type == `HFT_RMIC_TAIFEX_MSG_R32) begin
                    if (beat_index == 8'd11) begin
                        position_effect <= d7;
                        position_effect_seen <= 1'b1;
                    end
                    if (beat_index == 8'd14) begin
                        before_qty <= {d2,d3};
                        before_qty_seen <= 1'b1;
                    end
                    if (beat_index == 8'd18) begin
                        report_seq <= {d3,d4,d5,d6};
                        report_seq_seen <= 1'b1;
                    end
                end

                if (tap_last) begin
                    if (((msg_type == `HFT_RMIC_TAIFEX_MSG_R02) ||
                         (msg_type == `HFT_RMIC_TAIFEX_MSG_R32)) &&
                        order_id_seen && report_seq_complete_now &&
                        position_effect_seen && before_qty_seen) begin
                        metadata_valid <= 1'b1;
                        last_msg_type <= msg_type;
                        last_order_id <= order_id;
                        last_report_seq <= report_seq_value_now;
                        last_position_effect <= position_effect;
                        last_before_qty <= before_qty;
                    end
                end
            end
        end
    end
endmodule
