`timescale 1 ns / 1 ps

module eth_fcs_check(
    input  wire        clk,
    input  wire        resetn,

    input  wire [63:0] s_axis_tdata,
    input  wire [ 7:0] s_axis_tkeep,
    input  wire        s_axis_tvalid,
    input  wire        s_axis_tlast,
    input  wire [ 0:0] s_axis_tuser,

    output reg  [63:0] m_axis_tdata,
    output reg  [ 7:0] m_axis_tkeep,
    output reg         m_axis_tvalid,
    output reg         m_axis_tlast,
    output reg  [ 0:0] m_axis_tuser
);

    localparam [31:0] CRC_INIT    = 32'hFFFF_FFFF;
    localparam [31:0] CRC_RESIDUE = 32'hDEBB20E3;

    `include "crc32_parallel.svh"

    reg [31:0] crc_state;
    wire [31:0] crc_next = crc32_64b(crc_state, s_axis_tdata, s_axis_tkeep);
    wire        fcs_bad  = (crc_next != CRC_RESIDUE);

    always @(posedge clk) begin
        if (!resetn) begin
            crc_state     <= CRC_INIT;
            m_axis_tdata  <= 64'd0;
            m_axis_tkeep  <= 8'd0;
            m_axis_tvalid <= 1'b0;
            m_axis_tlast  <= 1'b0;
            m_axis_tuser  <= 1'b0;
        end else begin
            m_axis_tvalid <= 1'b0;
            m_axis_tlast  <= 1'b0;
            m_axis_tuser  <= 1'b0;

            if (s_axis_tvalid) begin
                m_axis_tdata  <= s_axis_tdata;
                m_axis_tkeep  <= s_axis_tkeep;
                m_axis_tvalid <= 1'b1;
                m_axis_tlast  <= s_axis_tlast;

                if (s_axis_tlast) begin
                    m_axis_tuser <= s_axis_tuser | fcs_bad;
                    crc_state    <= CRC_INIT;
                end else begin
                    crc_state    <= crc_next;
                end
            end
        end
    end

endmodule
