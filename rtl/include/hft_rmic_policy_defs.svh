`ifndef HFT_RMIC_POLICY_DEFS_SVH
`define HFT_RMIC_POLICY_DEFS_SVH

// Integration-wide reject namespace. Frozen RMIC M5.4 keeps its original
// 4-bit reason field unchanged; this namespace provides room for adapter,
// policy and system/integration failures without modifying the measured core.

`define HFT_RMIC_REASON_SRC_RMIC     2'd0
`define HFT_RMIC_REASON_SRC_ADAPTER  2'd1
`define HFT_RMIC_REASON_SRC_POLICY   2'd2
`define HFT_RMIC_REASON_SRC_SYSTEM   2'd3

// Adapter reason codes.
`define HFT_RMIC_ADAPTER_REASON_PASS              8'd0
`define HFT_RMIC_ADAPTER_REASON_SIDE_INVALID      8'd1
`define HFT_RMIC_ADAPTER_REASON_ACCOUNT_UNMAPPED  8'd2
`define HFT_RMIC_ADAPTER_REASON_ACCOUNT_AMBIGUOUS 8'd3
`define HFT_RMIC_ADAPTER_REASON_PRODUCT_UNMAPPED  8'd4
`define HFT_RMIC_ADAPTER_REASON_PRODUCT_AMBIGUOUS 8'd5
`define HFT_RMIC_ADAPTER_REASON_QTY_WIDTH         8'd6

// Policy reason codes. Only generic/configuration-independent categories are
// frozen here. Exchange-specific codes are added only after the corresponding
// policy is supported and verified against an authoritative specification.
`define HFT_RMIC_POLICY_REASON_PASS                     8'd0
`define HFT_RMIC_POLICY_REASON_KILL_SWITCH              8'd1
`define HFT_RMIC_POLICY_REASON_ORDER_TYPE_UNSUPPORTED   8'd2
`define HFT_RMIC_POLICY_REASON_TIF_UNSUPPORTED          8'd3
`define HFT_RMIC_POLICY_REASON_POSITION_EFFECT          8'd4
`define HFT_RMIC_POLICY_REASON_ORDER_RATE               8'd5
`define HFT_RMIC_POLICY_REASON_CANCEL_RATE              8'd6
`define HFT_RMIC_POLICY_REASON_OUTSTANDING_LIMIT        8'd7
`define HFT_RMIC_POLICY_REASON_EXPOSURE_LIMIT           8'd8
`define HFT_RMIC_POLICY_REASON_ACCOUNTING_UNREADY       8'd9

// Futures-accounting v1 reasons. The v1 model is an integration risk budget
// model based on host-configured margin-per-contract; it is not TAIFEX SPAN.
`define HFT_RMIC_POLICY_REASON_MARGIN_LIMIT              8'd10
`define HFT_RMIC_POLICY_REASON_CLOSE_LONG_INSUFFICIENT   8'd11
`define HFT_RMIC_POLICY_REASON_CLOSE_SHORT_INSUFFICIENT  8'd12
`define HFT_RMIC_POLICY_REASON_ACCOUNTING_STATE          8'd13
`define HFT_RMIC_POLICY_REASON_POSITION_OVERFLOW         8'd14
`define HFT_RMIC_POLICY_REASON_STATE_KEY_INVALID         8'd15
`define HFT_RMIC_POLICY_REASON_STATE_UNCONFIGURED        8'd16
`define HFT_RMIC_POLICY_REASON_STATE_DISABLED            8'd17

// System/integration reason codes.
`define HFT_RMIC_SYSTEM_REASON_PASS                    8'd0
`define HFT_RMIC_SYSTEM_REASON_NOT_READY               8'd1
`define HFT_RMIC_SYSTEM_REASON_RECOVERY_REQUIRED       8'd2
`define HFT_RMIC_SYSTEM_REASON_DOWNSTREAM_BACKPRESSURE 8'd3
`define HFT_RMIC_SYSTEM_REASON_INTERNAL_OVERFLOW       8'd4

`endif
