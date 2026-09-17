`timescale 1ns/1ps
`include "hft_rmic_accounting_defs.svh"
`include "hft_rmic_policy_defs.svh"

// I2 correctness-first multi-account / multi-product futures state owner.
//
// One mutation is in flight at a time.  The state table is indexed by
// (account_id, product_id) and stored in an explicit XPM block RAM for Vivado;
// Icarus uses HFT_RMIC_BEHAVIORAL_RAM.  A reset clears only configured_bits,
// making every stale RAM word inaccessible until host/recovery configuration
// explicitly restores that entry.  This is intentional fail-closed behavior.
module hft_rmic_futures_state_manager_v1 #(
    parameter integer NUM_ACCOUNTS = 16,
    parameter integer NUM_PRODUCTS = 16,
    parameter integer ACCOUNT_ID_W = 8,
    parameter integer PRODUCT_ID_W = 8,
    parameter integer QTY_W = 32,
    parameter integer MARGIN_W = 64
) (
    input  wire clk,
    input  wire rst_n,

    // Host/recovery configuration. Configuration has priority over requests
    // while IDLE, and restores the complete mutable state for warm recovery.
    input  wire                         cfg_valid,
    output wire                         cfg_ready,
    input  wire [ACCOUNT_ID_W-1:0]      cfg_account_id,
    input  wire [PRODUCT_ID_W-1:0]      cfg_product_id,
    input  wire                         cfg_enabled,
    input  wire [MARGIN_W-1:0]          cfg_margin_budget,
    input  wire [MARGIN_W-1:0]          cfg_margin_per_contract,
    input  wire [QTY_W-1:0]             cfg_long_position,
    input  wire [QTY_W-1:0]             cfg_short_position,
    input  wire [QTY_W-1:0]             cfg_pending_open_long,
    input  wire [QTY_W-1:0]             cfg_pending_open_short,
    input  wire [QTY_W-1:0]             cfg_reserved_close_long,
    input  wire [QTY_W-1:0]             cfg_reserved_close_short,
    output reg                          cfg_done,
    output reg                          cfg_ok,
    output reg [7:0]                    cfg_reason_code,

    // Accounting transaction request.
    input  wire                         req_valid,
    output wire                         req_ready,
    input  wire [ACCOUNT_ID_W-1:0]      req_account_id,
    input  wire [PRODUCT_ID_W-1:0]      req_product_id,
    input  wire [2:0]                   req_event_kind,
    input  wire                         req_side,
    input  wire [7:0]                   req_position_effect,
    input  wire [QTY_W-1:0]             req_order_qty,
    input  wire [QTY_W-1:0]             req_fill_qty,
    input  wire [QTY_W-1:0]             req_release_qty,

    // Transaction/query response.  State fields report the committed state on
    // success and the unchanged current state on a rejected valid-key request.
    output reg                          rsp_valid,
    input  wire                         rsp_ready,
    output reg                          rsp_ok,
    output reg [1:0]                    rsp_reason_source,
    output reg [7:0]                    rsp_reason_code,
    output reg [ACCOUNT_ID_W-1:0]       rsp_account_id,
    output reg [PRODUCT_ID_W-1:0]       rsp_product_id,
    output reg                          rsp_entry_enabled,
    output reg [QTY_W-1:0]              rsp_long_position,
    output reg [QTY_W-1:0]              rsp_short_position,
    output reg [QTY_W-1:0]              rsp_pending_open_long,
    output reg [QTY_W-1:0]              rsp_pending_open_short,
    output reg [QTY_W-1:0]              rsp_reserved_close_long,
    output reg [QTY_W-1:0]              rsp_reserved_close_short,
    output reg [MARGIN_W-1:0]           rsp_required_margin_before,
    output reg [MARGIN_W-1:0]           rsp_required_margin_after
);
    localparam integer ENTRY_COUNT = NUM_ACCOUNTS * NUM_PRODUCTS;
    localparam integer ADDR_W = (ENTRY_COUNT <= 2) ? 1 : $clog2(ENTRY_COUNT);
    localparam integer REC_W = 1 + (2*MARGIN_W) + (6*QTY_W);

    localparam integer REC_ENABLED_BIT = 0;
    localparam integer REC_MARGIN_BUDGET_LSB = 1;
    localparam integer REC_MARGIN_PER_CONTRACT_LSB = REC_MARGIN_BUDGET_LSB + MARGIN_W;
    localparam integer REC_LONG_LSB = REC_MARGIN_PER_CONTRACT_LSB + MARGIN_W;
    localparam integer REC_SHORT_LSB = REC_LONG_LSB + QTY_W;
    localparam integer REC_PENDING_LONG_LSB = REC_SHORT_LSB + QTY_W;
    localparam integer REC_PENDING_SHORT_LSB = REC_PENDING_LONG_LSB + QTY_W;
    localparam integer REC_RESERVED_LONG_LSB = REC_PENDING_SHORT_LSB + QTY_W;
    localparam integer REC_RESERVED_SHORT_LSB = REC_RESERVED_LONG_LSB + QTY_W;

    localparam [0:0] ST_IDLE = 1'b0;
    localparam [0:0] ST_EVAL = 1'b1;

    reg state;
    reg [ENTRY_COUNT-1:0] configured_bits;

    function automatic [ADDR_W-1:0] make_index;
        input [ACCOUNT_ID_W-1:0] account_id;
        input [PRODUCT_ID_W-1:0] product_id;
        begin
            make_index = (account_id * NUM_PRODUCTS) + product_id;
        end
    endfunction

    wire cfg_key_valid = (cfg_account_id < NUM_ACCOUNTS) &&
                         (cfg_product_id < NUM_PRODUCTS);
    wire req_key_valid = (req_account_id < NUM_ACCOUNTS) &&
                         (req_product_id < NUM_PRODUCTS);
    wire [ADDR_W-1:0] cfg_index = make_index(cfg_account_id, cfg_product_id);
    wire [ADDR_W-1:0] req_index = make_index(req_account_id, req_product_id);

    assign cfg_ready = (state == ST_IDLE) && !rsp_valid;
    wire cfg_fire = cfg_valid && cfg_ready;

    // Configuration owns the idle cycle when presented, so request/config
    // writes can never race one another.
    assign req_ready = (state == ST_IDLE) && !rsp_valid && !cfg_valid;
    wire req_fire = req_valid && req_ready;

    reg [ACCOUNT_ID_W-1:0] req_account_latched;
    reg [PRODUCT_ID_W-1:0] req_product_latched;
    reg [ADDR_W-1:0] req_index_latched;
    reg req_key_valid_latched;
    reg [2:0] req_event_latched;
    reg req_side_latched;
    reg [7:0] req_position_effect_latched;
    reg [QTY_W-1:0] req_order_qty_latched;
    reg [QTY_W-1:0] req_fill_qty_latched;
    reg [QTY_W-1:0] req_release_qty_latched;

    wire [REC_W-1:0] ram_rd_data;
    wire ram_rd_en = req_fire && req_key_valid;
    wire [ADDR_W-1:0] ram_rd_addr = req_index;

    wire rec_enabled = ram_rd_data[REC_ENABLED_BIT];
    wire [MARGIN_W-1:0] rec_margin_budget =
        ram_rd_data[REC_MARGIN_BUDGET_LSB +: MARGIN_W];
    wire [MARGIN_W-1:0] rec_margin_per_contract =
        ram_rd_data[REC_MARGIN_PER_CONTRACT_LSB +: MARGIN_W];
    wire [QTY_W-1:0] rec_long = ram_rd_data[REC_LONG_LSB +: QTY_W];
    wire [QTY_W-1:0] rec_short = ram_rd_data[REC_SHORT_LSB +: QTY_W];
    wire [QTY_W-1:0] rec_pending_long = ram_rd_data[REC_PENDING_LONG_LSB +: QTY_W];
    wire [QTY_W-1:0] rec_pending_short = ram_rd_data[REC_PENDING_SHORT_LSB +: QTY_W];
    wire [QTY_W-1:0] rec_reserved_long = ram_rd_data[REC_RESERVED_LONG_LSB +: QTY_W];
    wire [QTY_W-1:0] rec_reserved_short = ram_rd_data[REC_RESERVED_SHORT_LSB +: QTY_W];

    wire entry_configured = req_key_valid_latched && configured_bits[req_index_latched];

    wire acct_event_ok;
    wire [7:0] acct_reason_code;
    wire [QTY_W-1:0] acct_next_long;
    wire [QTY_W-1:0] acct_next_short;
    wire [QTY_W-1:0] acct_next_pending_long;
    wire [QTY_W-1:0] acct_next_pending_short;
    wire [QTY_W-1:0] acct_next_reserved_long;
    wire [QTY_W-1:0] acct_next_reserved_short;
    wire [MARGIN_W-1:0] acct_margin_before;
    wire [MARGIN_W-1:0] acct_margin_after;
    wire acct_margin_before_overflow;
    wire acct_margin_after_overflow;

    hft_rmic_futures_accounting_v1 #(
        .QTY_W(QTY_W), .MARGIN_W(MARGIN_W)
    ) u_accounting (
        .event_kind(req_event_latched),
        .side(req_side_latched),
        .position_effect(req_position_effect_latched),
        .order_qty(req_order_qty_latched),
        .fill_qty(req_fill_qty_latched),
        .release_qty(req_release_qty_latched),
        .margin_budget(rec_margin_budget),
        .margin_per_contract(rec_margin_per_contract),
        .long_position(rec_long),
        .short_position(rec_short),
        .pending_open_long(rec_pending_long),
        .pending_open_short(rec_pending_short),
        .reserved_close_long(rec_reserved_long),
        .reserved_close_short(rec_reserved_short),
        .event_ok(acct_event_ok),
        .reason_code(acct_reason_code),
        .next_long_position(acct_next_long),
        .next_short_position(acct_next_short),
        .next_pending_open_long(acct_next_pending_long),
        .next_pending_open_short(acct_next_pending_short),
        .next_reserved_close_long(acct_next_reserved_long),
        .next_reserved_close_short(acct_next_reserved_short),
        .required_margin_before(acct_margin_before),
        .required_margin_after(acct_margin_after),
        .required_margin_before_overflow(acct_margin_before_overflow),
        .required_margin_after_overflow(acct_margin_after_overflow)
    );

    wire req_is_query = (req_event_latched == `HFT_RMIC_ACCT_EVENT_QUERY);
    wire req_is_mutation = (req_event_latched == `HFT_RMIC_ACCT_EVENT_RESERVE) ||
                           (req_event_latched == `HFT_RMIC_ACCT_EVENT_FILL) ||
                           (req_event_latched == `HFT_RMIC_ACCT_EVENT_RELEASE);

    reg eval_ok;
    reg [7:0] eval_reason;
    reg [QTY_W-1:0] eval_long;
    reg [QTY_W-1:0] eval_short;
    reg [QTY_W-1:0] eval_pending_long;
    reg [QTY_W-1:0] eval_pending_short;
    reg [QTY_W-1:0] eval_reserved_long;
    reg [QTY_W-1:0] eval_reserved_short;
    reg [MARGIN_W-1:0] eval_margin_after;

    always @(*) begin
        eval_ok = 1'b0;
        eval_reason = `HFT_RMIC_POLICY_REASON_ACCOUNTING_STATE;
        eval_long = {QTY_W{1'b0}};
        eval_short = {QTY_W{1'b0}};
        eval_pending_long = {QTY_W{1'b0}};
        eval_pending_short = {QTY_W{1'b0}};
        eval_reserved_long = {QTY_W{1'b0}};
        eval_reserved_short = {QTY_W{1'b0}};
        eval_margin_after = {MARGIN_W{1'b0}};

        if (!req_key_valid_latched) begin
            eval_reason = `HFT_RMIC_POLICY_REASON_STATE_KEY_INVALID;
        end else if (!entry_configured) begin
            eval_reason = `HFT_RMIC_POLICY_REASON_STATE_UNCONFIGURED;
        end else begin
            // Once configured, always report the unchanged current state on a
            // rejected request so software/testbenches can verify atomicity.
            eval_long = rec_long;
            eval_short = rec_short;
            eval_pending_long = rec_pending_long;
            eval_pending_short = rec_pending_short;
            eval_reserved_long = rec_reserved_long;
            eval_reserved_short = rec_reserved_short;
            eval_margin_after = acct_margin_before;

            if (!rec_enabled) begin
                eval_reason = `HFT_RMIC_POLICY_REASON_STATE_DISABLED;
            end else if (req_is_query) begin
                eval_ok = 1'b1;
                eval_reason = `HFT_RMIC_POLICY_REASON_PASS;
            end else if (!req_is_mutation) begin
                eval_reason = `HFT_RMIC_POLICY_REASON_ACCOUNTING_STATE;
            end else if (!acct_event_ok) begin
                eval_reason = acct_reason_code;
            end else if (acct_margin_after_overflow) begin
                eval_reason = `HFT_RMIC_POLICY_REASON_POSITION_OVERFLOW;
            end else begin
                eval_ok = 1'b1;
                eval_reason = `HFT_RMIC_POLICY_REASON_PASS;
                eval_long = acct_next_long;
                eval_short = acct_next_short;
                eval_pending_long = acct_next_pending_long;
                eval_pending_short = acct_next_pending_short;
                eval_reserved_long = acct_next_reserved_long;
                eval_reserved_short = acct_next_reserved_short;
                eval_margin_after = acct_margin_after;
            end
        end
    end

    wire [REC_W-1:0] cfg_record = {
        cfg_reserved_close_short,
        cfg_reserved_close_long,
        cfg_pending_open_short,
        cfg_pending_open_long,
        cfg_short_position,
        cfg_long_position,
        cfg_margin_per_contract,
        cfg_margin_budget,
        cfg_enabled
    };

    wire [REC_W-1:0] commit_record = {
        eval_reserved_short,
        eval_reserved_long,
        eval_pending_short,
        eval_pending_long,
        eval_short,
        eval_long,
        rec_margin_per_contract,
        rec_margin_budget,
        rec_enabled
    };

    wire txn_commit = (state == ST_EVAL) && entry_configured && rec_enabled &&
                      req_is_mutation && eval_ok;
    wire cfg_write = cfg_fire && cfg_key_valid;
    wire ram_wr_en = cfg_write || txn_commit;
    wire [ADDR_W-1:0] ram_wr_addr = cfg_write ? cfg_index : req_index_latched;
    wire [REC_W-1:0] ram_wr_data = cfg_write ? cfg_record : commit_record;

    hft_rmic_state_ram #(
        .DEPTH(ENTRY_COUNT), .ADDR_W(ADDR_W), .DATA_W(REC_W)
    ) u_state_ram (
        .clk(clk),
        .rd_en(ram_rd_en), .rd_addr(ram_rd_addr), .rd_data(ram_rd_data),
        .wr_en(ram_wr_en), .wr_addr(ram_wr_addr), .wr_data(ram_wr_data)
    );

    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE;
            configured_bits <= {ENTRY_COUNT{1'b0}};

            cfg_done <= 1'b0;
            cfg_ok <= 1'b0;
            cfg_reason_code <= `HFT_RMIC_POLICY_REASON_PASS;

            req_account_latched <= {ACCOUNT_ID_W{1'b0}};
            req_product_latched <= {PRODUCT_ID_W{1'b0}};
            req_index_latched <= {ADDR_W{1'b0}};
            req_key_valid_latched <= 1'b0;
            req_event_latched <= `HFT_RMIC_ACCT_EVENT_QUERY;
            req_side_latched <= 1'b0;
            req_position_effect_latched <= 8'd0;
            req_order_qty_latched <= {QTY_W{1'b0}};
            req_fill_qty_latched <= {QTY_W{1'b0}};
            req_release_qty_latched <= {QTY_W{1'b0}};

            rsp_valid <= 1'b0;
            rsp_ok <= 1'b0;
            rsp_reason_source <= `HFT_RMIC_REASON_SRC_POLICY;
            rsp_reason_code <= `HFT_RMIC_POLICY_REASON_PASS;
            rsp_account_id <= {ACCOUNT_ID_W{1'b0}};
            rsp_product_id <= {PRODUCT_ID_W{1'b0}};
            rsp_entry_enabled <= 1'b0;
            rsp_long_position <= {QTY_W{1'b0}};
            rsp_short_position <= {QTY_W{1'b0}};
            rsp_pending_open_long <= {QTY_W{1'b0}};
            rsp_pending_open_short <= {QTY_W{1'b0}};
            rsp_reserved_close_long <= {QTY_W{1'b0}};
            rsp_reserved_close_short <= {QTY_W{1'b0}};
            rsp_required_margin_before <= {MARGIN_W{1'b0}};
            rsp_required_margin_after <= {MARGIN_W{1'b0}};
        end else begin
            cfg_done <= 1'b0;

            if (rsp_valid && rsp_ready)
                rsp_valid <= 1'b0;

            if (cfg_fire) begin
                cfg_done <= 1'b1;
                cfg_ok <= cfg_key_valid;
                cfg_reason_code <= cfg_key_valid ?
                    `HFT_RMIC_POLICY_REASON_PASS :
                    `HFT_RMIC_POLICY_REASON_STATE_KEY_INVALID;
                if (cfg_key_valid)
                    configured_bits[cfg_index] <= 1'b1;
            end

            case (state)
                ST_IDLE: begin
                    if (req_fire) begin
                        req_account_latched <= req_account_id;
                        req_product_latched <= req_product_id;
                        req_index_latched <= req_index;
                        req_key_valid_latched <= req_key_valid;
                        req_event_latched <= req_event_kind;
                        req_side_latched <= req_side;
                        req_position_effect_latched <= req_position_effect;
                        req_order_qty_latched <= req_order_qty;
                        req_fill_qty_latched <= req_fill_qty;
                        req_release_qty_latched <= req_release_qty;
                        state <= ST_EVAL;
                    end
                end

                ST_EVAL: begin
                    rsp_valid <= 1'b1;
                    rsp_ok <= eval_ok;
                    rsp_reason_source <= `HFT_RMIC_REASON_SRC_POLICY;
                    rsp_reason_code <= eval_reason;
                    rsp_account_id <= req_account_latched;
                    rsp_product_id <= req_product_latched;
                    rsp_entry_enabled <= req_key_valid_latched && entry_configured ? rec_enabled : 1'b0;
                    rsp_long_position <= eval_long;
                    rsp_short_position <= eval_short;
                    rsp_pending_open_long <= eval_pending_long;
                    rsp_pending_open_short <= eval_pending_short;
                    rsp_reserved_close_long <= eval_reserved_long;
                    rsp_reserved_close_short <= eval_reserved_short;
                    rsp_required_margin_before <=
                        (req_key_valid_latched && entry_configured) ? acct_margin_before : {MARGIN_W{1'b0}};
                    rsp_required_margin_after <= eval_margin_after;
                    state <= ST_IDLE;
                end
            endcase
        end
    end

    initial begin
        if (NUM_ACCOUNTS < 1 || NUM_PRODUCTS < 1)
            $error("NUM_ACCOUNTS and NUM_PRODUCTS must be >= 1");
        if (ENTRY_COUNT > (1 << ADDR_W))
            $error("state-manager address width is insufficient");
    end
endmodule
