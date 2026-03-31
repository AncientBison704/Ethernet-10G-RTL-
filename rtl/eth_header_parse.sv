`timescale 1 ns / 1 ps

module eth_header_parse (
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
    output reg  [ 0:0] m_axis_tuser,

    output reg         meta_valid,
    output reg  [47:0] meta_dst_mac,
    output reg  [47:0] meta_src_mac,
    output reg  [15:0] meta_ethertype,
    output reg  [31:0] meta_ip_src,
    output reg  [31:0] meta_ip_dst,
    output reg  [ 7:0] meta_ip_proto,
    output reg  [15:0] meta_udp_src_port,
    output reg  [15:0] meta_udp_dst_port,
    output reg         meta_is_ipv4,
    output reg         meta_is_udp
);

    reg [3:0] beat_cnt;

    reg [47:0] r_dst_mac;
    reg [47:0] r_src_mac;
    reg [15:0] r_ethertype;
    reg [ 7:0] r_ip_proto;
    reg [31:0] r_ip_src;
    reg [31:0] r_ip_dst;
    reg [15:0] r_udp_src_port;
    reg [15:0] r_udp_dst_port;
    reg        r_is_ipv4;
    reg        r_is_udp;


    always @(posedge clk) begin
        if (!resetn) begin
            m_axis_tdata  <= 0;
            m_axis_tkeep  <= 0;
            m_axis_tvalid <= 0;
            m_axis_tlast  <= 0;
            m_axis_tuser  <= 0;
            meta_valid    <= 0;
            beat_cnt      <= 0;
            r_dst_mac     <= 0;
            r_src_mac     <= 0;
            r_ethertype   <= 0;
            r_ip_proto    <= 0;
            r_ip_src      <= 0;
            r_ip_dst      <= 0;
            r_udp_src_port <= 0;
            r_udp_dst_port <= 0;
            r_is_ipv4     <= 0;
            r_is_udp      <= 0;
            meta_dst_mac  <= 0;
            meta_src_mac  <= 0;
            meta_ethertype <= 0;
            meta_ip_src   <= 0;
            meta_ip_dst   <= 0;
            meta_ip_proto <= 0;
            meta_udp_src_port <= 0;
            meta_udp_dst_port <= 0;
            meta_is_ipv4  <= 0;
            meta_is_udp   <= 0;
        end else begin
            m_axis_tdata  <= s_axis_tdata;
            m_axis_tkeep  <= s_axis_tkeep;
            m_axis_tvalid <= s_axis_tvalid;
            m_axis_tlast  <= s_axis_tlast;
            m_axis_tuser  <= s_axis_tuser;
            meta_valid    <= 0;

            if (s_axis_tvalid) begin
                case (beat_cnt)
                    4'd0: begin
                        r_dst_mac[47:40] <= s_axis_tdata[ 7: 0];  
                        r_dst_mac[39:32] <= s_axis_tdata[15: 8];  
                        r_dst_mac[31:24] <= s_axis_tdata[23:16];  
                        r_dst_mac[23:16] <= s_axis_tdata[31:24];  
                        r_dst_mac[15: 8] <= s_axis_tdata[39:32];  
                        r_dst_mac[ 7: 0] <= s_axis_tdata[47:40];  
                        r_src_mac[47:40] <= s_axis_tdata[55:48];  
                        r_src_mac[39:32] <= s_axis_tdata[63:56];  
                    end
                    4'd1: begin
                        r_src_mac[31:24] <= s_axis_tdata[ 7: 0];  
                        r_src_mac[23:16] <= s_axis_tdata[15: 8];  
                        r_src_mac[15: 8] <= s_axis_tdata[23:16];  
                        r_src_mac[ 7: 0] <= s_axis_tdata[31:24];  
                        r_ethertype[15:8] <= s_axis_tdata[39:32]; 
                        r_ethertype[ 7:0] <= s_axis_tdata[47:40]; 
                        r_is_ipv4 <= (s_axis_tdata[39:32] == 8'h08) &&
                                     (s_axis_tdata[47:40] == 8'h00);
                    end
                    4'd2: begin
                        r_ip_proto <= s_axis_tdata[63:56]; 
                        r_is_udp   <= (s_axis_tdata[63:56] == 8'h11); 
                    end
                    4'd3: begin
                        r_ip_src[31:24] <= s_axis_tdata[23:16]; 
                        r_ip_src[23:16] <= s_axis_tdata[31:24]; 
                        r_ip_src[15: 8] <= s_axis_tdata[39:32]; 
                        r_ip_src[ 7: 0] <= s_axis_tdata[47:40]; 
                        r_ip_dst[31:24] <= s_axis_tdata[55:48]; 
                        r_ip_dst[23:16] <= s_axis_tdata[63:56]; 
                    end
                    4'd4: begin
                        
                        r_ip_dst[15: 8] <= s_axis_tdata[ 7: 0]; 
                        r_ip_dst[ 7: 0] <= s_axis_tdata[15: 8]; 
                        r_udp_src_port[15:8] <= s_axis_tdata[23:16]; 
                        r_udp_src_port[ 7:0] <= s_axis_tdata[31:24]; 
                        r_udp_dst_port[15:8] <= s_axis_tdata[39:32]; 
                        r_udp_dst_port[ 7:0] <= s_axis_tdata[47:40]; 
                    end
                    default: ; 
                endcase

                if (s_axis_tlast) begin
                    
                    meta_valid         <= 1;
                    meta_dst_mac       <= r_dst_mac;
                    meta_src_mac       <= r_src_mac;
                    meta_ethertype     <= r_ethertype;
                    meta_ip_proto      <= r_ip_proto;
                    meta_ip_src        <= r_ip_src;
                    meta_ip_dst        <= r_ip_dst;
                    meta_udp_src_port  <= r_udp_src_port;
                    meta_udp_dst_port  <= r_udp_dst_port;
                    meta_is_ipv4       <= r_is_ipv4;
                    meta_is_udp        <= r_is_udp & r_is_ipv4;
                    beat_cnt           <= 0;
                end else begin
                    beat_cnt <= beat_cnt + 1;
                end
            end
        end
    end

endmodule
