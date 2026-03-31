`timescale 1 ns / 1 ps

module xgmii_rx_tb;
    import eth_pkg::*;

    reg clk = 0;
    reg resetn = 0;
    always #3.2 clk = ~clk;

    reg  [63:0] xgmii_rxd;
    reg  [ 7:0] xgmii_rxc;
    wire [63:0] m_axis_tdata;
    wire [ 7:0] m_axis_tkeep;
    wire        m_axis_tvalid;
    wire        m_axis_tlast;
    wire [ 0:0] m_axis_tuser;

    xgmii_rx dut (
        .clk(clk), .resetn(resetn),
        .xgmii_rxd(xgmii_rxd), .xgmii_rxc(xgmii_rxc),
        .m_axis_tdata(m_axis_tdata), .m_axis_tkeep(m_axis_tkeep),
        .m_axis_tvalid(m_axis_tvalid), .m_axis_tlast(m_axis_tlast),
        .m_axis_tuser(m_axis_tuser)
    );

    integer pass_count = 0;
    integer fail_count = 0;

    reg [7:0] tx_frame [0:2047];  
    integer   tx_len;              

    reg [7:0] rx_frame [0:2047];  
    integer   rx_len;
    reg       rx_error;
    reg       rx_done;

    reg [7:0] exp_frame [0:2047];
    integer   exp_len;
    reg       exp_error;

    always @(posedge clk) begin
        if (m_axis_tvalid) begin : capture_block
            integer ci;
            for (ci = 0; ci < 8; ci = ci + 1) begin
                if (m_axis_tkeep[ci]) begin
                    rx_frame[rx_len] = m_axis_tdata[ci*8 +: 8];
                    rx_len = rx_len + 1;
                end
            end
            if (m_axis_tlast) begin
                rx_error = m_axis_tuser[0];
                rx_done = 1;
            end
        end
    end

    task xgmii_idle;
        begin
            @(negedge clk);
            xgmii_rxd = {8{XGMII_IDLE}};
            xgmii_rxc = 8'hFF;
        end
    endtask

    task xgmii_send;
        integer idx, si;
        reg [63:0] beat_data;
        reg [ 7:0] beat_ctrl;
        begin
            rx_len = 0;
            rx_done = 0;
            rx_error = 0;

            xgmii_idle;
            xgmii_idle;

            @(negedge clk);
            xgmii_rxd = {SFD, PREAMBLE, PREAMBLE, PREAMBLE,
                         PREAMBLE, PREAMBLE, PREAMBLE, XGMII_START};
            xgmii_rxc = 8'h01;

            idx = 0;
            while (idx < tx_len) begin
                @(negedge clk);
                beat_data = 64'h0;
                beat_ctrl = 8'h00;

                if (tx_len - idx >= 8) begin
                    for (si = 0; si < 8; si = si + 1)
                        beat_data[si*8 +: 8] = tx_frame[idx + si];
                    idx = idx + 8;
                end else begin
                    for (si = 0; si < 8; si = si + 1) begin
                        if (idx + si < tx_len)
                            beat_data[si*8 +: 8] = tx_frame[idx + si];
                        else if (idx + si == tx_len) begin
                            beat_data[si*8 +: 8] = XGMII_TERM;
                            beat_ctrl[si] = 1'b1;
                        end else begin
                            beat_data[si*8 +: 8] = XGMII_IDLE;
                            beat_ctrl[si] = 1'b1;
                        end
                    end
                    idx = tx_len;
                end

                xgmii_rxd = beat_data;
                xgmii_rxc = beat_ctrl;
            end

            if ((tx_len % 8) == 0) begin
                @(negedge clk);
                xgmii_rxd = {XGMII_IDLE, XGMII_IDLE, XGMII_IDLE, XGMII_IDLE,
                             XGMII_IDLE, XGMII_IDLE, XGMII_IDLE, XGMII_TERM};
                xgmii_rxc = 8'hFF;
            end

            xgmii_idle;
            xgmii_idle;
            xgmii_idle;

            repeat (5) @(posedge clk);
        end
    endtask

    task verify;
        input [255:0] name;
        integer vi;
        reg mismatch;
        begin
            mismatch = 0;

            if (!rx_done) begin
                $display("  FAIL: %0s — no frame captured", name);
                fail_count = fail_count + 1;
                disable verify;
            end

            if (rx_len != exp_len) begin
                $display("  FAIL: %0s — len=%0d (expected %0d)", name, rx_len, exp_len);
                fail_count = fail_count + 1;
                disable verify;
            end

            if (rx_error != exp_error) begin
                $display("  FAIL: %0s — error=%0b (expected %0b)", name, rx_error, exp_error);
                fail_count = fail_count + 1;
                disable verify;
            end

            for (vi = 0; vi < exp_len; vi = vi + 1) begin
                if (rx_frame[vi] !== exp_frame[vi]) begin
                    if (!mismatch)
                        $display("  FAIL: %0s — data mismatch at byte %0d: 0x%02h vs 0x%02h",
                            name, vi, rx_frame[vi], exp_frame[vi]);
                    mismatch = 1;
                end
            end

            if (mismatch)
                fail_count = fail_count + 1;
            else begin
                $display("  PASS: %0s (%0d bytes)", name, rx_len);
                pass_count = pass_count + 1;
            end
        end
    endtask

    task fill_frame;
        input integer len;
        input [7:0] base;
        integer fi;
        begin
            tx_len = len;
            exp_len = len;
            exp_error = 0;
            for (fi = 0; fi < len; fi = fi + 1) begin
                tx_frame[fi] = base + fi[7:0];
                exp_frame[fi] = base + fi[7:0];
            end
        end
    endtask

    integer i;

    initial begin
        $dumpfile("xgmii_rx_tb.vcd");
        $dumpvars(0, xgmii_rx_tb);

        xgmii_rxd = {8{XGMII_IDLE}};
        xgmii_rxc = 8'hFF;

        repeat (20) @(posedge clk);
        resetn = 1;
        repeat (5) @(posedge clk);

        $display("\n=== XGMII RX Tests ===\n");

        $display("--- Test 1: 16-byte frame ---");
        fill_frame(16, 8'hA0);
        xgmii_send;
        verify("16-byte aligned");

        $display("--- Test 2: 17-byte frame ---");
        fill_frame(17, 8'hB0);
        xgmii_send;
        verify("17-byte unaligned");

        $display("--- Test 3: 64-byte frame ---");
        fill_frame(64, 8'h00);
        xgmii_send;
        verify("64-byte frame");

        $display("--- Test 4: 1-byte frame ---");
        fill_frame(1, 8'hFF);
        xgmii_send;
        verify("1-byte frame");

        $display("--- Test 5: 8-byte frame ---");
        fill_frame(8, 8'h10);
        xgmii_send;
        verify("8-byte exact");

        $display("--- Test 6: 256-byte frame ---");
        fill_frame(256, 8'h00);
        xgmii_send;
        verify("256-byte frame");

        $display("--- Test 7: Back-to-back ---");
        fill_frame(24, 8'hC0);
        xgmii_send;
        verify("b2b frame 1");

        fill_frame(32, 8'hD0);
        xgmii_send;
        verify("b2b frame 2");

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
