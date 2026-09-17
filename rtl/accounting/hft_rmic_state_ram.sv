`timescale 1ns/1ps

// Integration-owned state RAM with identical one-cycle synchronous read
// semantics in Icarus and Vivado. Vivado uses XPM block RAM explicitly so the
// physical memory primitive is not left to inference heuristics.
module hft_rmic_state_ram #(
    parameter integer DEPTH = 256,
    parameter integer ADDR_W = 8,
    parameter integer DATA_W = 321
) (
    input  wire                  clk,
    input  wire                  rd_en,
    input  wire [ADDR_W-1:0]     rd_addr,
    output wire [DATA_W-1:0]     rd_data,
    input  wire                  wr_en,
    input  wire [ADDR_W-1:0]     wr_addr,
    input  wire [DATA_W-1:0]     wr_data
);
`ifdef HFT_RMIC_BEHAVIORAL_RAM
    reg [DATA_W-1:0] mem [0:DEPTH-1];
    reg [DATA_W-1:0] rd_data_r;
    assign rd_data = rd_data_r;

    always @(posedge clk) begin
        if (wr_en)
            mem[wr_addr] <= wr_data;
    end

    always @(posedge clk) begin
        if (rd_en)
            rd_data_r <= mem[rd_addr];
    end
`else
    wire dbiterr_unused;
    wire sbiterr_unused;

    xpm_memory_sdpram #(
        .ADDR_WIDTH_A(ADDR_W),
        .ADDR_WIDTH_B(ADDR_W),
        .AUTO_SLEEP_TIME(0),
        .BYTE_WRITE_WIDTH_A(DATA_W),
        .CASCADE_HEIGHT(0),
        .CLOCKING_MODE("common_clock"),
        .ECC_MODE("no_ecc"),
        .MEMORY_INIT_FILE("none"),
        .MEMORY_INIT_PARAM("0"),
        .MEMORY_OPTIMIZATION("true"),
        .MEMORY_PRIMITIVE("block"),
        .MEMORY_SIZE(DEPTH * DATA_W),
        .MESSAGE_CONTROL(0),
        .READ_DATA_WIDTH_B(DATA_W),
        .READ_LATENCY_B(1),
        .READ_RESET_VALUE_B("0"),
        .RST_MODE_A("SYNC"),
        .RST_MODE_B("SYNC"),
        .SIM_ASSERT_CHK(0),
        .USE_EMBEDDED_CONSTRAINT(0),
        .USE_MEM_INIT(0),
        .USE_MEM_INIT_MMI(0),
        .WAKEUP_TIME("disable_sleep"),
        .WRITE_DATA_WIDTH_A(DATA_W),
        .WRITE_MODE_B("read_first"),
        .WRITE_PROTECT(1)
    ) u_xpm_state (
        .dbiterrb(dbiterr_unused),
        .doutb(rd_data),
        .sbiterrb(sbiterr_unused),
        .addra(wr_addr),
        .addrb(rd_addr),
        .clka(clk),
        .clkb(clk),
        .dina(wr_data),
        .ena(wr_en),
        .enb(rd_en),
        .injectdbiterra(1'b0),
        .injectsbiterra(1'b0),
        .regceb(1'b1),
        .rstb(1'b0),
        .sleep(1'b0),
        .wea(wr_en)
    );
`endif

    initial begin
        if (DEPTH < 2)
            $error("hft_rmic_state_ram DEPTH must be >= 2");
        if ((1 << ADDR_W) < DEPTH)
            $error("hft_rmic_state_ram ADDR_W=%0d too small for DEPTH=%0d", ADDR_W, DEPTH);
    end
endmodule
