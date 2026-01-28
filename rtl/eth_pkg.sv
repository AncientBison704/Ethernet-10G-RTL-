`ifndef ETH_PKG_SV
`define ETH_PKG_SV

package eth_pkg;

    localparam [7:0] XGMII_IDLE  = 8'h07;
    localparam [7:0] XGMII_START = 8'hFB;
    localparam [7:0] XGMII_TERM  = 8'hFD;
    localparam [7:0] XGMII_ERROR = 8'hFE;

    localparam [7:0] PREAMBLE = 8'h55;
    localparam [7:0] SFD      = 8'hD5;

    localparam MIN_FRAME_SIZE = 60;   
    localparam MAX_FRAME_SIZE = 1518; 

    localparam [31:0] CRC32_POLY = 32'h04C11DB7;

endpackage

`endif
