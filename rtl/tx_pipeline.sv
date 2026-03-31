`timescale 1 ns / 1 ps

module tx_pipeline
    import eth_pkg::*;
(
    input  wire        clk,
    input  wire        resetn,

    input  wire [63:0] s_axis_tdata,
    input  wire [ 7:0] s_axis_tkeep,
    input  wire        s_axis_tvalid,
    input  wire        s_axis_tlast,

    output wire [63:0] xgmii_txd,
    output wire [ 7:0] xgmii_txc
);

    wire [63:0] fcs_tdata;
    wire [ 7:0] fcs_tkeep;
    wire        fcs_tvalid;
    wire        fcs_tlast;
    wire        tx_tready;

    eth_fcs_insert u_fcs_insert (
        .clk(clk), .resetn(resetn),
        .s_axis_tdata(s_axis_tdata),
        .s_axis_tkeep(s_axis_tkeep),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tlast(s_axis_tlast),
        .m_axis_tdata(fcs_tdata),
        .m_axis_tkeep(fcs_tkeep),
        .m_axis_tvalid(fcs_tvalid),
        .m_axis_tlast(fcs_tlast),
        .m_axis_tready(tx_tready)
    );

    xgmii_tx u_xgmii_tx (
        .clk(clk), .resetn(resetn),
        .s_axis_tdata(fcs_tdata),
        .s_axis_tkeep(fcs_tkeep),
        .s_axis_tvalid(fcs_tvalid),
        .s_axis_tlast(fcs_tlast),
        .s_axis_tready(tx_tready),
        .xgmii_txd(xgmii_txd),
        .xgmii_txc(xgmii_txc)
    );

endmodule
