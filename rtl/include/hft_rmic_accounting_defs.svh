`ifndef HFT_RMIC_ACCOUNTING_DEFS_SVH
`define HFT_RMIC_ACCOUNTING_DEFS_SVH

// Futures-accounting transaction kinds shared by the stateless transition
// primitive, state manager and integration testbenches.
`define HFT_RMIC_ACCT_EVENT_RESERVE 3'd0
`define HFT_RMIC_ACCT_EVENT_FILL    3'd1
`define HFT_RMIC_ACCT_EVENT_RELEASE 3'd2
`define HFT_RMIC_ACCT_EVENT_QUERY   3'd3

`endif
