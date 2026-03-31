`timescale 1 ns / 1 ps

module pkt_filter #(
    parameter NUM_RULES = 4,
    parameter FIFO_DEPTH = 64  
) (
    input  wire        clk,
    input  wire        resetn,

    input  wire [63:0] s_axis_tdata,
    input  wire [ 7:0] s_axis_tkeep,
    input  wire        s_axis_tvalid,
    input  wire        s_axis_tlast,
    input  wire [ 0:0] s_axis_tuser,

    input  wire        meta_valid,
    input  wire [31:0] meta_ip_src,
    input  wire [31:0] meta_ip_dst,
    input  wire [15:0] meta_udp_dst_port,
    input  wire        meta_is_ipv4,
    input  wire        meta_is_udp,

    output reg  [63:0] m_axis_tdata,
    output reg  [ 7:0] m_axis_tkeep,
    output reg         m_axis_tvalid,
    output reg         m_axis_tlast,
    output reg  [ 0:0] m_axis_tuser,

    input  wire [NUM_RULES-1:0]   cfg_rule_en,
    input  wire [32*NUM_RULES-1:0] cfg_ip_src,       
    input  wire [32*NUM_RULES-1:0] cfg_ip_src_mask,   
    input  wire [32*NUM_RULES-1:0] cfg_ip_dst,
    input  wire [32*NUM_RULES-1:0] cfg_ip_dst_mask,
    input  wire [16*NUM_RULES-1:0] cfg_udp_dst_port,
    input  wire [NUM_RULES-1:0]    cfg_udp_port_en,   

    output reg  [31:0] stat_frames_in,
    output reg  [31:0] stat_frames_passed,
    output reg  [31:0] stat_frames_dropped
);


    reg [63:0] fifo_data  [0:FIFO_DEPTH-1];
    reg [ 7:0] fifo_keep  [0:FIFO_DEPTH-1];
    reg        fifo_last  [0:FIFO_DEPTH-1];
    reg [ 0:0] fifo_user  [0:FIFO_DEPTH-1];
    reg [6:0]  fifo_wr_ptr;
    reg [6:0]  fifo_rd_ptr;
    reg [6:0]  fifo_count;

    localparam S_STORE    = 2'd0;  
    localparam S_DECIDE   = 2'd1;  
    localparam S_FORWARD  = 2'd2;  
    localparam S_DROP     = 2'd3;  
    reg [1:0] state;
    reg       frame_pass;

    
    reg any_rule_enabled;
    reg any_rule_matched;

    always @(*) begin : match_logic
        integer r;
        any_rule_enabled = 0;
        any_rule_matched = 0;

        for (r = 0; r < NUM_RULES; r = r + 1) begin
            if (cfg_rule_en[r]) begin
                any_rule_enabled = 1;

                begin : rule_check
                    reg ip_src_match, ip_dst_match, port_match;

                    ip_src_match = ((meta_ip_src & cfg_ip_src_mask[r*32 +: 32]) ==
                                    (cfg_ip_src[r*32 +: 32] & cfg_ip_src_mask[r*32 +: 32]));

                    ip_dst_match = ((meta_ip_dst & cfg_ip_dst_mask[r*32 +: 32]) ==
                                    (cfg_ip_dst[r*32 +: 32] & cfg_ip_dst_mask[r*32 +: 32]));

                    port_match = !cfg_udp_port_en[r] ||
                                 (meta_is_udp && meta_udp_dst_port == cfg_udp_dst_port[r*16 +: 16]);

                    if (meta_is_ipv4 && ip_src_match && ip_dst_match && port_match)
                        any_rule_matched = 1;
                end
            end
        end
    end

    
    always @(posedge clk) begin
        if (!resetn) begin
            state              <= S_STORE;
            fifo_wr_ptr        <= 0;
            fifo_rd_ptr        <= 0;
            fifo_count         <= 0;
            m_axis_tdata       <= 0;
            m_axis_tkeep       <= 0;
            m_axis_tvalid      <= 0;
            m_axis_tlast       <= 0;
            m_axis_tuser       <= 0;
            frame_pass         <= 0;
            stat_frames_in     <= 0;
            stat_frames_passed <= 0;
            stat_frames_dropped <= 0;
        end else begin
            m_axis_tvalid <= 0;
            m_axis_tlast  <= 0;

            case (state)
                S_STORE: begin
                    if (s_axis_tvalid) begin
                        fifo_data[fifo_wr_ptr] <= s_axis_tdata;
                        fifo_keep[fifo_wr_ptr] <= s_axis_tkeep;
                        fifo_last[fifo_wr_ptr] <= s_axis_tlast;
                        fifo_user[fifo_wr_ptr] <= s_axis_tuser;
                        fifo_wr_ptr <= fifo_wr_ptr + 1;
                        fifo_count  <= fifo_count + 1;

                        if (s_axis_tlast) begin
                            stat_frames_in <= stat_frames_in + 1;
                            state <= S_DECIDE;
                        end
                    end
                end

                S_DECIDE: begin
                    if (!any_rule_enabled || any_rule_matched) begin
                        frame_pass <= 1;
                        state <= S_FORWARD;
                    end else begin
                        frame_pass <= 0;
                        state <= S_DROP;
                    end
                end

                S_FORWARD: begin
                    if (fifo_rd_ptr < fifo_wr_ptr) begin
                        m_axis_tdata  <= fifo_data[fifo_rd_ptr];
                        m_axis_tkeep  <= fifo_keep[fifo_rd_ptr];
                        m_axis_tvalid <= 1;
                        m_axis_tlast  <= fifo_last[fifo_rd_ptr];
                        m_axis_tuser  <= fifo_user[fifo_rd_ptr];
                        fifo_rd_ptr   <= fifo_rd_ptr + 1;

                        if (fifo_last[fifo_rd_ptr]) begin
                            stat_frames_passed <= stat_frames_passed + 1;
                            state       <= S_STORE;
                            fifo_wr_ptr <= 0;
                            fifo_rd_ptr <= 0;
                            fifo_count  <= 0;
                        end
                    end
                end

                S_DROP: begin
                    stat_frames_dropped <= stat_frames_dropped + 1;
                    fifo_wr_ptr <= 0;
                    fifo_rd_ptr <= 0;
                    fifo_count  <= 0;
                    state       <= S_STORE;
                end

                default: state <= S_STORE;
            endcase
        end
    end

endmodule
