`ifndef TAIFEX_TMP_V2187_DEFS_SVH
`define TAIFEX_TMP_V2187_DEFS_SVH

// Integration-owned constants derived from TAIFEX TCP/IP TMP Messaging
// Specifications v2.18.7 (2025-08-18). These constants describe message and
// field encodings only; they do not claim to implement TAIFEX margin/SPAN.

// Message types.
`define HFT_RMIC_TAIFEX_MSG_R02 8'd102
`define HFT_RMIC_TAIFEX_MSG_R03 8'd103
`define HFT_RMIC_TAIFEX_MSG_R32 8'd132

// R01/R02/R32 quantity is uint16.
`define HFT_RMIC_TAIFEX_QTY_WIDTH 16

// Side.
`define HFT_RMIC_TAIFEX_SIDE_BUY  8'h01
`define HFT_RMIC_TAIFEX_SIDE_SELL 8'h02

// ExecType is a char field.
`define HFT_RMIC_TAIFEX_EXEC_NEW           8'h30 // '0'
`define HFT_RMIC_TAIFEX_EXEC_CANCEL        8'h34 // '4'
`define HFT_RMIC_TAIFEX_EXEC_REDUCE        8'h35 // '5'
`define HFT_RMIC_TAIFEX_EXEC_TRADE         8'h46 // 'F'
`define HFT_RMIC_TAIFEX_EXEC_CHANGE_UPPER  8'h4d // 'M'
`define HFT_RMIC_TAIFEX_EXEC_CHANGE_LOWER  8'h6d // 'm'
`define HFT_RMIC_TAIFEX_EXEC_QUERY         8'h49 // 'I'
`define HFT_RMIC_TAIFEX_EXEC_NEW_TRADE     8'h36 // '6'

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
