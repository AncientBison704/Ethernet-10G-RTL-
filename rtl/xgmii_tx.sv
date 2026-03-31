`timescale 1 ns / 1 ps

module xgmii_tx
    import eth_pkg::*;
(
    input  wire        clk,
    input  wire        resetn,

    input  wire [63:0] s_axis_tdata,
    input  wire [ 7:0] s_axis_tkeep,
    input  wire        s_axis_tvalid,
    input  wire        s_axis_tlast,
    output reg         s_axis_tready,

    output reg  [63:0] xgmii_txd,
    output reg  [ 7:0] xgmii_txc
);

    localparam S_IDLE     = 3'd0;
    localparam S_PREAMBLE = 3'd1;
    localparam S_DATA     = 3'd2;
    localparam S_TERM     = 3'd3;
    localparam S_IFG      = 3'd4;

    reg [2:0] state;

    function [3:0] count_bytes;
        input [7:0] keep;
        count_bytes = keep[0]+keep[1]+keep[2]+keep[3]
                     +keep[4]+keep[5]+keep[6]+keep[7];
    endfunction

    function [63:0] build_term_data;
        input [63:0] data;
        input [7:0]  keep;
        reg [63:0] out;
        integer i;
        reg [3:0] nb;
        begin
            out = 64'h0;
            nb = count_bytes(keep);
            for (i = 0; i < 8; i = i + 1) begin
                if (i < nb)
                    out[i*8 +: 8] = data[i*8 +: 8];
                else if (i == nb)
                    out[i*8 +: 8] = XGMII_TERM;
                else
                    out[i*8 +: 8] = XGMII_IDLE;
            end
            build_term_data = out;
        end
    endfunction

    function [7:0] build_term_ctrl;
        input [7:0] keep;
        reg [7:0] ctrl;
        integer i;
        reg [3:0] nb;
        begin
            ctrl = 8'h00;
            nb = count_bytes(keep);
            for (i = 0; i < 8; i = i + 1) begin
                if (i >= nb)
                    ctrl[i] = 1'b1;
            end
            build_term_ctrl = ctrl;
        end
    endfunction

    always @(posedge clk) begin
        if (!resetn) begin
            state         <= S_IDLE;
            s_axis_tready <= 1'b0;
            xgmii_txd     <= {8{XGMII_IDLE}};
            xgmii_txc     <= 8'hFF;
        end else begin
            case (state)
                S_IDLE: begin
                    xgmii_txd     <= {8{XGMII_IDLE}};
                    xgmii_txc     <= 8'hFF;
                    s_axis_tready <= 1'b0;

                    if (s_axis_tvalid) begin
                        state <= S_PREAMBLE;
                    end
                end

                S_PREAMBLE: begin
                    xgmii_txd <= {SFD, PREAMBLE, PREAMBLE, PREAMBLE,
                                  PREAMBLE, PREAMBLE, PREAMBLE, XGMII_START};
                    xgmii_txc     <= 8'h01;
                    s_axis_tready <= 1'b1;  
                    state         <= S_DATA;
                end

                S_DATA: begin
                    s_axis_tready <= 1'b1;

                    if (s_axis_tvalid) begin
                        if (s_axis_tlast) begin
                            s_axis_tready <= 1'b0;
                            if (s_axis_tkeep == 8'hFF) begin
                                xgmii_txd <= s_axis_tdata;
                                xgmii_txc <= 8'h00;
                                state     <= S_TERM;
                            end else begin
                                xgmii_txd <= build_term_data(s_axis_tdata, s_axis_tkeep);
                                xgmii_txc <= build_term_ctrl(s_axis_tkeep);
                                state     <= S_IFG;
                            end
                        end else begin
                            xgmii_txd <= s_axis_tdata;
                            xgmii_txc <= 8'h00;
                        end
                    end else begin
                        xgmii_txd <= {8{XGMII_IDLE}};
                        xgmii_txc <= 8'hFF;
                    end
                end

                S_TERM: begin
                    xgmii_txd <= {XGMII_IDLE, XGMII_IDLE, XGMII_IDLE, XGMII_IDLE,
                                  XGMII_IDLE, XGMII_IDLE, XGMII_IDLE, XGMII_TERM};
                    xgmii_txc     <= 8'hFF;
                    s_axis_tready <= 1'b0;
                    state         <= S_IFG;
                end

                S_IFG: begin
                    xgmii_txd     <= {8{XGMII_IDLE}};
                    xgmii_txc     <= 8'hFF;
                    s_axis_tready <= 1'b0;
                    state         <= S_IDLE;
                end

                default: begin
                    state     <= S_IDLE;
                    xgmii_txd <= {8{XGMII_IDLE}};
                    xgmii_txc <= 8'hFF;
                end
            endcase
        end
    end

endmodule
