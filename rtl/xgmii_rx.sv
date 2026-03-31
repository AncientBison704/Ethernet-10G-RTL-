`timescale 1 ns / 1 ps

module xgmii_rx
    import eth_pkg::*;
(
    input  wire        clk,
    input  wire        resetn,

    input  wire [63:0] xgmii_rxd,
    input  wire [ 7:0] xgmii_rxc,

    output reg  [63:0] m_axis_tdata,
    output reg  [ 7:0] m_axis_tkeep,
    output reg         m_axis_tvalid,
    output reg         m_axis_tlast,
    output reg  [ 0:0] m_axis_tuser
);

    localparam S_IDLE = 2'd0;
    localparam S_DATA = 2'd1;
    localparam S_LAST = 2'd2;

    reg [1:0] state;
    reg       frame_error;

    wire [7:0] lane [0:7];
    wire       ctrl [0:7];
    genvar gi;
    generate
        for (gi = 0; gi < 8; gi = gi + 1) begin : gen_lanes
            assign lane[gi] = xgmii_rxd[gi*8 +: 8];
            assign ctrl[gi] = xgmii_rxc[gi];
        end
    endgenerate

    wire start_detect = ctrl[0] && (lane[0] == XGMII_START);

    reg [3:0] term_lane;
    reg       term_found;
    always @(*) begin
        term_lane = 4'd8;
        term_found = 1'b0;
        if      (ctrl[0] && lane[0] == XGMII_TERM) begin term_lane = 4'd0; term_found = 1'b1; end
        else if (ctrl[1] && lane[1] == XGMII_TERM) begin term_lane = 4'd1; term_found = 1'b1; end
        else if (ctrl[2] && lane[2] == XGMII_TERM) begin term_lane = 4'd2; term_found = 1'b1; end
        else if (ctrl[3] && lane[3] == XGMII_TERM) begin term_lane = 4'd3; term_found = 1'b1; end
        else if (ctrl[4] && lane[4] == XGMII_TERM) begin term_lane = 4'd4; term_found = 1'b1; end
        else if (ctrl[5] && lane[5] == XGMII_TERM) begin term_lane = 4'd5; term_found = 1'b1; end
        else if (ctrl[6] && lane[6] == XGMII_TERM) begin term_lane = 4'd6; term_found = 1'b1; end
        else if (ctrl[7] && lane[7] == XGMII_TERM) begin term_lane = 4'd7; term_found = 1'b1; end
    end

    function [7:0] make_tkeep;
        input [3:0] tl;
        begin
            case (tl)
                4'd0: make_tkeep = 8'h00;
                4'd1: make_tkeep = 8'h01;
                4'd2: make_tkeep = 8'h03;
                4'd3: make_tkeep = 8'h07;
                4'd4: make_tkeep = 8'h0F;
                4'd5: make_tkeep = 8'h1F;
                4'd6: make_tkeep = 8'h3F;
                4'd7: make_tkeep = 8'h7F;
                default: make_tkeep = 8'hFF;
            endcase
        end
    endfunction

    reg [63:0] pipe_data;
    reg        pipe_valid;

    reg [63:0] last_data;
    reg [ 7:0] last_tkeep;
    reg        last_has_data;  

    always @(posedge clk) begin
        if (!resetn) begin
            state         <= S_IDLE;
            m_axis_tdata  <= 0;
            m_axis_tkeep  <= 0;
            m_axis_tvalid <= 0;
            m_axis_tlast  <= 0;
            m_axis_tuser  <= 0;
            frame_error   <= 0;
            pipe_data     <= 0;
            pipe_valid    <= 0;
            last_data     <= 0;
            last_tkeep    <= 0;
            last_has_data <= 0;
        end else begin
            m_axis_tvalid <= 0;
            m_axis_tlast  <= 0;
            m_axis_tuser  <= 0;

            case (state)
                S_IDLE: begin
                    pipe_valid  <= 0;
                    frame_error <= 0;
                    if (start_detect) begin
                        if (!(lane[1] == PREAMBLE && lane[2] == PREAMBLE &&
                              lane[3] == PREAMBLE && lane[4] == PREAMBLE &&
                              lane[5] == PREAMBLE && lane[6] == PREAMBLE &&
                              lane[7] == SFD))
                            frame_error <= 1;
                        state <= S_DATA;
                    end
                end

                S_DATA: begin
                    if (term_found) begin
                        if (term_lane == 4'd0) begin
                            if (pipe_valid) begin
                                m_axis_tdata  <= pipe_data;
                                m_axis_tkeep  <= 8'hFF;
                                m_axis_tvalid <= 1'b1;
                                m_axis_tlast  <= 1'b1;
                                m_axis_tuser  <= frame_error;
                            end
                            pipe_valid <= 0;
                            state <= S_IDLE;
                        end else begin
                            if (pipe_valid) begin
                                m_axis_tdata  <= pipe_data;
                                m_axis_tkeep  <= 8'hFF;
                                m_axis_tvalid <= 1'b1;
                            end
                            last_data     <= xgmii_rxd;
                            last_tkeep    <= make_tkeep(term_lane);
                            last_has_data <= 1'b1;
                            pipe_valid    <= 0;
                            state         <= S_LAST;
                        end
                    end else begin
                        if (pipe_valid) begin
                            m_axis_tdata  <= pipe_data;
                            m_axis_tkeep  <= 8'hFF;
                            m_axis_tvalid <= 1'b1;
                        end
                        pipe_data  <= xgmii_rxd;
                        pipe_valid <= 1'b1;
                    end
                end

                S_LAST: begin
                    if (last_has_data) begin
                        m_axis_tdata  <= last_data;
                        m_axis_tkeep  <= last_tkeep;
                        m_axis_tvalid <= 1'b1;
                        m_axis_tlast  <= 1'b1;
                        m_axis_tuser  <= frame_error;
                    end
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
