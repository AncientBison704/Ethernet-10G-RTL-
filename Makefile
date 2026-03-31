
RTL_DIR = rtl
TB_DIR  = tb

IVFLAGS = -g2012 -I$(RTL_DIR)

RX_RTL = $(RTL_DIR)/eth_pkg.sv $(RTL_DIR)/xgmii_rx.sv
RX_TB  = $(TB_DIR)/xgmii_rx_tb.sv

.PHONY: test-rx
test-rx: sim/xgmii_rx_tb
	cd sim && vvp ../sim/xgmii_rx_tb

sim/xgmii_rx_tb: $(RX_RTL) $(RX_TB)
	iverilog $(IVFLAGS) -o $@ -s xgmii_rx_tb $(RX_RTL) $(RX_TB)

.PHONY: wave-rx
wave-rx:
	gtkwave sim/xgmii_rx_tb.vcd &

FCS_RTL = $(RTL_DIR)/eth_pkg.sv $(RTL_DIR)/eth_fcs_check.sv
FCS_TB  = $(TB_DIR)/eth_fcs_check_tb.sv

.PHONY: test-fcs
test-fcs: sim/eth_fcs_check_tb
	cd sim && vvp ../sim/eth_fcs_check_tb

sim/eth_fcs_check_tb: $(FCS_RTL) $(FCS_TB)
	iverilog $(IVFLAGS) -o $@ -s eth_fcs_check_tb $(FCS_RTL) $(FCS_TB)

.PHONY: wave-fcs
wave-fcs:
	gtkwave sim/eth_fcs_check_tb.vcd &


RX_FCS_RTL = $(RTL_DIR)/eth_pkg.sv $(RTL_DIR)/xgmii_rx.sv $(RTL_DIR)/eth_fcs_check.sv $(RTL_DIR)/xgmii_rx_fcs_pipe.sv
RX_FCS_TB  = $(TB_DIR)/xgmii_rx_fcs_pipe_tb.sv

.PHONY: test-rx-fcs
test-rx-fcs: sim/xgmii_rx_fcs_pipe_tb
	cd sim && vvp ../sim/xgmii_rx_fcs_pipe_tb

sim/xgmii_rx_fcs_pipe_tb: $(RX_FCS_RTL) $(RX_FCS_TB)
	iverilog $(IVFLAGS) -o $@ -s xgmii_rx_fcs_pipe_tb $(RX_FCS_RTL) $(RX_FCS_TB)

.PHONY: wave-rx-fcs
wave-rx-fcs:
	gtkwave sim/xgmii_rx_fcs_pipe_tb.vcd &

W3_RTL = $(RTL_DIR)/eth_pkg.sv $(RTL_DIR)/xgmii_rx.sv $(RTL_DIR)/eth_fcs_check.sv \
         $(RTL_DIR)/eth_header_parse.sv $(RTL_DIR)/pkt_filter.sv
W3_TB  = $(TB_DIR)/header_filter_tb.sv

.PHONY: test-filter
test-filter: sim/header_filter_tb
	cd sim && vvp ../sim/header_filter_tb

sim/header_filter_tb: $(W3_RTL) $(W3_TB)
	iverilog $(IVFLAGS) -o $@ -s header_filter_tb $(W3_RTL) $(W3_TB)

.PHONY: wave-filter
wave-filter:
	gtkwave sim/header_filter_tb.vcd &

W4_RTL = $(RTL_DIR)/eth_pkg.sv $(RTL_DIR)/xgmii_rx.sv $(RTL_DIR)/eth_fcs_check.sv \
         $(RTL_DIR)/eth_fcs_insert.sv $(RTL_DIR)/xgmii_tx.sv $(RTL_DIR)/tx_pipeline.sv
W4_TB  = $(TB_DIR)/loopback_tb.sv

.PHONY: test-loopback
test-loopback: sim/loopback_tb
	cd sim && vvp ../sim/loopback_tb

sim/loopback_tb: $(W4_RTL) $(W4_TB)
	iverilog $(IVFLAGS) -o $@ -s loopback_tb $(W4_RTL) $(W4_TB)

.PHONY: wave-loopback
wave-loopback:
	gtkwave sim/loopback_tb.vcd &

.PHONY: clean
clean:
	rm -f sim/xgmii_rx_tb sim/eth_fcs_check_tb sim/xgmii_rx_fcs_pipe_tb
	rm -f sim/header_filter_tb sim/loopback_tb sim/*.vcd
