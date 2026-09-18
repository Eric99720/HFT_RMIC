`timescale 1ns/1ps

module hft_rmic_exec_commit_fifo_v1 #(
    parameter integer DEPTH = 8,
    parameter integer PTR_W = (DEPTH <= 2) ? 1 : $clog2(DEPTH)
) (
    input wire clk, input wire rst_n, input wire flush,
    input wire s_valid, output wire s_ready,
    input wire [7:0] s_msg_type, input wire [7:0] s_status_code,
    input wire [7:0] s_exec_type, input wire [31:0] s_order_id,
    input wire s_side, input wire [7:0] s_position_effect,
    input wire [31:0] s_order_price, input wire [15:0] s_last_qty,
    input wire [15:0] s_leaves_qty, input wire [15:0] s_before_qty,
    output wire m_valid, input wire m_ready,
    output wire [7:0] m_msg_type, output wire [7:0] m_status_code,
    output wire [7:0] m_exec_type, output wire [31:0] m_order_id,
    output wire m_side, output wire [7:0] m_position_effect,
    output wire [31:0] m_order_price, output wire [15:0] m_last_qty,
    output wire [15:0] m_leaves_qty, output wire [15:0] m_before_qty,
    output reg overflow_sticky, output wire [PTR_W:0] occupancy
);
    localparam integer W = 8+8+8+32+1+8+32+16+16+16;
    reg [W-1:0] mem [0:DEPTH-1];
    reg [PTR_W-1:0] wr_ptr, rd_ptr;
    reg [PTR_W:0] count;
    wire push = s_valid && s_ready;
    wire pop = m_valid && m_ready;
    assign s_ready = (count < DEPTH);
    assign m_valid = (count != 0);
    assign occupancy = count;
    wire [W-1:0] front = mem[rd_ptr];
    assign {m_msg_type,m_status_code,m_exec_type,m_order_id,m_side,
            m_position_effect,m_order_price,m_last_qty,m_leaves_qty,m_before_qty} = front;

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            wr_ptr <= 0; rd_ptr <= 0; count <= 0; overflow_sticky <= 1'b0;
        end else if(flush) begin
            wr_ptr <= 0; rd_ptr <= 0; count <= 0; overflow_sticky <= 1'b0;
        end else begin
            if(s_valid && !s_ready) overflow_sticky <= 1'b1;
            if(push) begin
                mem[wr_ptr] <= {s_msg_type,s_status_code,s_exec_type,s_order_id,s_side,
                                s_position_effect,s_order_price,s_last_qty,s_leaves_qty,s_before_qty};
                wr_ptr <= (wr_ptr == DEPTH-1) ? 0 : wr_ptr + 1'b1;
            end
            if(pop) rd_ptr <= (rd_ptr == DEPTH-1) ? 0 : rd_ptr + 1'b1;
            case ({push,pop})
                2'b10: count <= count + 1'b1;
                2'b01: count <= count - 1'b1;
                default: count <= count;
            endcase
        end
    end
    initial begin
        if(DEPTH < 2) $error("exec commit FIFO DEPTH must be >= 2");
    end
endmodule
