`timescale 1 ns / 1 ps

module xgmii_rx_fcs_pipe_tb;
    localparam CLK_PERIOD = 6.4; 
    localparam MAX_BYTES  = 256;

    reg         clk;
    reg         resetn;
    reg  [63:0] xgmii_rxd;
    reg  [ 7:0] xgmii_rxc;

    wire [63:0] m_axis_tdata;
    wire [ 7:0] m_axis_tkeep;
    wire        m_axis_tvalid;
    wire        m_axis_tlast;
    wire [ 0:0] m_axis_tuser;

    integer i;
    integer out_len;
    reg [7:0] frame_mem [0:MAX_BYTES-1];
    reg [7:0] expect_mem[0:MAX_BYTES-1];
    reg [7:0] out_mem   [0:MAX_BYTES-1];
    
    reg final_tuser_reg;
    reg saw_tlast;

    xgmii_rx_fcs_pipe dut (
        .clk(clk),
        .resetn(resetn),
        .xgmii_rxd(xgmii_rxd),
        .xgmii_rxc(xgmii_rxc),
        .m_axis_tdata(m_axis_tdata),
        .m_axis_tkeep(m_axis_tkeep),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tlast(m_axis_tlast),
        .m_axis_tuser(m_axis_tuser)
    );

    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD/2.0) clk = ~clk;
    end

    function [31:0] crc32_byte;
        input [31:0] crc_in;
        input [ 7:0] data;
        reg   [31:0] crc;
        integer k;
        begin
            crc = crc_in ^ data;
            for (k = 0; k < 8; k = k + 1) begin
                if (crc[0])
                    crc = (crc >> 1) ^ 32'hEDB88320;
                else
                    crc = (crc >> 1);
            end
            crc32_byte = crc;
        end
    endfunction

    function [31:0] calc_fcs;
        input integer nbytes;
        reg [31:0] crc;
        integer idx;
        begin
            crc = 32'hFFFF_FFFF;
            for (idx = 0; idx < nbytes; idx = idx + 1)
                crc = crc32_byte(crc, frame_mem[idx]);
            calc_fcs = ~crc;
        end
    endfunction

    task automatic init_idle;
        begin
            xgmii_rxd = {8{8'h07}};
            xgmii_rxc = 8'hFF;
        end
    endtask

    task automatic append_fcs;
        input integer payload_len;
        input        corrupt;
        reg [31:0] fcs;
        begin
            fcs = calc_fcs(payload_len);
            if (corrupt)
                fcs = fcs ^ 32'h00000001;
            frame_mem[payload_len+0] = fcs[ 7:0];
            frame_mem[payload_len+1] = fcs[15:8];
            frame_mem[payload_len+2] = fcs[23:16];
            frame_mem[payload_len+3] = fcs[31:24];
        end
    endtask

    task automatic drive_frame;
        input integer total_len;
        integer idx;
        integer lane;
        reg [63:0] beat_data;
        reg [ 7:0] beat_ctrl;
        begin
            @(negedge clk);
            beat_data = 64'd0;
            beat_ctrl = 8'd0;
            beat_data[ 7:0] = 8'hFB;
            beat_data[15:8] = 8'h55;
            beat_data[23:16] = 8'h55;
            beat_data[31:24] = 8'h55;
            beat_data[39:32] = 8'h55;
            beat_data[47:40] = 8'h55;
            beat_data[55:48] = 8'h55;
            beat_data[63:56] = 8'hD5;
            beat_ctrl[0] = 1'b1;
            xgmii_rxd = beat_data;
            xgmii_rxc = beat_ctrl;

            idx = 0;
            while (idx < total_len) begin
                @(negedge clk);
                beat_data = 64'd0;
                beat_ctrl = 8'd0;
                for (lane = 0; lane < 8; lane = lane + 1) begin
                    if (idx < total_len) begin
                        beat_data[lane*8 +: 8] = frame_mem[idx];
                        idx = idx + 1;
                    end else begin
                        beat_data[lane*8 +: 8] = 8'hFD;
                        beat_ctrl[lane] = 1'b1;
                        lane = 8;
                    end
                end
                xgmii_rxd = beat_data;
                xgmii_rxc = beat_ctrl;
            end

            if ((total_len % 8) == 0) begin
                @(negedge clk);
                xgmii_rxd = {{7{8'h07}}, 8'hFD};
                xgmii_rxc = 8'b00000001;
            end

            @(negedge clk);
            init_idle();
            @(negedge clk);
            init_idle();
        end
    endtask

    task automatic wait_for_tlast;
        integer timeout;
        begin
            timeout = 0;
            while (!(m_axis_tvalid && m_axis_tlast)) begin
                @(posedge clk);
                timeout = timeout + 1;
                if (timeout > 2000) begin
                    $display("ERROR: timeout waiting for tlast");
                    $finish;
                end
            end
        end
    endtask

    task automatic run_test;
        input integer payload_len;
        input        corrupt;
        input [255:0] test_name;
        integer total_len;
        integer j;
        reg [0:0] final_tuser;
        begin
            $display("Running %0s", test_name);

            for (j = 0; j < MAX_BYTES; j = j + 1) begin
                frame_mem[j]  = 8'd0;
                expect_mem[j] = 8'd0;
                out_mem[j]    = 8'd0;
            end

            for (j = 0; j < payload_len; j = j + 1)
                frame_mem[j] = (8'h20 + j[7:0]);

            append_fcs(payload_len, corrupt);
            total_len = payload_len + 4;
            for (j = 0; j < total_len; j = j + 1)
                expect_mem[j] = frame_mem[j];

            out_len = 0;
            saw_tlast = 0;
	    final_tuser_reg = 0;

	    drive_frame(total_len);
            wait (saw_tlast);
	    @(posedge clk);   

	    final_tuser = final_tuser_reg;

            if (out_len !== total_len) begin
                $display("FAIL %0s: out_len=%0d expected=%0d", test_name, out_len, total_len);
                $finish;
            end

            for (j = 0; j < total_len; j = j + 1) begin
                if (out_mem[j] !== expect_mem[j]) begin
                    $display("FAIL %0s: byte %0d got=%02x exp=%02x", test_name, j, out_mem[j], expect_mem[j]);
                    $finish;
                end
            end

            if (!corrupt && final_tuser !== 1'b0) begin
                $display("FAIL %0s: expected good FCS, tuser=%0d", test_name, final_tuser);
                $finish;
            end
            if (corrupt && final_tuser !== 1'b1) begin
                $display("FAIL %0s: expected bad FCS, tuser=%0d", test_name, final_tuser);
                $finish;
            end

            $display("PASS %0s", test_name);
            repeat (4) @(posedge clk);
        end
    endtask

    always @(posedge clk) begin
    if (!resetn) begin
        out_len <= 0;
        final_tuser_reg <= 0;
        saw_tlast <= 1'b0;
    end else begin
        if (m_axis_tvalid) begin
            if (m_axis_tkeep[0]) out_mem[out_len+0] = m_axis_tdata[7:0];
            if (m_axis_tkeep[1]) out_mem[out_len+1] = m_axis_tdata[15:8];
            if (m_axis_tkeep[2]) out_mem[out_len+2] = m_axis_tdata[23:16];
            if (m_axis_tkeep[3]) out_mem[out_len+3] = m_axis_tdata[31:24];
            if (m_axis_tkeep[4]) out_mem[out_len+4] = m_axis_tdata[39:32];
            if (m_axis_tkeep[5]) out_mem[out_len+5] = m_axis_tdata[47:40];
            if (m_axis_tkeep[6]) out_mem[out_len+6] = m_axis_tdata[55:48];
            if (m_axis_tkeep[7]) out_mem[out_len+7] = m_axis_tdata[63:56];

            out_len <= out_len
                     + m_axis_tkeep[0] + m_axis_tkeep[1] + m_axis_tkeep[2] + m_axis_tkeep[3]
                     + m_axis_tkeep[4] + m_axis_tkeep[5] + m_axis_tkeep[6] + m_axis_tkeep[7];

            if (m_axis_tlast) begin
                final_tuser_reg <= m_axis_tuser;
                saw_tlast <= 1'b1;
            end
        end
    end
end

    initial begin
        $dumpfile("xgmii_rx_fcs_pipe_tb.vcd");
        $dumpvars(0, xgmii_rx_fcs_pipe_tb);

        resetn = 1'b0;
        init_idle();
        repeat (8) @(posedge clk);
        resetn = 1'b1;
        repeat (4) @(posedge clk);

        run_test(16, 1'b0, "good_16B_payload");
        run_test(17, 1'b0, "good_17B_payload");
        run_test(16, 1'b1, "bad_16B_payload");
        run_test(31, 1'b1, "bad_31B_payload");

        $display("All end-to-end RX+FCS tests passed.");
        $finish;
    end
endmodule
