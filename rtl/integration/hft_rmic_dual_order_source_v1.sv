`timescale 1ns/1ps

// I4 order-source ownership shim.
//
// Frozen HFT has two order_data producers at the R01 boundary when
// ENABLE_R01_PREBUILD=1: the ordinary bridge pending path and the speculative
// prebuild path.  Prebuild has the same priority it has in the frozen top, but
// both paths must hand ownership to the same RM gate before reaching R01.
module hft_rmic_dual_order_source_v1 #(
    parameter integer ORDER_WIDTH = 256
) (
    input  wire                     legacy_valid,
    output wire                     legacy_ready,
    input  wire [ORDER_WIDTH-1:0]   legacy_data,

    input  wire                     prebuild_valid,
    output wire                     prebuild_accept,
    input  wire [ORDER_WIDTH-1:0]   prebuild_data,

    output wire                     risk_valid,
    input  wire                     risk_ready,
    output wire [ORDER_WIDTH-1:0]   risk_data,
    output wire                     risk_source_prebuild
);
    assign risk_source_prebuild = prebuild_valid;
    assign risk_valid = prebuild_valid | legacy_valid;
    assign risk_data = prebuild_valid ? prebuild_data : legacy_data;

    // Prebuild priority intentionally mirrors the frozen app-top ownership.
    assign prebuild_accept = prebuild_valid & risk_ready;
    assign legacy_ready = ~prebuild_valid & risk_ready;
endmodule
