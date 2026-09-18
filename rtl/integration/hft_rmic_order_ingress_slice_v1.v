`timescale 1ns/1ps

module hft_rmic_order_ingress_slice_v1 #(
    parameter integer ORDER_WIDTH = 256
) (
    input  wire                   clk,
    input  wire                   rst_n,
    input  wire                   clear,
    input  wire                   s_valid,
    output wire                   s_ready,
    input  wire [ORDER_WIDTH-1:0] s_data,
    input  wire                   s_source_prebuild,
    output wire                   m_valid,
    input  wire                   m_ready,
    output wire [ORDER_WIDTH-1:0] m_data,
    output wire                   m_source_prebuild
);
    reg                   full;
    reg [ORDER_WIDTH-1:0] data_q;
    reg                   source_prebuild_q;

    assign s_ready = ~full || m_ready;
    assign m_valid = full;
    assign m_data = data_q;
    assign m_source_prebuild = source_prebuild_q;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            full <= 1'b0;
            data_q <= {ORDER_WIDTH{1'b0}};
            source_prebuild_q <= 1'b0;
        end else if (clear) begin
            full <= 1'b0;
        end else if (s_ready) begin
            full <= s_valid;
            if (s_valid) begin
                data_q <= s_data;
                source_prebuild_q <= s_source_prebuild;
            end
        end
    end
endmodule
