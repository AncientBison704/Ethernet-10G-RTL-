`timescale 1 ns / 1 ps

module loopback_tb;
    import eth_pkg::*;

    reg clk = 0;
    reg resetn = 0;
    always #3.2 clk = ~clk;

    reg  [63:0] rx_xgmii_rxd;
    reg  [ 7:0] rx_xgmii_rxc;

    wire [63:0] rx_out_tdata;
    wire [ 7:0] rx_out_tkeep;
    wire        rx_out_tvalid;
    wire        rx_out_tlast;
    wire [ 0:0] rx_out_tuser;

    wire [63:0] fcs_out_tdata;
    wire [ 7:0] fcs_out_tkeep;
    wire        fcs_out_tvalid;
    wire        fcs_out_tlast;
    wire [ 0:0] fcs_out_tuser;

    wire [63:0] tx_xgmii_txd;
    wire [ 7:0] tx_xgmii_txc;


    xgmii_rx u_rx (
        .clk(clk), .resetn(resetn),
        .xgmii_rxd(rx_xgmii_rxd), .xgmii_rxc(rx_xgmii_rxc),
        .m_axis_tdata(rx_out_tdata), .m_axis_tkeep(rx_out_tkeep),
        .m_axis_tvalid(rx_out_tvalid), .m_axis_tlast(rx_out_tlast),
        .m_axis_tuser(rx_out_tuser)
    );

    eth_fcs_check u_fcs_check (
        .clk(clk), .resetn(resetn),
        .s_axis_tdata(rx_out_tdata), .s_axis_tkeep(rx_out_tkeep),
        .s_axis_tvalid(rx_out_tvalid), .s_axis_tlast(rx_out_tlast),
        .s_axis_tuser(rx_out_tuser),
        .m_axis_tdata(fcs_out_tdata), .m_axis_tkeep(fcs_out_tkeep),
        .m_axis_tvalid(fcs_out_tvalid), .m_axis_tlast(fcs_out_tlast),
        .m_axis_tuser(fcs_out_tuser)
    );

    reg  [63:0] strip_tdata;
    reg  [ 7:0] strip_tkeep;
    reg         strip_tvalid;
    reg         strip_tlast;


    reg [63:0] sb_data [0:255];
    reg [ 7:0] sb_keep [0:255];
    reg [7:0]  sb_wr, sb_rd, sb_total;
    reg [1:0]  sb_state;
    reg [11:0] sb_byte_count;

    localparam SS_STORE  = 2'd0;
    localparam SS_CALC   = 2'd1;
    localparam SS_REPLAY = 2'd2;

    function [3:0] popcount;
        input [7:0] k;
        begin
            popcount = k[0]+k[1]+k[2]+k[3]+k[4]+k[5]+k[6]+k[7];
        end
    endfunction

    reg [7:0]  strip_end_beat;    
    reg [3:0]  strip_end_bytes;   
    reg [11:0] stripped_total;   

    always @(posedge clk) begin
        if (!resetn) begin
            strip_tvalid  <= 0;
            strip_tlast   <= 0;
            strip_tdata   <= 0;
            strip_tkeep   <= 0;
            sb_wr         <= 0;
            sb_rd         <= 0;
            sb_total      <= 0;
            sb_state      <= SS_STORE;
            sb_byte_count <= 0;
        end else begin
            strip_tvalid <= 0;
            strip_tlast  <= 0;

            case (sb_state)
                SS_STORE: begin
                    if (fcs_out_tvalid) begin
                        sb_data[sb_wr] <= fcs_out_tdata;
                        sb_keep[sb_wr] <= fcs_out_tkeep;
                        sb_byte_count  <= sb_byte_count + popcount(fcs_out_tkeep);
                        sb_wr <= sb_wr + 1;

                        if (fcs_out_tlast) begin
                            sb_total <= sb_wr + 1;
                            sb_state <= SS_CALC;
                        end
                    end
                end

                SS_CALC: begin
                    stripped_total <= sb_byte_count - 4;

                    if (sb_byte_count > 4) begin
                        strip_end_beat  <= (sb_byte_count - 5) / 8;  // (stripped-1)/8
                        strip_end_bytes <= ((sb_byte_count - 4 - 1) % 8) + 1;
                    end

                    sb_rd    <= 0;
                    sb_state <= SS_REPLAY;
                end

                SS_REPLAY: begin
                    if (sb_rd <= strip_end_beat) begin
                        strip_tdata  <= sb_data[sb_rd];
                        strip_tvalid <= 1;

                        if (sb_rd == strip_end_beat) begin
                            case (strip_end_bytes)
                                1: strip_tkeep <= 8'h01;
                                2: strip_tkeep <= 8'h03;
                                3: strip_tkeep <= 8'h07;
                                4: strip_tkeep <= 8'h0F;
                                5: strip_tkeep <= 8'h1F;
                                6: strip_tkeep <= 8'h3F;
                                7: strip_tkeep <= 8'h7F;
                                default: strip_tkeep <= 8'hFF;
                            endcase
                            strip_tlast <= 1;
                            sb_wr         <= 0;
                            sb_rd         <= 0;
                            sb_byte_count <= 0;
                            sb_state      <= SS_STORE;
                        end else begin
                            strip_tkeep <= 8'hFF;
                            sb_rd <= sb_rd + 1;
                        end
                    end
                end
            endcase
        end
    end

    tx_pipeline u_tx (
        .clk(clk), .resetn(resetn),
        .s_axis_tdata(strip_tdata),
        .s_axis_tkeep(strip_tkeep),
        .s_axis_tvalid(strip_tvalid),
        .s_axis_tlast(strip_tlast),
        .xgmii_txd(tx_xgmii_txd),
        .xgmii_txc(tx_xgmii_txc)
    );

    reg [7:0] frame_buf [0:2047];
    integer frame_len;

    function [31:0] crc32_byte;
        input [31:0] crc_in;
        input [7:0] data;
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
        input [31:0] ip_src, ip_dst;
        input [15:0] udp_sport, udp_dport;
        input integer payload_len;
        integer i, udp_len, ip_len;
        reg [31:0] fcs;
        begin
            udp_len = 8 + payload_len;
            ip_len = 20 + udp_len;
            frame_len = 14 + ip_len;

            frame_buf[0]=8'hFF; frame_buf[1]=8'hFF; frame_buf[2]=8'hFF;
            frame_buf[3]=8'hFF; frame_buf[4]=8'hFF; frame_buf[5]=8'hFF;
            frame_buf[6]=8'h00; frame_buf[7]=8'h11; frame_buf[8]=8'h22;
            frame_buf[9]=8'h33; frame_buf[10]=8'h44; frame_buf[11]=8'h55;
            frame_buf[12]=8'h08; frame_buf[13]=8'h00;

            // IPv4
            frame_buf[14]=8'h45; frame_buf[15]=8'h00;
            frame_buf[16]=ip_len[15:8]; frame_buf[17]=ip_len[7:0];
            frame_buf[18]=8'h00; frame_buf[19]=8'h00;
            frame_buf[20]=8'h40; frame_buf[21]=8'h00;
            frame_buf[22]=8'h40; frame_buf[23]=8'h11;
            frame_buf[24]=8'h00; frame_buf[25]=8'h00;
            frame_buf[26]=ip_src[31:24]; frame_buf[27]=ip_src[23:16];
            frame_buf[28]=ip_src[15:8]; frame_buf[29]=ip_src[7:0];
            frame_buf[30]=ip_dst[31:24]; frame_buf[31]=ip_dst[23:16];
            frame_buf[32]=ip_dst[15:8]; frame_buf[33]=ip_dst[7:0];

            // UDP
            frame_buf[34]=udp_sport[15:8]; frame_buf[35]=udp_sport[7:0];
            frame_buf[36]=udp_dport[15:8]; frame_buf[37]=udp_dport[7:0];
            frame_buf[38]=udp_len[15:8]; frame_buf[39]=udp_len[7:0];
            frame_buf[40]=8'h00; frame_buf[41]=8'h00;

            for (i = 0; i < payload_len; i = i + 1)
                frame_buf[42+i] = i[7:0];

            begin
                reg [31:0] c;
                c = 32'hFFFFFFFF;
                for (i = 0; i < frame_len; i = i + 1)
                    c = crc32_byte(c, frame_buf[i]);
                fcs = ~c;
            end
            frame_buf[frame_len+0]=fcs[7:0];
            frame_buf[frame_len+1]=fcs[15:8];
            frame_buf[frame_len+2]=fcs[23:16];
            frame_buf[frame_len+3]=fcs[31:24];
            frame_len = frame_len + 4;
        end
    endtask

    task xgmii_drive;
        integer idx, si;
        reg [63:0] bd;
        reg [7:0] bc;
        begin
            @(negedge clk); rx_xgmii_rxd={8{XGMII_IDLE}}; rx_xgmii_rxc=8'hFF;
            @(negedge clk); rx_xgmii_rxd={8{XGMII_IDLE}}; rx_xgmii_rxc=8'hFF;
            @(negedge clk);
            rx_xgmii_rxd={SFD,PREAMBLE,PREAMBLE,PREAMBLE,PREAMBLE,PREAMBLE,PREAMBLE,XGMII_START};
            rx_xgmii_rxc=8'h01;

            idx = 0;
            while (idx < frame_len) begin
                @(negedge clk);
                bd = 64'h0; bc = 8'h0;
                if (frame_len - idx >= 8) begin
                    for (si=0; si<8; si=si+1) bd[si*8+:8] = frame_buf[idx+si];
                    idx = idx + 8;
                end else begin
                    for (si=0; si<8; si=si+1) begin
                        if (idx+si < frame_len) bd[si*8+:8] = frame_buf[idx+si];
                        else if (idx+si == frame_len) begin bd[si*8+:8]=XGMII_TERM; bc[si]=1; end
                        else begin bd[si*8+:8]=XGMII_IDLE; bc[si]=1; end
                    end
                    idx = frame_len;
                end
                rx_xgmii_rxd = bd; rx_xgmii_rxc = bc;
            end
            if ((frame_len%8)==0) begin
                @(negedge clk);
                rx_xgmii_rxd={XGMII_IDLE,XGMII_IDLE,XGMII_IDLE,XGMII_IDLE,
                              XGMII_IDLE,XGMII_IDLE,XGMII_IDLE,XGMII_TERM};
                rx_xgmii_rxc=8'hFF;
            end
            @(negedge clk); rx_xgmii_rxd={8{XGMII_IDLE}}; rx_xgmii_rxc=8'hFF;
            @(negedge clk); rx_xgmii_rxd={8{XGMII_IDLE}}; rx_xgmii_rxc=8'hFF;
        end
    endtask

    reg [7:0] tx_cap [0:2047];
    integer tx_cap_len;
    reg tx_cap_active;
    reg tx_cap_done;
    reg tx_cap_started;  

    always @(posedge clk) begin : tx_capture
        integer ci;
        if (!resetn) begin
            tx_cap_len     = 0;
            tx_cap_active  = 0;
            tx_cap_done    = 0;
            tx_cap_started = 0;
        end else if (!tx_cap_done) begin
            if (!tx_cap_started) begin
                if (tx_xgmii_txc[0] && tx_xgmii_txd[7:0] == XGMII_START)
                    tx_cap_started = 1;  
            end else if (!tx_cap_active) begin
                tx_cap_active = 1;
                for (ci = 0; ci < 8; ci = ci + 1) begin
                    if (tx_xgmii_txc[ci] && tx_xgmii_txd[ci*8+:8] == XGMII_TERM) begin
                        tx_cap_active = 0;
                        tx_cap_done   = 1;
                    end else if (!tx_xgmii_txc[ci]) begin
                        tx_cap[tx_cap_len] = tx_xgmii_txd[ci*8+:8];
                        tx_cap_len = tx_cap_len + 1;
                    end
                end
            end else begin
                for (ci = 0; ci < 8; ci = ci + 1) begin
                    if (tx_xgmii_txc[ci] && tx_xgmii_txd[ci*8+:8] == XGMII_TERM) begin
                        tx_cap_active = 0;
                        tx_cap_done   = 1;
                    end else if (!tx_xgmii_txc[ci]) begin
                        tx_cap[tx_cap_len] = tx_xgmii_txd[ci*8+:8];
                        tx_cap_len = tx_cap_len + 1;
                    end
                end
            end
        end
    end

    integer pass_count = 0;
    integer fail_count = 0;

    task verify_loopback;
        input [255:0] name;
        input integer exp_len;
        integer i;
        reg mismatch;
        begin
            mismatch = 0;
            if (!tx_cap_done) begin
                $display("  FAIL: %0s — no TX output captured", name);
                fail_count = fail_count + 1;
                disable verify_loopback;
            end
            if (tx_cap_len != exp_len) begin
                $display("  FAIL: %0s — TX len=%0d expected=%0d", name, tx_cap_len, exp_len);
                fail_count = fail_count + 1;
                disable verify_loopback;
            end
            for (i = 0; i < exp_len; i = i + 1) begin
                if (tx_cap[i] !== frame_buf[i]) begin
                    if (!mismatch)
                        $display("  FAIL: %0s — byte[%0d] TX=0x%02h expected=0x%02h",
                            name, i, tx_cap[i], frame_buf[i]);
                    mismatch = 1;
                end
            end
            if (mismatch)
                fail_count = fail_count + 1;
            else begin
                $display("  PASS: %0s (%0d bytes, including FCS)", name, tx_cap_len);
                pass_count = pass_count + 1;
            end
        end
    endtask

    integer lat_start, lat_end;

    initial begin
        $dumpfile("loopback_tb.vcd");
        $dumpvars(0, loopback_tb);

        rx_xgmii_rxd = {8{XGMII_IDLE}};
        rx_xgmii_rxc = 8'hFF;

        repeat (20) @(posedge clk);
        resetn = 1;
        repeat (10) @(posedge clk);

        $display("\n=== Loopback Tests ===\n");

        $display("--- Test 1: 60+4 byte frame ---");
        tx_cap_len = 0; tx_cap_done = 0; tx_cap_active = 0; tx_cap_started = 0;
        build_udp_frame(32'hC0A80101, 32'hC0A80102, 16'd1234, 16'd5678, 18);
        lat_start = $time;
        xgmii_drive;
        repeat (100) @(posedge clk);
        lat_end = $time;
        verify_loopback("60+4B frame", frame_len);
        $display("  Latency: %0d ns", (lat_end - lat_start) / 1000);

        repeat (10) @(posedge clk);

        $display("\n--- Test 2: 142+4 byte frame ---");
        tx_cap_len = 0; tx_cap_done = 0; tx_cap_active = 0; tx_cap_started = 0;
        build_udp_frame(32'h0A000001, 32'h0A000002, 16'd4000, 16'd8080, 100);
        xgmii_drive;
        repeat (200) @(posedge clk);
        verify_loopback("142+4B frame", frame_len);

        repeat (10) @(posedge clk);

        $display("\n--- Test 3: 43+4 byte frame ---");
        tx_cap_len = 0; tx_cap_done = 0; tx_cap_active = 0; tx_cap_started = 0;
        build_udp_frame(32'hAC100164, 32'hAC1001FF, 16'd9999, 16'd53, 1);
        xgmii_drive;
        repeat (100) @(posedge clk);
        verify_loopback("43+4B frame", frame_len);

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
        repeat (500000) @(posedge clk);
        $display("TIMEOUT");
        $finish;
    end

endmodule
