# 10G Ethernet RTL Design and Verification

A SystemVerilog-based implementation and verification project for core **10 Gigabit Ethernet receive datapath components**, developed incrementally in weekly milestones.

This project focuses on **RTL design, protocol-level packet handling, frame integrity verification, and testbench-driven validation** using industry-style digital design workflows.

---

## Project Overview

This repository contains a SystemVerilog implementation of key datapath components used in a **10 Gigabit Ethernet receive pipeline**.

The project focuses on the design and verification of high-speed packet-processing blocks commonly found in Ethernet MAC and network interface logic, including **XGMII frame reception, payload extraction, and frame integrity validation using CRC-based FCS checking**.

The design was developed using an iterative RTL workflow, starting from protocol-level frame parsing and progressing toward an integrated receive pipeline with end-to-end verification.

Particular emphasis was placed on:

* robust RTL module design
* protocol-compliant frame handling
* error detection and propagation
* self-checking verification infrastructure
* waveform-driven debugging and validation

The final integrated pipeline successfully supports correct packet reception, variable payload lengths, and bad-frame detection through FCS mismatch handling.


---

## Key Features

* 64-bit **XGMII receive interface**
* Frame parsing and byte extraction
* Start / terminate control symbol handling
* Ethernet **FCS (CRC-32) verification**
* Good / bad frame detection
* Error flag propagation via `tuser`
* Self-checking testbenches
* Waveform dump generation (`.vcd`)
* Makefile-based simulation workflow

---

## Directory Structure

```text
.
├── rtl/
│   ├── eth_pkg.sv
│   ├── xgmii_rx.sv
│   ├── eth_fcs_check.sv
│   ├── xgmii_rx_fcs_pipe.sv
│   └── ...
│
├── tb/
│   ├── xgmii_rx_tb.sv
│   ├── xgmii_rx_fcs_pipe_tb.sv
│   └── ...
│
├── sim/
│   └── generated simulation binaries and VCD waveforms
│
├── Makefile
├── README.md
└── .gitignore
```

---

## Modules

### `xgmii_rx.sv`

Implements receive-side logic for decoding incoming XGMII data and control lanes.

Responsibilities include:

* detecting start-of-frame delimiter
* collecting payload bytes
* handling control symbols
* asserting valid output stream signals

---

### `eth_fcs_check.sv`

Performs **Frame Check Sequence validation** using Ethernet CRC-32.

This block determines whether the incoming packet is valid.

Outputs include:

* pass/fail FCS status
* bad frame detection
* user-side error flagging

---

### `xgmii_rx_fcs_pipe.sv`

Integrated pipeline module combining:

* XGMII RX parser
* FCS checker
* output AXI-stream style interface

This module was used for **end-to-end verification**.

---

## Testbench Coverage

The testbench includes validation for:

* correct 16-byte payload frames
* non-aligned 17-byte payload frames
* intentionally corrupted FCS frames
* variable packet lengths
* bad frame detection

Example passing simulation output:

```text
Running good_16B_payload
PASS good_16B_payload

Running good_17B_payload
PASS good_17B_payload

Running bad_16B_payload
PASS bad_16B_payload

Running bad_31B_payload
PASS bad_31B_payload

All end-to-end RX+FCS tests passed.
```

---

## How to Run

### Compile and run tests

```bash
make test-rx-fcs
```

### Generate waveform

Waveforms are automatically dumped into:

```text
sim/xgmii_rx_fcs_pipe_tb.vcd
```

Open with GTKWave:

```bash
gtkwave sim/xgmii_rx_fcs_pipe_tb.vcd
```

---

## Tools Used

* SystemVerilog
* Icarus Verilog (`iverilog`)
* VVP
* GTKWave
* Git / GitHub

---

## Skills Demonstrated

This project demonstrates practical experience in:

* RTL design
* digital logic verification
* protocol-level hardware implementation
* simulation debugging
* waveform analysis
* Makefile automation
* Git-based incremental development workflow

---

## Future Improvements

Potential extensions:

* TX datapath implementation
* AXI-stream integration
* pipelined CRC acceleration
* synthesis on FPGA
* timing constraint validation
* hardware bring-up on Xilinx FPGA

