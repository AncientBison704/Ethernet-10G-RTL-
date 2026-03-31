`timescale 1 ns / 1 ps

module xgmii_rx_fcs_pipe(
    input  wire        clk,
    input  wire        resetn,
    input  wire [63:0] xgmii_rxd,
    input  wire [ 7:0] xgmii_rxc,

    output wire [63:0] m_axis_tdata,
    output wire [ 7:0] m_axis_tkeep,
    output wire        m_axis_tvalid,
    output wire        m_axis_tlast,
    output wire [ 0:0] m_axis_tuser
);

    wire [63:0] rx_tdata;
    wire [ 7:0] rx_tkeep;
    wire        rx_tvalid;
    wire        rx_tlast;
    wire [ 0:0] rx_tuser;

    xgmii_rx u_xgmii_rx (
        .clk         (clk),
        .resetn      (resetn),
        .xgmii_rxd   (xgmii_rxd),
        .xgmii_rxc   (xgmii_rxc),
        .m_axis_tdata(rx_tdata),
        .m_axis_tkeep(rx_tkeep),
        .m_axis_tvalid(rx_tvalid),
        .m_axis_tlast(rx_tlast),
        .m_axis_tuser(rx_tuser)
    );

    eth_fcs_check u_eth_fcs_check (
        .clk         (clk),
        .resetn      (resetn),
        .s_axis_tdata(rx_tdata),
        .s_axis_tkeep(rx_tkeep),
        .s_axis_tvalid(rx_tvalid),
        .s_axis_tlast(rx_tlast),
        .s_axis_tuser(rx_tuser),
        .m_axis_tdata(m_axis_tdata),
        .m_axis_tkeep(m_axis_tkeep),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tlast(m_axis_tlast),
        .m_axis_tuser(m_axis_tuser)
    );

endmodule
