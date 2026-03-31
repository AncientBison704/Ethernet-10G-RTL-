`timescale 1 ns / 1 ps

module eth_fcs_insert #(
    parameter FIFO_DEPTH = 256
) (
    input  wire        clk,
    input  wire        resetn,

    input  wire [63:0] s_axis_tdata,
    input  wire [ 7:0] s_axis_tkeep,
    input  wire        s_axis_tvalid,
    input  wire        s_axis_tlast,

    output reg  [63:0] m_axis_tdata,
    output reg  [ 7:0] m_axis_tkeep,
    output reg         m_axis_tvalid,
    output reg         m_axis_tlast,
    input  wire        m_axis_tready
);

    `include "crc32_parallel.svh"

    localparam [31:0] CRC_INIT = 32'hFFFF_FFFF;

    reg [63:0] fifo_data [0:FIFO_DEPTH-1];
    reg [ 7:0] fifo_keep [0:FIFO_DEPTH-1];
    reg        fifo_last [0:FIFO_DEPTH-1];
    reg [7:0]  fifo_wr_ptr;
    reg [7:0]  fifo_rd_ptr;

    reg [31:0] crc_state;
    wire [31:0] crc_next = crc32_64b(crc_state, s_axis_tdata, s_axis_tkeep);

    localparam S_STORE  = 2'd0;
    localparam S_REPLAY = 2'd1;
    localparam S_FCS    = 2'd2;

    reg [1:0] state;
    reg [31:0] final_crc;
    reg [3:0]  last_beat_bytes;

    function [3:0] popcount8;
        input [7:0] k;
        popcount8 = k[0]+k[1]+k[2]+k[3]+k[4]+k[5]+k[6]+k[7];
    endfunction

    reg out_pending;  

    always @(posedge clk) begin
        if (!resetn) begin
            state          <= S_STORE;
            fifo_wr_ptr    <= 0;
            fifo_rd_ptr    <= 0;
            crc_state      <= CRC_INIT;
            final_crc      <= 0;
            m_axis_tdata   <= 0;
            m_axis_tkeep   <= 0;
            m_axis_tvalid  <= 0;
            m_axis_tlast   <= 0;
            last_beat_bytes <= 0;
            out_pending    <= 0;
        end else begin

            if (m_axis_tvalid && m_axis_tready) begin
                m_axis_tvalid <= 0;
                m_axis_tlast  <= 0;
                out_pending   <= 0;
            end

            case (state)
                S_STORE: begin
                    if (s_axis_tvalid) begin
                        fifo_data[fifo_wr_ptr] <= s_axis_tdata;
                        fifo_keep[fifo_wr_ptr] <= s_axis_tkeep;
                        fifo_last[fifo_wr_ptr] <= s_axis_tlast;
                        fifo_wr_ptr <= fifo_wr_ptr + 1;
                        crc_state   <= crc_next;

                        if (s_axis_tlast) begin
                            final_crc       <= ~crc_next;
                            last_beat_bytes <= popcount8(s_axis_tkeep);
                            state           <= S_REPLAY;
                        end
                    end
                end

                S_REPLAY: begin
                    if (!out_pending && !m_axis_tvalid) begin
                        if (fifo_rd_ptr < fifo_wr_ptr) begin
                            if (fifo_last[fifo_rd_ptr]) begin
                                if (last_beat_bytes <= 4) begin
                                    m_axis_tdata <= fifo_data[fifo_rd_ptr];
                                    m_axis_tkeep <= fifo_keep[fifo_rd_ptr];
                                    begin : fcs_fill
                                        integer fi;
                                        reg [3:0] fcs_idx;
                                        fcs_idx = 0;
                                        for (fi = 0; fi < 8; fi = fi + 1) begin
                                            if (!fifo_keep[fifo_rd_ptr][fi] && fcs_idx < 4) begin
                                                m_axis_tdata[fi*8 +: 8] <= final_crc[fcs_idx*8 +: 8];
                                                m_axis_tkeep[fi] <= 1'b1;
                                                fcs_idx = fcs_idx + 1;
                                            end
                                        end
                                    end
                                    m_axis_tvalid <= 1;
                                    m_axis_tlast  <= 1;
                                    out_pending   <= 1;
                                    fifo_rd_ptr <= 0;
                                    fifo_wr_ptr <= 0;
                                    crc_state   <= CRC_INIT;
                                    state       <= S_STORE;
                                end else begin
                                    m_axis_tdata  <= fifo_data[fifo_rd_ptr];
                                    m_axis_tkeep  <= 8'hFF;  
                                    m_axis_tvalid <= 1;
                                    out_pending   <= 1;
                                    fifo_rd_ptr   <= fifo_rd_ptr + 1;

                                    begin : fcs_merge
                                        integer mi;
                                        reg [3:0] fcs_idx;
                                        fcs_idx = 0;
                                        for (mi = 0; mi < 8; mi = mi + 1) begin
                                            if (!fifo_keep[fifo_rd_ptr][mi] && fcs_idx < 4) begin
                                                m_axis_tdata[mi*8 +: 8] <= final_crc[fcs_idx*8 +: 8];
                                                fcs_idx = fcs_idx + 1;
                                            end
                                        end
                                        
                                        if (fcs_idx >= 4) begin
                                            m_axis_tlast <= 1;
                                            fifo_rd_ptr  <= 0;
                                            fifo_wr_ptr  <= 0;
                                            crc_state    <= CRC_INIT;
                                            state        <= S_STORE;
                                        end else begin
                                            m_axis_tlast <= 0;
                                            state        <= S_FCS;
                                        end
                                    end
                                end
                            end else begin
                                // Normal beat — emit
                                m_axis_tdata  <= fifo_data[fifo_rd_ptr];
                                m_axis_tkeep  <= fifo_keep[fifo_rd_ptr];
                                m_axis_tvalid <= 1;
                                m_axis_tlast  <= 0;
                                out_pending   <= 1;
                                fifo_rd_ptr   <= fifo_rd_ptr + 1;
                            end
                        end
                    end
                end

                S_FCS: begin
                    if (!out_pending && !m_axis_tvalid) begin
                        begin : fcs_overflow
                            reg [3:0] remaining;
                            reg [3:0] start_idx;
                            integer oi;
                            remaining = last_beat_bytes - 4;  
                            start_idx = 4 - remaining;        
                            m_axis_tdata <= 0;
                            m_axis_tkeep <= 0;
                            for (oi = 0; oi < 8; oi = oi + 1) begin
                                if (oi < remaining) begin
                                    m_axis_tdata[oi*8 +: 8] <= final_crc[(start_idx + oi)*8 +: 8];
                                    m_axis_tkeep[oi] <= 1'b1;
                                end
                            end
                        end
                        m_axis_tvalid <= 1;
                        m_axis_tlast  <= 1;
                        out_pending   <= 1;
                        fifo_rd_ptr   <= 0;
                        fifo_wr_ptr   <= 0;
                        crc_state     <= CRC_INIT;
                        state         <= S_STORE;
                    end
                end

                default: state <= S_STORE;
            endcase
        end
    end

endmodule
