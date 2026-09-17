`timescale 1ns/1ps

// CI-only behavioral contract stub for the private frozen RMIC AMU dependency.
// It verifies integration wrapper packing and AMU operation semantics without
// pretending to reproduce the bank/hash/BRAM implementation.  Local Vivado
// integration must compile the real pinned deps/RMIC RTL instead.
module amu_banked_double_hash_v2 #(
    parameter integer TABLE_SIZE = 64,
    parameter integer BANKS = 8,
    parameter integer STASH_SIZE = 4,
    parameter integer KEY_W = 32,
    parameter integer VALUE_W = 96
) (
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire                     req_valid,
    output wire                     req_ready,
    input  wire [1:0]               req_op,
    input  wire [KEY_W-1:0]         req_key,
    input  wire [VALUE_W-1:0]       req_value,
    output reg                      rsp_valid,
    input  wire                     rsp_ready,
    output reg                      rsp_ok,
    output reg                      rsp_found,
    output reg [2:0]                rsp_status,
    output reg [VALUE_W-1:0]        rsp_value,
    output reg [$clog2(BANKS)-1:0]  rsp_bank,
    output reg                      rsp_in_stash,
    output reg                      init_done
);
    localparam [1:0] OP_LOOKUP = 2'd0;
    localparam [1:0] OP_INSERT = 2'd1;
    localparam [1:0] OP_DELETE = 2'd2;
    localparam [1:0] OP_UPDATE = 2'd3;
    localparam [2:0] ST_OK        = 3'd0;
    localparam [2:0] ST_NOT_FOUND = 3'd1;
    localparam [2:0] ST_EXISTS    = 3'd2;
    localparam [2:0] ST_FULL      = 3'd3;
    localparam [2:0] ST_BAD_OP    = 3'd4;

    reg [TABLE_SIZE-1:0] valid_bits;
    reg [KEY_W-1:0] keys [0:TABLE_SIZE-1];
    reg [VALUE_W-1:0] values [0:TABLE_SIZE-1];
    integer i;
    integer hit_idx;
    integer empty_idx;

    assign req_ready = init_done && (!rsp_valid || rsp_ready);

    always @(*) begin
        hit_idx = -1;
        empty_idx = -1;
        for (i=0; i<TABLE_SIZE; i=i+1) begin
            if (valid_bits[i] && keys[i] == req_key && hit_idx < 0)
                hit_idx = i;
            if (!valid_bits[i] && empty_idx < 0)
                empty_idx = i;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_bits <= {TABLE_SIZE{1'b0}};
            rsp_valid <= 1'b0;
            rsp_ok <= 1'b0;
            rsp_found <= 1'b0;
            rsp_status <= ST_NOT_FOUND;
            rsp_value <= {VALUE_W{1'b0}};
            rsp_bank <= {$clog2(BANKS){1'b0}};
            rsp_in_stash <= 1'b0;
            init_done <= 1'b0;
        end else begin
            init_done <= 1'b1;
            if (rsp_valid && rsp_ready)
                rsp_valid <= 1'b0;

            if (req_valid && req_ready) begin
                rsp_valid <= 1'b1;
                rsp_ok <= 1'b0;
                rsp_found <= 1'b0;
                rsp_status <= ST_BAD_OP;
                rsp_value <= {VALUE_W{1'b0}};
                rsp_bank <= {$clog2(BANKS){1'b0}};
                rsp_in_stash <= 1'b0;

                case (req_op)
                    OP_LOOKUP: begin
                        if (hit_idx >= 0) begin
                            rsp_ok <= 1'b1;
                            rsp_found <= 1'b1;
                            rsp_status <= ST_OK;
                            rsp_value <= values[hit_idx];
                        end else begin
                            rsp_status <= ST_NOT_FOUND;
                        end
                    end
                    OP_INSERT: begin
                        if (hit_idx >= 0) begin
                            rsp_found <= 1'b1;
                            rsp_status <= ST_EXISTS;
                            rsp_value <= values[hit_idx];
                        end else if (empty_idx >= 0) begin
                            valid_bits[empty_idx] <= 1'b1;
                            keys[empty_idx] <= req_key;
                            values[empty_idx] <= req_value;
                            rsp_ok <= 1'b1;
                            rsp_found <= 1'b1;
                            rsp_status <= ST_OK;
                            rsp_value <= req_value;
                        end else begin
                            rsp_status <= ST_FULL;
                        end
                    end
                    OP_UPDATE: begin
                        if (hit_idx >= 0) begin
                            values[hit_idx] <= req_value;
                            rsp_ok <= 1'b1;
                            rsp_found <= 1'b1;
                            rsp_status <= ST_OK;
                            rsp_value <= req_value;
                        end else begin
                            rsp_status <= ST_NOT_FOUND;
                        end
                    end
                    OP_DELETE: begin
                        if (hit_idx >= 0) begin
                            valid_bits[hit_idx] <= 1'b0;
                            rsp_ok <= 1'b1;
                            rsp_found <= 1'b1;
                            rsp_status <= ST_OK;
                            rsp_value <= values[hit_idx];
                        end else begin
                            rsp_status <= ST_NOT_FOUND;
                        end
                    end
                    default: rsp_status <= ST_BAD_OP;
                endcase
            end
        end
    end
endmodule
