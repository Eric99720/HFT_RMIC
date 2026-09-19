`timescale 1ns/1ps

// Integration-owned one-stage-lower-latency derivative of the pinned RMIC AMU.
// Provenance: Eric99720/RMIC@de6c300f4f18b18296f013287ab0eca70d3abb72
// rtl/amu_banked_double_hash_v2.sv
//
// The frozen AMU pipeline is req -> s0 -> hash -> bank/match -> rsp.
// I5 timing evidence shows the AMU INSERT round trip is now the dominant CL2EX
// leg after parallel admission and the L0 futures-state cache. This derivative
// removes only the s0 register stage: accepted request fields feed the registered
// hash stage directly. Bank topology, collision semantics, stash behavior,
// forwarding, initialization and response semantics are unchanged.
module hft_rmic_amu_banked_double_hash_fast_v1 #(
    parameter integer TABLE_SIZE = 4096,
    parameter integer BANKS = 8,
    parameter integer STASH_SIZE = 4,
    parameter integer KEY_W = 32,
    parameter integer VALUE_W = 128
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
    output reg  [2:0]               rsp_status,
    output reg  [VALUE_W-1:0]       rsp_value,
    output reg  [$clog2(BANKS)-1:0] rsp_bank,
    output reg                      rsp_in_stash,
    output wire                     init_done
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

    localparam integer BANK_DEPTH = TABLE_SIZE / BANKS;
    localparam integer BANK_ADDR_W = $clog2(BANK_DEPTH);
    localparam integer BANK_W = $clog2(BANKS);
    localparam integer ENTRY_W = 1 + KEY_W + VALUE_W;
    localparam integer ENTRY_VALUE_LSB = 0;
    localparam integer ENTRY_KEY_LSB = VALUE_W;
    localparam integer ENTRY_VALID_BIT = VALUE_W + KEY_W;
    localparam integer STASH_IDX_W = (STASH_SIZE <= 1) ? 1 : $clog2(STASH_SIZE);

    localparam [31:0] HASH_C0 = 32'h9E3779B1;
    localparam [31:0] HASH_C1 = 32'h85EBCA77;

    // Each physical bank is a separate 1-D RAM instance.  This is deliberate:
    // Vivado 2022.1 flattened the previous 3-D bank_mem[bank][address] array into
    // registers instead of BRAM, which caused ~662k FF / ~191k LUT and an SLL
    // routing failure on U50.
    wire [ENTRY_W-1:0] bank_rdata [0:BANKS-1];
    reg  [BANK_ADDR_W-1:0] m_addr [0:BANKS-1];

    reg [STASH_SIZE-1:0] stash_valid;
    reg [KEY_W-1:0] stash_key [0:STASH_SIZE-1];
    reg [VALUE_W-1:0] stash_value [0:STASH_SIZE-1];

    reg s0_valid;
    reg [1:0] s0_op;
    reg [KEY_W-1:0] s0_key;
    reg [VALUE_W-1:0] s0_value;

    reg h_valid;
    reg [1:0] h_op;
    reg [KEY_W-1:0] h_key;
    reg [VALUE_W-1:0] h_value;
    reg [31:0] h_hash0;
    reg [31:0] h_hash1;

    reg m_valid;
    reg [1:0] m_op;
    reg [KEY_W-1:0] m_key;
    reg [VALUE_W-1:0] m_value;

    reg fwd_valid;
    reg [BANK_W-1:0] fwd_bank;
    reg [BANK_ADDR_W-1:0] fwd_addr;
    reg [ENTRY_W-1:0] fwd_data;

    reg init_active;
    reg [BANK_ADDR_W-1:0] init_addr;
    assign init_done = !init_active;

    wire pipe_ce = !(rsp_valid && !rsp_ready);
    assign req_ready = init_done && pipe_ce;
    wire req_accept = req_valid && req_ready;

    wire [BANK_ADDR_W-1:0] hash_base = h_hash0[31 -: BANK_ADDR_W];
    wire [BANK_ADDR_W-1:0] hash_step = h_hash1[31 -: BANK_ADDR_W] |
        {{(BANK_ADDR_W-1){1'b0}}, 1'b1};

    wire [BANK_ADDR_W-1:0] candidate_addr [0:BANKS-1];
    genvar cg;
    generate
        for (cg=0; cg<BANKS; cg=cg+1) begin : GEN_ADDR
            assign candidate_addr[cg] = hash_base + (hash_step * cg);
        end
    endgenerate

    reg bank_commit_we;
    reg [BANK_W-1:0] bank_commit_bank;
    reg [BANK_ADDR_W-1:0] bank_commit_addr;
    reg [ENTRY_W-1:0] bank_commit_data;

    // Physical bank instances.  All banks scrub one address in parallel during
    // initialization, so a 4096-entry/8-bank table initializes in 512 cycles.
    genvar bg;
    generate
        for (bg=0; bg<BANKS; bg=bg+1) begin : GEN_BANK
            amu_bank_ram #(
                .DEPTH(BANK_DEPTH),
                .ADDR_W(BANK_ADDR_W),
                .DATA_W(ENTRY_W)
            ) u_bank (
                .clk(clk),
                .init_we(init_active),
                .init_addr(init_addr),
                .rd_en(pipe_ce && !init_active),
                .rd_addr(candidate_addr[bg]),
                .rd_data(bank_rdata[bg]),
                .wr_en(bank_commit_we && (bank_commit_bank == bg)),
                .wr_addr(bank_commit_addr),
                .wr_data(bank_commit_data)
            );
        end
    endgenerate

    wire [ENTRY_W-1:0] bank_eff [0:BANKS-1];
    genvar eg;
    generate
        for (eg=0; eg<BANKS; eg=eg+1) begin : GEN_FWD
            assign bank_eff[eg] = (fwd_valid && (fwd_bank == eg) &&
                                   (fwd_addr == m_addr[eg])) ? fwd_data : bank_rdata[eg];
        end
    endgenerate

    reg bank_match_any, bank_empty_any;
    reg [BANK_W-1:0] bank_match_idx, bank_empty_idx;
    reg [VALUE_W-1:0] bank_match_value;
    reg stash_match_any, stash_empty_any;
    reg [STASH_IDX_W-1:0] stash_match_idx, stash_empty_idx;
    reg [VALUE_W-1:0] stash_match_value;
    integer bi, si;
    always @(*) begin
        bank_match_any = 1'b0;
        bank_empty_any = 1'b0;
        bank_match_idx = {BANK_W{1'b0}};
        bank_empty_idx = {BANK_W{1'b0}};
        bank_match_value = {VALUE_W{1'b0}};
        for (bi=0; bi<BANKS; bi=bi+1) begin
            if (!bank_match_any && bank_eff[bi][ENTRY_VALID_BIT] &&
                (bank_eff[bi][ENTRY_KEY_LSB +: KEY_W] == m_key)) begin
                bank_match_any = 1'b1;
                bank_match_idx = bi[BANK_W-1:0];
                bank_match_value = bank_eff[bi][ENTRY_VALUE_LSB +: VALUE_W];
            end
            if (!bank_empty_any && !bank_eff[bi][ENTRY_VALID_BIT]) begin
                bank_empty_any = 1'b1;
                bank_empty_idx = bi[BANK_W-1:0];
            end
        end

        stash_match_any = 1'b0;
        stash_empty_any = 1'b0;
        stash_match_idx = {STASH_IDX_W{1'b0}};
        stash_empty_idx = {STASH_IDX_W{1'b0}};
        stash_match_value = {VALUE_W{1'b0}};
        for (si=0; si<STASH_SIZE; si=si+1) begin
            if (!stash_match_any && stash_valid[si] && (stash_key[si] == m_key)) begin
                stash_match_any = 1'b1;
                stash_match_idx = si[STASH_IDX_W-1:0];
                stash_match_value = stash_value[si];
            end
            if (!stash_empty_any && !stash_valid[si]) begin
                stash_empty_any = 1'b1;
                stash_empty_idx = si[STASH_IDX_W-1:0];
            end
        end
    end

    reg stash_commit_we;
    reg [STASH_IDX_W-1:0] stash_commit_idx;
    reg stash_commit_valid;
    reg [KEY_W-1:0] stash_commit_key;
    reg [VALUE_W-1:0] stash_commit_value;

    reg m_rsp_ok, m_rsp_found, m_rsp_in_stash;
    reg [2:0] m_rsp_status;
    reg [VALUE_W-1:0] m_rsp_value;
    reg [BANK_W-1:0] m_rsp_bank;

    always @(*) begin
        bank_commit_we = 1'b0;
        bank_commit_bank = {BANK_W{1'b0}};
        bank_commit_addr = {BANK_ADDR_W{1'b0}};
        bank_commit_data = {ENTRY_W{1'b0}};
        stash_commit_we = 1'b0;
        stash_commit_idx = {STASH_IDX_W{1'b0}};
        stash_commit_valid = 1'b0;
        stash_commit_key = {KEY_W{1'b0}};
        stash_commit_value = {VALUE_W{1'b0}};

        m_rsp_ok = 1'b0;
        m_rsp_found = 1'b0;
        m_rsp_status = ST_NOT_FOUND;
        m_rsp_value = {VALUE_W{1'b0}};
        m_rsp_bank = {BANK_W{1'b0}};
        m_rsp_in_stash = 1'b0;

        if (m_valid) begin
            case (m_op)
                OP_LOOKUP: begin
                    if (bank_match_any) begin
                        m_rsp_ok = 1'b1;
                        m_rsp_found = 1'b1;
                        m_rsp_status = ST_OK;
                        m_rsp_value = bank_match_value;
                        m_rsp_bank = bank_match_idx;
                    end else if (stash_match_any) begin
                        m_rsp_ok = 1'b1;
                        m_rsp_found = 1'b1;
                        m_rsp_status = ST_OK;
                        m_rsp_value = stash_match_value;
                        m_rsp_in_stash = 1'b1;
                    end
                end

                OP_INSERT: begin
                    if (bank_match_any) begin
                        m_rsp_found = 1'b1;
                        m_rsp_status = ST_EXISTS;
                        m_rsp_value = bank_match_value;
                        m_rsp_bank = bank_match_idx;
                    end else if (stash_match_any) begin
                        m_rsp_found = 1'b1;
                        m_rsp_status = ST_EXISTS;
                        m_rsp_value = stash_match_value;
                        m_rsp_in_stash = 1'b1;
                    end else if (bank_empty_any) begin
                        m_rsp_ok = 1'b1;
                        m_rsp_status = ST_OK;
                        m_rsp_bank = bank_empty_idx;
                        bank_commit_we = pipe_ce;
                        bank_commit_bank = bank_empty_idx;
                        bank_commit_addr = m_addr[bank_empty_idx];
                        bank_commit_data = {1'b1, m_key, m_value};
                    end else if (stash_empty_any) begin
                        m_rsp_ok = 1'b1;
                        m_rsp_status = ST_OK;
                        m_rsp_in_stash = 1'b1;
                        stash_commit_we = pipe_ce;
                        stash_commit_idx = stash_empty_idx;
                        stash_commit_valid = 1'b1;
                        stash_commit_key = m_key;
                        stash_commit_value = m_value;
                    end else begin
                        m_rsp_status = ST_FULL;
                    end
                end

                OP_DELETE: begin
                    if (bank_match_any) begin
                        m_rsp_ok = 1'b1;
                        m_rsp_found = 1'b1;
                        m_rsp_status = ST_OK;
                        m_rsp_value = bank_match_value;
                        m_rsp_bank = bank_match_idx;
                        bank_commit_we = pipe_ce;
                        bank_commit_bank = bank_match_idx;
                        bank_commit_addr = m_addr[bank_match_idx];
                        bank_commit_data = {ENTRY_W{1'b0}};
                    end else if (stash_match_any) begin
                        m_rsp_ok = 1'b1;
                        m_rsp_found = 1'b1;
                        m_rsp_status = ST_OK;
                        m_rsp_value = stash_match_value;
                        m_rsp_in_stash = 1'b1;
                        stash_commit_we = pipe_ce;
                        stash_commit_idx = stash_match_idx;
                        stash_commit_valid = 1'b0;
                    end
                end

                OP_UPDATE: begin
                    if (bank_match_any) begin
                        m_rsp_ok = 1'b1;
                        m_rsp_found = 1'b1;
                        m_rsp_status = ST_OK;
                        m_rsp_value = bank_match_value;
                        m_rsp_bank = bank_match_idx;
                        bank_commit_we = pipe_ce;
                        bank_commit_bank = bank_match_idx;
                        bank_commit_addr = m_addr[bank_match_idx];
                        bank_commit_data = {1'b1, m_key, m_value};
                    end else if (stash_match_any) begin
                        m_rsp_ok = 1'b1;
                        m_rsp_found = 1'b1;
                        m_rsp_status = ST_OK;
                        m_rsp_value = stash_match_value;
                        m_rsp_in_stash = 1'b1;
                        stash_commit_we = pipe_ce;
                        stash_commit_idx = stash_match_idx;
                        stash_commit_valid = 1'b1;
                        stash_commit_key = m_key;
                        stash_commit_value = m_value;
                    end
                end

                default: m_rsp_status = ST_BAD_OP;
            endcase
        end
    end

    integer sj;
    always @(posedge clk) begin
        if (!rst_n) begin
            init_active <= 1'b1;
            init_addr <= {BANK_ADDR_W{1'b0}};
            stash_valid <= {STASH_SIZE{1'b0}};
            for (sj=0; sj<STASH_SIZE; sj=sj+1) begin
                stash_key[sj] <= {KEY_W{1'b0}};
                stash_value[sj] <= {VALUE_W{1'b0}};
            end

            s0_valid <= 1'b0;
            s0_op <= OP_LOOKUP;
            s0_key <= {KEY_W{1'b0}};
            s0_value <= {VALUE_W{1'b0}};
            h_valid <= 1'b0;
            h_op <= OP_LOOKUP;
            h_key <= {KEY_W{1'b0}};
            h_value <= {VALUE_W{1'b0}};
            h_hash0 <= 32'd0;
            h_hash1 <= 32'd0;
            m_valid <= 1'b0;
            m_op <= OP_LOOKUP;
            m_key <= {KEY_W{1'b0}};
            m_value <= {VALUE_W{1'b0}};

            rsp_valid <= 1'b0;
            rsp_ok <= 1'b0;
            rsp_found <= 1'b0;
            rsp_status <= ST_OK;
            rsp_value <= {VALUE_W{1'b0}};
            rsp_bank <= {BANK_W{1'b0}};
            rsp_in_stash <= 1'b0;

            fwd_valid <= 1'b0;
            fwd_bank <= {BANK_W{1'b0}};
            fwd_addr <= {BANK_ADDR_W{1'b0}};
            fwd_data <= {ENTRY_W{1'b0}};
            for (sj=0; sj<BANKS; sj=sj+1)
                m_addr[sj] <= {BANK_ADDR_W{1'b0}};
        end else if (init_active) begin
            s0_valid <= 1'b0;
            h_valid <= 1'b0;
            m_valid <= 1'b0;
            rsp_valid <= 1'b0;
            fwd_valid <= 1'b0;
            if (init_addr == BANK_DEPTH-1) begin
                init_active <= 1'b0;
                init_addr <= {BANK_ADDR_W{1'b0}};
            end else begin
                init_addr <= init_addr + 1'b1;
            end
        end else if (pipe_ce) begin
            rsp_valid <= m_valid;
            if (m_valid) begin
                rsp_ok <= m_rsp_ok;
                rsp_found <= m_rsp_found;
                rsp_status <= m_rsp_status;
                rsp_value <= m_rsp_value;
                rsp_bank <= m_rsp_bank;
                rsp_in_stash <= m_rsp_in_stash;
            end

            if (stash_commit_we) begin
                stash_valid[stash_commit_idx] <= stash_commit_valid;
                if (stash_commit_valid) begin
                    stash_key[stash_commit_idx] <= stash_commit_key;
                    stash_value[stash_commit_idx] <= stash_commit_value;
                end
            end

            fwd_valid <= bank_commit_we;
            if (bank_commit_we) begin
                fwd_bank <= bank_commit_bank;
                fwd_addr <= bank_commit_addr;
                fwd_data <= bank_commit_data;
            end

            m_valid <= h_valid;
            m_op <= h_op;
            m_key <= h_key;
            m_value <= h_value;
            for (sj=0; sj<BANKS; sj=sj+1)
                m_addr[sj] <= candidate_addr[sj];

            // I5 fast derivative: bypass the frozen s0 stage and capture the
            // accepted request directly into the registered hash stage.
            h_valid <= req_accept;
            h_op <= req_op;
            h_key <= req_key;
            h_value <= req_value;
            if (req_accept) begin
                h_hash0 <= (req_key * HASH_C0);
                h_hash1 <= (req_key * HASH_C1);
            end else begin
                h_hash0 <= 32'd0;
                h_hash1 <= 32'd0;
            end

            // Keep the frozen s0 registers quiescent. They synthesize away in
            // this derivative and remain only to keep the source delta small.
            s0_valid <= 1'b0;
        end
    end

    initial begin
        if ((TABLE_SIZE % BANKS) != 0)
            $error("TABLE_SIZE must be divisible by BANKS");
        if ((BANK_DEPTH & (BANK_DEPTH-1)) != 0)
            $error("TABLE_SIZE/BANKS must be a power of two");
        if ((BANKS & (BANKS-1)) != 0)
            $error("BANKS must be a power of two");
    end
endmodule
