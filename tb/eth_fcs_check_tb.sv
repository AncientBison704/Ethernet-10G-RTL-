`timescale 1 ns / 1 ps

module eth_fcs_check_tb;
    reg clk = 0;
    reg resetn = 0;
    always #3.2 clk = ~clk;

    reg  [63:0] s_axis_tdata;
    reg  [ 7:0] s_axis_tkeep;
    reg         s_axis_tvalid;
    reg         s_axis_tlast;
    reg  [ 0:0] s_axis_tuser;

    wire [63:0] m_axis_tdata;
    wire [ 7:0] m_axis_tkeep;
    wire        m_axis_tvalid;
    wire        m_axis_tlast;
    wire [ 0:0] m_axis_tuser;

    eth_fcs_check dut (
        .clk(clk), .resetn(resetn),
        .s_axis_tdata(s_axis_tdata), .s_axis_tkeep(s_axis_tkeep),
        .s_axis_tvalid(s_axis_tvalid), .s_axis_tlast(s_axis_tlast), .s_axis_tuser(s_axis_tuser),
        .m_axis_tdata(m_axis_tdata), .m_axis_tkeep(m_axis_tkeep),
        .m_axis_tvalid(m_axis_tvalid), .m_axis_tlast(m_axis_tlast), .m_axis_tuser(m_axis_tuser)
    );

    integer pass_count = 0;
    integer fail_count = 0;

    reg [7:0] tx_frame [0:2047];
    integer   tx_len;

    reg [7:0] rx_frame [0:2047];
    integer   rx_len;
    reg       rx_done;
    reg       rx_bad;

    reg [7:0] exp_frame [0:2047];
    integer   exp_len;
    reg       exp_bad;

    function [31:0] crc32_byte;
        input [31:0] crc_in;
        input [ 7:0] data;
        reg   [31:0] crc;
        integer i;
        begin
            crc = crc_in ^ data;
            for (i = 0; i < 8; i = i + 1) begin
                if (crc[0])
                    crc = (crc >> 1) ^ 32'hEDB88320;
                else
                    crc = (crc >> 1);
            end
            crc32_byte = crc;
        end
    endfunction

    function [31:0] crc32_buf;
        input integer len;
        integer i;
        reg [31:0] crc;
        begin
            crc = 32'hFFFF_FFFF;
            for (i = 0; i < len; i = i + 1)
                crc = crc32_byte(crc, tx_frame[i]);
            crc32_buf = ~crc;
        end
    endfunction

    always @(posedge clk) begin : cap
        integer i;
        if (m_axis_tvalid) begin
            for (i = 0; i < 8; i = i + 1) begin
                if (m_axis_tkeep[i]) begin
                    rx_frame[rx_len] = m_axis_tdata[i*8 +: 8];
                    rx_len = rx_len + 1;
                end
            end
            if (m_axis_tlast) begin
                rx_done = 1;
                rx_bad  = m_axis_tuser[0];
            end
        end
    end

    task drive_idle;
        begin
            @(negedge clk);
            s_axis_tdata  = 64'd0;
            s_axis_tkeep  = 8'd0;
            s_axis_tvalid = 1'b0;
            s_axis_tlast  = 1'b0;
            s_axis_tuser  = 1'b0;
        end
    endtask

    task send_frame;
        integer idx, i, rem;
        reg [63:0] beat;
        reg [31:0] fcs;
        input integer payload_len;
        input [7:0] base;
        input bad_fcs;
        input pre_bad;
        begin
            rx_len = 0;
            rx_done = 0;
            rx_bad = 0;

            tx_len = payload_len;
            for (i = 0; i < payload_len; i = i + 1)
                tx_frame[i] = base + i[7:0];

            fcs = crc32_buf(payload_len);
            tx_frame[payload_len + 0] = fcs[7:0];
            tx_frame[payload_len + 1] = fcs[15:8];
            tx_frame[payload_len + 2] = fcs[23:16];
            tx_frame[payload_len + 3] = fcs[31:24];
            tx_len = payload_len + 4;

            if (bad_fcs)
                tx_frame[payload_len + 0] = tx_frame[payload_len + 0] ^ 8'h01;

            exp_len = tx_len;
            exp_bad = bad_fcs | pre_bad;
            for (i = 0; i < exp_len; i = i + 1)
                exp_frame[i] = tx_frame[i];

            drive_idle;
            idx = 0;
            while (idx < tx_len) begin
                beat = 64'd0;
                rem  = tx_len - idx;
                @(negedge clk);
                for (i = 0; i < 8; i = i + 1) begin
                    if (i < rem)
                        beat[i*8 +: 8] = tx_frame[idx+i];
                end
                s_axis_tdata  = beat;
                s_axis_tkeep  = (rem >= 8) ? 8'hFF : ((1 << rem) - 1);
                s_axis_tvalid = 1'b1;
                s_axis_tlast  = (rem <= 8);
                s_axis_tuser  = pre_bad;
                idx = idx + ((rem >= 8) ? 8 : rem);
            end
            drive_idle;
            repeat (5) @(posedge clk);
        end
    endtask

    task verify;
        input [255:0] name;
        integer i;
        integer mismatch_idx;
        begin
            mismatch_idx = -1;
            if (!rx_done) begin
                $display("  FAIL: %0s - no output", name);
                fail_count = fail_count + 1;
            end else if (rx_len != exp_len) begin
                $display("  FAIL: %0s - len=%0d exp=%0d", name, rx_len, exp_len);
                fail_count = fail_count + 1;
            end else if (rx_bad != exp_bad) begin
                $display("  FAIL: %0s - bad=%0b exp=%0b", name, rx_bad, exp_bad);
                fail_count = fail_count + 1;
            end else begin
                for (i = 0; i < exp_len; i = i + 1) begin
                    if ((mismatch_idx == -1) && (rx_frame[i] !== exp_frame[i]))
                        mismatch_idx = i;
                end

                if (mismatch_idx != -1) begin
                    $display("  FAIL: %0s - byte %0d got %02h exp %02h",
                             name, mismatch_idx, rx_frame[mismatch_idx], exp_frame[mismatch_idx]);
                    fail_count = fail_count + 1;
                end else begin
                    $display("  PASS: %0s", name);
                    pass_count = pass_count + 1;
                end
            end
        end
    endtask

    initial begin
        $dumpfile("eth_fcs_check_tb.vcd");
        $dumpvars(0, eth_fcs_check_tb);

        s_axis_tdata = 0;
        s_axis_tkeep = 0;
        s_axis_tvalid = 0;
        s_axis_tlast = 0;
        s_axis_tuser = 0;

        repeat (20) @(posedge clk);
        resetn = 1;
        repeat (5) @(posedge clk);

        $display("\n=== FCS CHECK Tests ===\n");

        send_frame(60, 8'h10, 1'b0, 1'b0);
        verify("good 60B payload");

        send_frame(17, 8'h80, 1'b0, 1'b0);
        verify("good 17B payload");

        send_frame(1, 8'hF0, 1'b0, 1'b0);
        verify("good 1B payload");

        send_frame(64, 8'h20, 1'b1, 1'b0);
        verify("bad FCS");

        send_frame(32, 8'h40, 1'b0, 1'b1);
        verify("propagate upstream error");

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
        repeat (100000) @(posedge clk);
        $display("TIMEOUT");
        $finish;
    end
endmodule
