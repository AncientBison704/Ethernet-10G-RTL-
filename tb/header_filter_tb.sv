`timescale 1 ns / 1 ps

module header_filter_tb;
    import eth_pkg::*;

    reg clk = 0;
    reg resetn = 0;
    always #3.2 clk = ~clk;

    reg  [63:0] xgmii_rxd;
    reg  [ 7:0] xgmii_rxc;

    wire [63:0] rx_tdata;
    wire [ 7:0] rx_tkeep;
    wire        rx_tvalid, rx_tlast;
    wire [ 0:0] rx_tuser;

    wire [63:0] fcs_tdata;
    wire [ 7:0] fcs_tkeep;
    wire        fcs_tvalid, fcs_tlast;
    wire [ 0:0] fcs_tuser;

    wire [63:0] parse_tdata;
    wire [ 7:0] parse_tkeep;
    wire        parse_tvalid, parse_tlast;
    wire [ 0:0] parse_tuser;
    wire        parse_meta_valid;
    wire [47:0] parse_dst_mac, parse_src_mac;
    wire [15:0] parse_ethertype;
    wire [31:0] parse_ip_src, parse_ip_dst;
    wire [ 7:0] parse_ip_proto;
    wire [15:0] parse_udp_src_port, parse_udp_dst_port;
    wire        parse_is_ipv4, parse_is_udp;

    wire [63:0] filt_tdata;
    wire [ 7:0] filt_tkeep;
    wire        filt_tvalid, filt_tlast;
    wire [ 0:0] filt_tuser;
    wire [31:0] stat_in, stat_pass, stat_drop;

    reg  [3:0]  cfg_rule_en;
    reg  [127:0] cfg_ip_src;
    reg  [127:0] cfg_ip_src_mask;
    reg  [127:0] cfg_ip_dst;
    reg  [127:0] cfg_ip_dst_mask;
    reg  [63:0]  cfg_udp_dst_port;
    reg  [3:0]   cfg_udp_port_en;

    xgmii_rx u_rx (
        .clk(clk), .resetn(resetn),
        .xgmii_rxd(xgmii_rxd), .xgmii_rxc(xgmii_rxc),
        .m_axis_tdata(rx_tdata), .m_axis_tkeep(rx_tkeep),
        .m_axis_tvalid(rx_tvalid), .m_axis_tlast(rx_tlast), .m_axis_tuser(rx_tuser)
    );

    eth_fcs_check u_fcs (
        .clk(clk), .resetn(resetn),
        .s_axis_tdata(rx_tdata), .s_axis_tkeep(rx_tkeep),
        .s_axis_tvalid(rx_tvalid), .s_axis_tlast(rx_tlast), .s_axis_tuser(rx_tuser),
        .m_axis_tdata(fcs_tdata), .m_axis_tkeep(fcs_tkeep),
        .m_axis_tvalid(fcs_tvalid), .m_axis_tlast(fcs_tlast), .m_axis_tuser(fcs_tuser)
    );

    eth_header_parse u_parse (
        .clk(clk), .resetn(resetn),
        .s_axis_tdata(fcs_tdata), .s_axis_tkeep(fcs_tkeep),
        .s_axis_tvalid(fcs_tvalid), .s_axis_tlast(fcs_tlast), .s_axis_tuser(fcs_tuser),
        .m_axis_tdata(parse_tdata), .m_axis_tkeep(parse_tkeep),
        .m_axis_tvalid(parse_tvalid), .m_axis_tlast(parse_tlast), .m_axis_tuser(parse_tuser),
        .meta_valid(parse_meta_valid),
        .meta_dst_mac(parse_dst_mac), .meta_src_mac(parse_src_mac),
        .meta_ethertype(parse_ethertype),
        .meta_ip_src(parse_ip_src), .meta_ip_dst(parse_ip_dst),
        .meta_ip_proto(parse_ip_proto),
        .meta_udp_src_port(parse_udp_src_port), .meta_udp_dst_port(parse_udp_dst_port),
        .meta_is_ipv4(parse_is_ipv4), .meta_is_udp(parse_is_udp)
    );

    pkt_filter #(.NUM_RULES(4)) u_filter (
        .clk(clk), .resetn(resetn),
        .s_axis_tdata(parse_tdata), .s_axis_tkeep(parse_tkeep),
        .s_axis_tvalid(parse_tvalid), .s_axis_tlast(parse_tlast), .s_axis_tuser(parse_tuser),
        .meta_valid(parse_meta_valid),
        .meta_ip_src(parse_ip_src), .meta_ip_dst(parse_ip_dst),
        .meta_udp_dst_port(parse_udp_dst_port),
        .meta_is_ipv4(parse_is_ipv4), .meta_is_udp(parse_is_udp),
        .m_axis_tdata(filt_tdata), .m_axis_tkeep(filt_tkeep),
        .m_axis_tvalid(filt_tvalid), .m_axis_tlast(filt_tlast), .m_axis_tuser(filt_tuser),
        .cfg_rule_en(cfg_rule_en),
        .cfg_ip_src(cfg_ip_src), .cfg_ip_src_mask(cfg_ip_src_mask),
        .cfg_ip_dst(cfg_ip_dst), .cfg_ip_dst_mask(cfg_ip_dst_mask),
        .cfg_udp_dst_port(cfg_udp_dst_port), .cfg_udp_port_en(cfg_udp_port_en),
        .stat_frames_in(stat_in), .stat_frames_passed(stat_pass), .stat_frames_dropped(stat_drop)
    );

    reg [7:0] frame_buf [0:2047];
    integer frame_len;

    integer pass_count = 0;
    integer fail_count = 0;

    reg [7:0] cap_buf [0:2047];
    integer cap_len;
    reg cap_done;

    always @(posedge clk) begin : capture
        integer ci;
        if (filt_tvalid) begin
            for (ci = 0; ci < 8; ci = ci + 1)
                if (filt_tkeep[ci]) begin
                    cap_buf[cap_len] = filt_tdata[ci*8 +: 8];
                    cap_len = cap_len + 1;
                end
            if (filt_tlast)
                cap_done = 1;
        end
    end

    function [31:0] crc32_byte;
        input [31:0] crc_in;
        input [ 7:0] data;
        reg [31:0] crc;
        integer i;
        begin
            crc = crc_in ^ data;
            for (i = 0; i < 8; i = i + 1)
                crc = crc[0] ? (crc >> 1) ^ 32'hEDB88320 : (crc >> 1);
            crc32_byte = crc;
        end
    endfunction

    task build_udp_frame;
        input [47:0] dst_mac;
        input [47:0] src_mac;
        input [31:0] ip_src;
        input [31:0] ip_dst;
        input [15:0] udp_src_port;
        input [15:0] udp_dst_port;
        input integer payload_len;
        integer i;
        integer udp_len, ip_total_len;
        reg [31:0] fcs;
        begin
            udp_len = 8 + payload_len;
            ip_total_len = 20 + udp_len;
            frame_len = 14 + ip_total_len;

            frame_buf[0]  = dst_mac[47:40];
            frame_buf[1]  = dst_mac[39:32];
            frame_buf[2]  = dst_mac[31:24];
            frame_buf[3]  = dst_mac[23:16];
            frame_buf[4]  = dst_mac[15: 8];
            frame_buf[5]  = dst_mac[ 7: 0];
            frame_buf[6]  = src_mac[47:40];
            frame_buf[7]  = src_mac[39:32];
            frame_buf[8]  = src_mac[31:24];
            frame_buf[9]  = src_mac[23:16];
            frame_buf[10] = src_mac[15: 8];
            frame_buf[11] = src_mac[ 7: 0];
            frame_buf[12] = 8'h08;  
            frame_buf[13] = 8'h00;

            frame_buf[14] = 8'h45;  
            frame_buf[15] = 8'h00;  
            frame_buf[16] = ip_total_len[15:8];
            frame_buf[17] = ip_total_len[7:0];
            frame_buf[18] = 8'h00;  
            frame_buf[19] = 8'h00;
            frame_buf[20] = 8'h40;  
            frame_buf[21] = 8'h00;
            frame_buf[22] = 8'h40;  
            frame_buf[23] = 8'h11;  
            frame_buf[24] = 8'h00;  
            frame_buf[25] = 8'h00;
            frame_buf[26] = ip_src[31:24];
            frame_buf[27] = ip_src[23:16];
            frame_buf[28] = ip_src[15: 8];
            frame_buf[29] = ip_src[ 7: 0];
            frame_buf[30] = ip_dst[31:24];
            frame_buf[31] = ip_dst[23:16];
            frame_buf[32] = ip_dst[15: 8];
            frame_buf[33] = ip_dst[ 7: 0];

            frame_buf[34] = udp_src_port[15:8];
            frame_buf[35] = udp_src_port[7:0];
            frame_buf[36] = udp_dst_port[15:8];
            frame_buf[37] = udp_dst_port[7:0];
            frame_buf[38] = udp_len[15:8];
            frame_buf[39] = udp_len[7:0];
            frame_buf[40] = 8'h00;  
            frame_buf[41] = 8'h00;

            for (i = 0; i < payload_len; i = i + 1)
                frame_buf[42 + i] = i[7:0];

            begin
                reg [31:0] crc;
                crc = 32'hFFFFFFFF;
                for (i = 0; i < frame_len; i = i + 1)
                    crc = crc32_byte(crc, frame_buf[i]);
                fcs = ~crc;
            end
            frame_buf[frame_len + 0] = fcs[ 7: 0];
            frame_buf[frame_len + 1] = fcs[15: 8];
            frame_buf[frame_len + 2] = fcs[23:16];
            frame_buf[frame_len + 3] = fcs[31:24];
            frame_len = frame_len + 4;  
        end
    endtask

    task xgmii_send;
        integer idx, si;
        reg [63:0] beat_data;
        reg [ 7:0] beat_ctrl;
        begin
            cap_len = 0;
            cap_done = 0;

            @(negedge clk); xgmii_rxd = {8{XGMII_IDLE}}; xgmii_rxc = 8'hFF;
            @(negedge clk); xgmii_rxd = {8{XGMII_IDLE}}; xgmii_rxc = 8'hFF;

            @(negedge clk);
            xgmii_rxd = {SFD, PREAMBLE, PREAMBLE, PREAMBLE,
                         PREAMBLE, PREAMBLE, PREAMBLE, XGMII_START};
            xgmii_rxc = 8'h01;

            idx = 0;
            while (idx < frame_len) begin
                @(negedge clk);
                beat_data = 64'h0;
                beat_ctrl = 8'h00;
                if (frame_len - idx >= 8) begin
                    for (si = 0; si < 8; si = si + 1)
                        beat_data[si*8 +: 8] = frame_buf[idx + si];
                    idx = idx + 8;
                end else begin
                    for (si = 0; si < 8; si = si + 1) begin
                        if (idx + si < frame_len)
                            beat_data[si*8 +: 8] = frame_buf[idx + si];
                        else if (idx + si == frame_len) begin
                            beat_data[si*8 +: 8] = XGMII_TERM;
                            beat_ctrl[si] = 1'b1;
                        end else begin
                            beat_data[si*8 +: 8] = XGMII_IDLE;
                            beat_ctrl[si] = 1'b1;
                        end
                    end
                    idx = frame_len;
                end
                xgmii_rxd = beat_data;
                xgmii_rxc = beat_ctrl;
            end

            if ((frame_len % 8) == 0) begin
                @(negedge clk);
                xgmii_rxd = {XGMII_IDLE, XGMII_IDLE, XGMII_IDLE, XGMII_IDLE,
                             XGMII_IDLE, XGMII_IDLE, XGMII_IDLE, XGMII_TERM};
                xgmii_rxc = 8'hFF;
            end

            @(negedge clk); xgmii_rxd = {8{XGMII_IDLE}}; xgmii_rxc = 8'hFF;
            @(negedge clk); xgmii_rxd = {8{XGMII_IDLE}}; xgmii_rxc = 8'hFF;
            @(negedge clk); xgmii_rxd = {8{XGMII_IDLE}}; xgmii_rxc = 8'hFF;

            repeat (20) @(posedge clk);
        end
    endtask

    initial begin
        $dumpfile("header_filter_tb.vcd");
        $dumpvars(0, header_filter_tb);

        xgmii_rxd = {8{XGMII_IDLE}};
        xgmii_rxc = 8'hFF;
        cfg_rule_en = 0;
        cfg_ip_src = 0; cfg_ip_src_mask = 0;
        cfg_ip_dst = 0; cfg_ip_dst_mask = 0;
        cfg_udp_dst_port = 0; cfg_udp_port_en = 0;

        repeat (20) @(posedge clk);
        resetn = 1;
        repeat (5) @(posedge clk);

        $display("\n=== Header Parser + Filter Tests ===\n");

        $display("--- Test 1: No rules, frame should pass ---");
        cfg_rule_en = 4'b0000;
        build_udp_frame(
            48'hFF_FF_FF_FF_FF_FF,  
            48'h00_11_22_33_44_55,  
            32'hC0_A8_01_0A,        
            32'hC0_A8_01_01,        
            16'd12345,              
            16'd5000,               
            20                      
        );
        xgmii_send;
        if (cap_done) begin
            $display("  PASS: frame passed (no rules)");
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL: frame should have passed");
            fail_count = fail_count + 1;
        end

        $display("\n--- Test 2: IP dst match → pass ---");
        cfg_rule_en = 4'b0001;
        cfg_ip_dst[31:0] = 32'hC0_A8_01_01;        
        cfg_ip_dst_mask[31:0] = 32'hFFFF_FFFF;      
        cfg_ip_src_mask[31:0] = 32'h0000_0000;      
        cfg_udp_port_en[0] = 0;                      

        build_udp_frame(
            48'hFF_FF_FF_FF_FF_FF, 48'h00_11_22_33_44_55,
            32'hC0_A8_01_0A, 32'hC0_A8_01_01,
            16'd12345, 16'd5000, 18
        );
        xgmii_send;
        if (cap_done) begin
            $display("  PASS: matching frame passed");
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL: matching frame should have passed");
            fail_count = fail_count + 1;
        end

        $display("\n--- Test 3: IP dst mismatch → drop ---");
        build_udp_frame(
            48'hFF_FF_FF_FF_FF_FF, 48'h00_11_22_33_44_55,
            32'hC0_A8_01_0A, 32'hC0_A8_02_01,   
            16'd12345, 16'd5000, 18
        );
        xgmii_send;
        if (!cap_done) begin
            $display("  PASS: non-matching frame dropped");
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL: non-matching frame should have been dropped");
            fail_count = fail_count + 1;
        end

        $display("\n--- Test 4: Subnet match /24 → pass ---");
        cfg_ip_dst_mask[31:0] = 32'hFFFFFF00;  
        cfg_ip_dst[31:0] = 32'hC0_A8_01_00;    

        build_udp_frame(
            48'hFF_FF_FF_FF_FF_FF, 48'h00_11_22_33_44_55,
            32'hC0_A8_01_0A, 32'hC0_A8_01_FF,   
            16'd12345, 16'd5000, 22
        );
        xgmii_send;
        if (cap_done) begin
            $display("  PASS: subnet match passed");
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL: subnet match should have passed");
            fail_count = fail_count + 1;
        end

        $display("\n--- Test 5: UDP port match → pass ---");
        cfg_ip_dst_mask[31:0] = 32'h0000_0000;  
        cfg_udp_port_en[0] = 1;
        cfg_udp_dst_port[15:0] = 16'd4789;      

        build_udp_frame(
            48'hFF_FF_FF_FF_FF_FF, 48'h00_11_22_33_44_55,
            32'h0A_00_00_01, 32'h0A_00_00_02,
            16'd55555, 16'd4789, 30
        );
        xgmii_send;
        if (cap_done) begin
            $display("  PASS: UDP port match passed");
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL: UDP port match should have passed");
            fail_count = fail_count + 1;
        end

        $display("\n--- Test 6: UDP port mismatch → drop ---");
        build_udp_frame(
            48'hFF_FF_FF_FF_FF_FF, 48'h00_11_22_33_44_55,
            32'h0A_00_00_01, 32'h0A_00_00_02,
            16'd55555, 16'd8080, 30   
        );
        xgmii_send;
        if (!cap_done) begin
            $display("  PASS: UDP port mismatch dropped");
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL: UDP port mismatch should have been dropped");
            fail_count = fail_count + 1;
        end

        $display("\n--- Statistics ---");
        $display("  Frames in:      %0d", stat_in);
        $display("  Frames passed:  %0d", stat_pass);
        $display("  Frames dropped: %0d", stat_drop);

        $display("\n========================================");
        $display("  %0d / %0d tests passed", pass_count, pass_count + fail_count);
        if (fail_count == 0)
            $display("  ALL TESTS PASSED");
        else
            $display("  %0d TESTS FAILED", fail_count);
        $display("========================================\n");
        $finish;
    end

    initial begin
        repeat (200000) @(posedge clk);
        $display("TIMEOUT");
        $finish;
    end

endmodule
