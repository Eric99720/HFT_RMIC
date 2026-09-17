`timescale 1ns/1ps

// Small configuration-time exact-match map used at the HFT/RMIC integration
// boundary.  It is intentionally separate from the RMIC order AMU: these maps
// translate external identifiers (investor account / HFT symbol slot) into the
// compact normalized IDs consumed by the frozen RMIC core.
module configurable_exact_map #(
    parameter integer KEY_W = 32,
    parameter integer VALUE_W = 8,
    parameter integer ENTRIES = 16,
    parameter integer INDEX_W = (ENTRIES <= 1) ? 1 : $clog2(ENTRIES)
) (
    input  wire                   clk,
    input  wire                   rst_n,

    input  wire                   cfg_we,
    input  wire [INDEX_W-1:0]     cfg_index,
    input  wire                   cfg_valid,
    input  wire [KEY_W-1:0]       cfg_key,
    input  wire [VALUE_W-1:0]     cfg_value,

    input  wire [KEY_W-1:0]       lookup_key,
    output reg                    lookup_hit,
    output reg                    lookup_ambiguous,
    output reg  [VALUE_W-1:0]     lookup_value
);
    reg [ENTRIES-1:0] valid_bits;
    reg [KEY_W-1:0] key_mem [0:ENTRIES-1];
    reg [VALUE_W-1:0] value_mem [0:ENTRIES-1];

    integer i;
    reg found;
    always @(*) begin
        lookup_hit = 1'b0;
        lookup_ambiguous = 1'b0;
        lookup_value = {VALUE_W{1'b0}};
        found = 1'b0;

        for (i = 0; i < ENTRIES; i = i + 1) begin
            if (valid_bits[i] && (key_mem[i] == lookup_key)) begin
                if (!found) begin
                    found = 1'b1;
                    lookup_hit = 1'b1;
                    lookup_value = value_mem[i];
                end else begin
                    // Duplicate configuration is treated as unsafe rather than
                    // selecting an arbitrary mapping entry.
                    lookup_ambiguous = 1'b1;
                    lookup_hit = 1'b0;
                end
            end
        end
    end

    integer r;
    always @(posedge clk) begin
        if (!rst_n) begin
            valid_bits <= {ENTRIES{1'b0}};
            for (r = 0; r < ENTRIES; r = r + 1) begin
                key_mem[r] <= {KEY_W{1'b0}};
                value_mem[r] <= {VALUE_W{1'b0}};
            end
        end else if (cfg_we && (cfg_index < ENTRIES)) begin
            valid_bits[cfg_index] <= cfg_valid;
            key_mem[cfg_index] <= cfg_key;
            value_mem[cfg_index] <= cfg_value;
        end
    end

    initial begin
        if (ENTRIES < 1)
            $error("configurable_exact_map ENTRIES must be >= 1");
    end
endmodule
