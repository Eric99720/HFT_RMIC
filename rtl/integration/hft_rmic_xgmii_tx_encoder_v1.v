`timescale 1ns/1ps

// Integration-owned timing derivative.
// Provenance: deps/hft-full-system-fpga/rtl/network/xgmii/hft_xgmii_tx_encoder.v
// pinned at 50217fad1fd580f8c451ba893f9035f4be1dc21a.
//
// Functional ownership is unchanged.  The only datapath change is the
// Ethernet-minimum-frame padding CRC phase: the frozen generic byte-indexed
// CRC helper made crc_idx -> FCS a long routed path.  Padding bytes are always
// zero, so this derivative consumes a fixed two zero bytes per cycle (or one
// final byte) and removes the variable frame-RAM/index cone.
module hft_rmic_xgmii_tx_encoder_v1 #(
    parameter integer MAX_FRAME_BYTES = 2048,
    parameter integer DATA_WIDTH = 64,
    parameter integer KEEP_WIDTH = 8
) (
    input  wire                   clk,
    input  wire                   rst_n,

    input  wire                   s_axis_tvalid,
    output wire                   s_axis_tready,
    input  wire [DATA_WIDTH-1:0]  s_axis_tdata,
    input  wire [KEEP_WIDTH-1:0]  s_axis_tkeep,
    input  wire                   s_axis_tlast,
    input  wire                   s_axis_tuser,

    output reg  [DATA_WIDTH-1:0]  xgmii_txd,
    output reg  [KEEP_WIDTH-1:0]  xgmii_txc,

    output reg                    frame_done,
    output reg                    frame_error,
    output reg  [7:0]             error_code,
    output reg  [15:0]            frame_len,
    output reg  [31:0]            fcs_value
);
    localparam [7:0] XGMII_CTRL_IDLE = 8'h07;
    localparam [7:0] XGMII_CTRL_TERM = 8'hfd;
    localparam [7:0] XGMII_ERR_NONE = 8'h00;
    localparam [7:0] XGMII_ERR_FRAME_SIZE = 8'h07;
    localparam [7:0] XGMII_ERR_BAD_TKEEP = 8'h08;
    localparam [7:0] XGMII_ERR_TUSER = 8'h09;

    localparam integer FRAME_WORDS = (MAX_FRAME_BYTES + KEEP_WIDTH - 1) / KEEP_WIDTH;
    localparam [15:0] MAX_FRAME_BYTES_U16 = MAX_FRAME_BYTES;
    localparam [15:0] FRAME_WORDS_U16 = FRAME_WORDS;
    localparam [15:0] KEEP_WIDTH_U16 = KEEP_WIDTH;

    localparam [2:0] ST_IDLE   = 3'd0;
    localparam [2:0] ST_RECV   = 3'd1;
    localparam [2:0] ST_CRC    = 3'd2;
    localparam [2:0] ST_START  = 3'd3;
    localparam [2:0] ST_DATA   = 3'd4;
    localparam [2:0] ST_IFG    = 3'd5;

    reg [2:0] state;

    reg [DATA_WIDTH-1:0] frame_fifo_data [0:FRAME_WORDS-1];
    reg [KEEP_WIDTH-1:0] frame_fifo_keep [0:FRAME_WORDS-1];
    reg [15:0]           frame_wr_idx;
    reg [15:0]           input_byte_count;
    reg [15:0]           padded_frame_len;
    reg [15:0]           wire_byte_len;
    reg [15:0]           pad_bytes_remaining;
    reg [15:0]           tx_idx;
    reg [31:0]           crc_reg;
    reg [31:0]           next_crc_word_value;
    reg [2:0]            ifg_count;

    integer lane;
    integer valid_count;
    reg [15:0] next_input_len;
    reg        keep_bad;
    reg        capture_error;

    (* max_fanout = 16 *) wire [DATA_WIDTH-1:0] s_axis_tdata_crc = s_axis_tdata;
    (* max_fanout = 16 *) wire [KEEP_WIDTH-1:0] s_axis_tkeep_crc = s_axis_tkeep;

    assign s_axis_tready = (state == ST_IDLE) || (state == ST_RECV);

    function [31:0] next_crc32_byte;
        input [31:0] crc;
        input [7:0]  data;
        integer bit_idx;
        reg [31:0] c;
        begin
            c = crc ^ {24'd0, data};
            for (bit_idx = 0; bit_idx < 8; bit_idx = bit_idx + 1) begin
                if (c[0]) begin
                    c = (c >> 1) ^ 32'hedb88320;
                end else begin
                    c = c >> 1;
                end
            end
            next_crc32_byte = c;
        end
    endfunction

    // Fixed two-byte zero transform for Ethernet padding. Keeping the
    // transform independent of a byte index is the timing-critical change.
    function [31:0] next_crc32_zero2;
        input [31:0] crc;
        reg [31:0] c;
        begin
            c = next_crc32_byte(crc, 8'h00);
            c = next_crc32_byte(c, 8'h00);
            next_crc32_zero2 = c;
        end
    endfunction

    function [7:0] frame_byte_at;
        input [15:0] byte_idx;
        integer word_idx;
        integer lane_idx;
        begin
            word_idx = byte_idx / KEEP_WIDTH;
            lane_idx = byte_idx % KEEP_WIDTH;
            frame_byte_at = frame_fifo_data[word_idx][lane_idx*8 +: 8];
        end
    endfunction

    function [7:0] tx_payload_byte_at;
        input [15:0] byte_idx;
        input [15:0] payload_len;
        input [15:0] padded_len;
        input [31:0] fcs;
        begin
            if (byte_idx < payload_len) begin
                tx_payload_byte_at = frame_byte_at(byte_idx);
            end else if (byte_idx < padded_len) begin
                tx_payload_byte_at = 8'h00;
            end else begin
                case (byte_idx - padded_len)
                    16'd0: tx_payload_byte_at = fcs[7:0];
                    16'd1: tx_payload_byte_at = fcs[15:8];
                    16'd2: tx_payload_byte_at = fcs[23:16];
                    default: tx_payload_byte_at = fcs[31:24];
                endcase
            end
        end
    endfunction

    function [7:0] crc_data_byte_at;
        input [15:0] byte_idx;
        begin
            if (byte_idx < input_byte_count) begin
                crc_data_byte_at = frame_byte_at(byte_idx);
            end else begin
                crc_data_byte_at = 8'h00;
            end
        end
    endfunction

    function [31:0] next_crc32_word;
        input [31:0] crc;
        input [15:0] byte_idx;
        input [15:0] stop_idx;
        integer crc_lane;
        reg [31:0] c;
        reg [15:0] next_idx;
        begin
            c = crc;
            for (crc_lane = 0; crc_lane < KEEP_WIDTH; crc_lane = crc_lane + 1) begin
                next_idx = byte_idx + crc_lane;
                if (next_idx < stop_idx) begin
                    c = next_crc32_byte(c, crc_data_byte_at(next_idx));
                end
            end
            next_crc32_word = c;
        end
    endfunction

    function [31:0] next_crc32_axis_word;
        input [31:0] crc;
        input [DATA_WIDTH-1:0] data_word;
        input [KEEP_WIDTH-1:0] keep_word;
        integer crc_lane;
        reg [31:0] c;
        begin
            c = crc;
            for (crc_lane = 0; crc_lane < KEEP_WIDTH; crc_lane = crc_lane + 1) begin
                if (keep_word[crc_lane]) begin
                    c = next_crc32_byte(c, data_word[crc_lane*8 +: 8]);
                end
            end
            next_crc32_axis_word = c;
        end
    endfunction

    function keep_is_contiguous;
        input [KEEP_WIDTH-1:0] keep_value;
        integer k;
        reg seen_zero;
        begin
            keep_is_contiguous = 1'b1;
            seen_zero = 1'b0;
            for (k = 0; k < KEEP_WIDTH; k = k + 1) begin
                if (!keep_value[k]) begin
                    seen_zero = 1'b1;
                end else if (seen_zero) begin
                    keep_is_contiguous = 1'b0;
                end
            end
        end
    endfunction

    task set_idle_word;
        begin
            xgmii_txd <= {8{XGMII_CTRL_IDLE}};
            xgmii_txc <= {KEEP_WIDTH{1'b1}};
        end
    endtask

    task drive_start_word;
        begin
            xgmii_txd <= 64'hd5555555555555fb;
            xgmii_txc <= 8'h01;
            tx_idx <= 16'd0;
        end
    endtask

    task raise_error;
        input [7:0] code;
        begin
            frame_done <= 1'b1;
            frame_error <= 1'b1;
            error_code <= code;
            frame_len <= 16'd0;
            fcs_value <= 32'd0;
            frame_wr_idx <= 16'd0;
            input_byte_count <= 16'd0;
            set_idle_word();
            state <= ST_IDLE;
        end
    endtask

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE;
            frame_wr_idx <= 16'd0;
            input_byte_count <= 16'd0;
            padded_frame_len <= 16'd0;
            wire_byte_len <= 16'd0;
            pad_bytes_remaining <= 16'd0;
            tx_idx <= 16'd0;
            crc_reg <= 32'hffff_ffff;
            ifg_count <= 3'd0;
            set_idle_word();
            frame_done <= 1'b0;
            frame_error <= 1'b0;
            error_code <= XGMII_ERR_NONE;
            frame_len <= 16'd0;
            fcs_value <= 32'd0;
        end else begin
            frame_done <= 1'b0;
            frame_error <= 1'b0;
            error_code <= XGMII_ERR_NONE;

            case (state)
                ST_IDLE: begin
                    set_idle_word();
                    frame_wr_idx <= 16'd0;
                    input_byte_count <= 16'd0;
                    if (s_axis_tvalid) begin
                        valid_count = 0;
                        keep_bad = !keep_is_contiguous(s_axis_tkeep) || (s_axis_tkeep == {KEEP_WIDTH{1'b0}});
                        for (lane = 0; lane < KEEP_WIDTH; lane = lane + 1) begin
                            if (s_axis_tkeep[lane]) begin
                                valid_count = valid_count + 1;
                            end
                        end
                        next_input_len = valid_count[15:0];
                        if (s_axis_tuser) begin
                            raise_error(XGMII_ERR_TUSER);
                        end else if (keep_bad || (!s_axis_tlast && (s_axis_tkeep != {KEEP_WIDTH{1'b1}}))) begin
                            raise_error(XGMII_ERR_BAD_TKEEP);
                        end else if (next_input_len > MAX_FRAME_BYTES_U16) begin
                            raise_error(XGMII_ERR_FRAME_SIZE);
                        end else begin
                            next_crc_word_value = next_crc32_axis_word(32'hffff_ffff, s_axis_tdata_crc, s_axis_tkeep_crc);
                            frame_fifo_data[0] <= s_axis_tdata;
                            frame_fifo_keep[0] <= s_axis_tkeep;
                            frame_wr_idx <= 16'd1;
                            input_byte_count <= next_input_len;
                            padded_frame_len <= (next_input_len < 16'd60) ? 16'd60 : next_input_len;
                            wire_byte_len <= ((next_input_len < 16'd60) ? 16'd60 : next_input_len) + 16'd4;
                            if (s_axis_tlast) begin
                                crc_reg <= next_crc_word_value;
                                if (next_input_len < 16'd60) begin
                                    pad_bytes_remaining <= 16'd60 - next_input_len;
                                    state <= ST_CRC;
                                end else begin
                                    fcs_value <= ~next_crc_word_value;
                                    frame_len <= next_input_len;
                                    drive_start_word();
                                    state <= ST_DATA;
                                end
                            end else begin
                                crc_reg <= next_crc_word_value;
                                state <= ST_RECV;
                            end
                        end
                    end
                end

                ST_RECV: begin
                    set_idle_word();
                    if (s_axis_tvalid) begin
                        valid_count = 0;
                        keep_bad = !keep_is_contiguous(s_axis_tkeep) || (s_axis_tkeep == {KEEP_WIDTH{1'b0}});
                        for (lane = 0; lane < KEEP_WIDTH; lane = lane + 1) begin
                            if (s_axis_tkeep[lane]) begin
                                valid_count = valid_count + 1;
                            end
                        end
                        next_input_len = input_byte_count + valid_count[15:0];
                        capture_error = 1'b0;
                        if (s_axis_tuser) begin
                            capture_error = 1'b1;
                            raise_error(XGMII_ERR_TUSER);
                        end else if (keep_bad || (!s_axis_tlast && (s_axis_tkeep != {KEEP_WIDTH{1'b1}}))) begin
                            capture_error = 1'b1;
                            raise_error(XGMII_ERR_BAD_TKEEP);
                        end else if ((frame_wr_idx >= FRAME_WORDS_U16) || (next_input_len > MAX_FRAME_BYTES_U16)) begin
                            capture_error = 1'b1;
                            raise_error(XGMII_ERR_FRAME_SIZE);
                        end

                        if (!capture_error) begin
                            next_crc_word_value = next_crc32_axis_word(crc_reg, s_axis_tdata_crc, s_axis_tkeep_crc);
                            frame_fifo_data[frame_wr_idx] <= s_axis_tdata;
                            frame_fifo_keep[frame_wr_idx] <= s_axis_tkeep;
                            frame_wr_idx <= frame_wr_idx + 16'd1;
                            input_byte_count <= next_input_len;
                            padded_frame_len <= (next_input_len < 16'd60) ? 16'd60 : next_input_len;
                            wire_byte_len <= ((next_input_len < 16'd60) ? 16'd60 : next_input_len) + 16'd4;
                            if (s_axis_tlast) begin
                                crc_reg <= next_crc_word_value;
                                if (next_input_len < 16'd60) begin
                                    pad_bytes_remaining <= 16'd60 - next_input_len;
                                    state <= ST_CRC;
                                end else begin
                                    fcs_value <= ~next_crc_word_value;
                                    frame_len <= next_input_len;
                                    drive_start_word();
                                    state <= ST_DATA;
                                end
                            end else begin
                                crc_reg <= next_crc_word_value;
                            end
                        end
                    end
                end

                ST_CRC: begin
                    set_idle_word();
                    if (pad_bytes_remaining >= 16'd2) begin
                        next_crc_word_value = next_crc32_zero2(crc_reg);
                        crc_reg <= next_crc_word_value;
                        if (pad_bytes_remaining == 16'd2) begin
                            pad_bytes_remaining <= 16'd0;
                            fcs_value <= ~next_crc_word_value;
                            frame_len <= padded_frame_len;
                            state <= ST_START;
                        end else begin
                            pad_bytes_remaining <= pad_bytes_remaining - 16'd2;
                        end
                    end else if (pad_bytes_remaining == 16'd1) begin
                        next_crc_word_value = next_crc32_byte(crc_reg, 8'h00);
                        crc_reg <= next_crc_word_value;
                        pad_bytes_remaining <= 16'd0;
                        fcs_value <= ~next_crc_word_value;
                        frame_len <= padded_frame_len;
                        state <= ST_START;
                    end else begin
                        fcs_value <= ~crc_reg;
                        frame_len <= padded_frame_len;
                        state <= ST_START;
                    end
                end

                ST_START: begin
                    drive_start_word();
                    state <= ST_DATA;
                end

                ST_DATA: begin
                    xgmii_txd <= {DATA_WIDTH{1'b0}};
                    xgmii_txc <= {KEEP_WIDTH{1'b0}};
                    for (lane = 0; lane < KEEP_WIDTH; lane = lane + 1) begin
                        if ((tx_idx + lane) < wire_byte_len) begin
                            xgmii_txd[lane*8 +: 8] <= tx_payload_byte_at(tx_idx + lane, input_byte_count, padded_frame_len, fcs_value);
                            xgmii_txc[lane] <= 1'b0;
                        end else if ((tx_idx + lane) == wire_byte_len) begin
                            xgmii_txd[lane*8 +: 8] <= XGMII_CTRL_TERM;
                            xgmii_txc[lane] <= 1'b1;
                        end else begin
                            xgmii_txd[lane*8 +: 8] <= XGMII_CTRL_IDLE;
                            xgmii_txc[lane] <= 1'b1;
                        end
                    end
                    if ((tx_idx + KEEP_WIDTH) > wire_byte_len) begin
                        frame_done <= 1'b1;
                        ifg_count <= 3'd0;
                        state <= ST_IFG;
                    end else begin
                        tx_idx <= tx_idx + KEEP_WIDTH;
                    end
                end

                ST_IFG: begin
                    set_idle_word();
                    if (ifg_count == 3'd1) begin
                        state <= ST_IDLE;
                    end else begin
                        ifg_count <= ifg_count + 3'd1;
                    end
                end

                default: begin
                    state <= ST_IDLE;
                end
            endcase
        end
    end
endmodule
