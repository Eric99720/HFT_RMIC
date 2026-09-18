`timescale 1ns/1ps
module hft_rmic_cached_exact_map_v1 #(
    parameter integer KEY_W = 32,
    parameter integer VALUE_W = 8,
    parameter integer ENTRIES = 16,
    parameter integer INDEX_W = (ENTRIES <= 1) ? 1 : $clog2(ENTRIES)
) (
    input wire clk, input wire rst_n,
    input wire cfg_we, input wire [INDEX_W-1:0] cfg_index,
    input wire cfg_valid, input wire [KEY_W-1:0] cfg_key,
    input wire [VALUE_W-1:0] cfg_value,
    input wire [KEY_W-1:0] hot_key,
    input wire [KEY_W-1:0] lookup_key,
    output wire cache_ready,
    output wire lookup_hit,
    output wire lookup_ambiguous,
    output wire [VALUE_W-1:0] lookup_value
);
    wire raw_hit, raw_ambiguous;
    wire [VALUE_W-1:0] raw_value;
    reg cache_valid;
    reg [KEY_W-1:0] cached_key;
    reg cached_hit, cached_ambiguous;
    reg [VALUE_W-1:0] cached_value;

    configurable_exact_map #(
        .KEY_W(KEY_W), .VALUE_W(VALUE_W), .ENTRIES(ENTRIES), .INDEX_W(INDEX_W)
    ) u_exact_map (
        .clk(clk), .rst_n(rst_n),
        .cfg_we(cfg_we), .cfg_index(cfg_index), .cfg_valid(cfg_valid),
        .cfg_key(cfg_key), .cfg_value(cfg_value),
        .lookup_key(hot_key), .lookup_hit(raw_hit),
        .lookup_ambiguous(raw_ambiguous), .lookup_value(raw_value)
    );

    wire hot_key_current = (hot_key == cached_key);
    wire lookup_key_match = (lookup_key == cached_key);
    assign cache_ready = cache_valid && hot_key_current && !cfg_we;
    assign lookup_hit = cache_ready && lookup_key_match && cached_hit;
    assign lookup_ambiguous = cache_ready && lookup_key_match && cached_ambiguous;
    assign lookup_value = cached_value;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cache_valid <= 1'b0;
            cached_key <= {KEY_W{1'b0}};
            cached_hit <= 1'b0;
            cached_ambiguous <= 1'b0;
            cached_value <= {VALUE_W{1'b0}};
        end else if (cfg_we) begin
            cache_valid <= 1'b0;
        end else begin
            cached_key <= hot_key;
            cached_hit <= raw_hit;
            cached_ambiguous <= raw_ambiguous;
            cached_value <= raw_value;
            cache_valid <= 1'b1;
        end
    end
endmodule
