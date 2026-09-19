`timescale 1ns/1ps
module amu_bank_ram #(
    parameter integer DEPTH=8,
    parameter integer ADDR_W=3,
    parameter integer DATA_W=65
)(
    input wire clk,
    input wire init_we,
    input wire [ADDR_W-1:0] init_addr,
    input wire rd_en,
    input wire [ADDR_W-1:0] rd_addr,
    output wire [DATA_W-1:0] rd_data,
    input wire wr_en,
    input wire [ADDR_W-1:0] wr_addr,
    input wire [DATA_W-1:0] wr_data
);
    reg [DATA_W-1:0] mem [0:DEPTH-1];
    reg [DATA_W-1:0] rd_q;
    assign rd_data = rd_q;
    always @(posedge clk) begin
        if (init_we) mem[init_addr] <= {DATA_W{1'b0}};
        else if (wr_en) mem[wr_addr] <= wr_data;
        if (rd_en) rd_q <= mem[rd_addr];
    end
endmodule
