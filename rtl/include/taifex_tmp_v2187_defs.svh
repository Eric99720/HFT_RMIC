`ifndef TAIFEX_TMP_V2187_DEFS_SVH
`define TAIFEX_TMP_V2187_DEFS_SVH

// Integration-owned constants derived from TAIFEX TCP/IP TMP Messaging
// Specifications v2.18.7 (2025-08-18).  These constants describe message
// encodings only; they do not claim to implement TAIFEX margin methodology.

// R01 quantity is uint16.
`define HFT_RMIC_TAIFEX_QTY_WIDTH 16

// Side.
`define HFT_RMIC_TAIFEX_SIDE_BUY  8'h01
`define HFT_RMIC_TAIFEX_SIDE_SELL 8'h02

// Order type.
`define HFT_RMIC_TAIFEX_ORD_MARKET 8'h01
`define HFT_RMIC_TAIFEX_ORD_LIMIT  8'h02
`define HFT_RMIC_TAIFEX_ORD_MWP    8'h03

// Time in force.
`define HFT_RMIC_TAIFEX_TIF_ROD 8'h00
`define HFT_RMIC_TAIFEX_TIF_IOC 8'h03
`define HFT_RMIC_TAIFEX_TIF_FOK 8'h04

// PositionEffect is a character field.
`define HFT_RMIC_TAIFEX_POS_OPEN        8'h4f  // 'O'
`define HFT_RMIC_TAIFEX_POS_CLOSE       8'h43  // 'C'
`define HFT_RMIC_TAIFEX_POS_DAYTRADE    8'h44  // 'D'
`define HFT_RMIC_TAIFEX_POS_OPEN_OFFSET 8'h41  // 'A', options only
`define HFT_RMIC_TAIFEX_POS_FCM_OFFSET  8'h37  // '7'

`endif
