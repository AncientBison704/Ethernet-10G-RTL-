# 10GbE Packet Processor

A low-latency 10 Gigabit Ethernet packet processing pipeline in SystemVerilog, fully verified in simulation. Implements XGMII MAC RX/TX, parallel CRC32 (FCS), pipelined IPv4/UDP header parser, configurable packet filter, and end-to-end loopback verification.

## Architecture

```
                        ┌─────────────────────────────────────────────┐
                        │              RX Pipeline                    │
 XGMII 64-bit  ──────► │  XGMII RX → FCS Check → Header Parse       │
 @ 156.25 MHz           │                              │              │
                        │                          metadata           │
                        └──────────────────────────────┼──────────────┘
                                                       │
                                                       ▼
                                              ┌────────────────┐
                                              │  Packet Filter │
                                              │  (IP/port/     │
                                              │   subnet match)│
                                              └───────┬────────┘
                                                      │
                        ┌─────────────────────────────┼──────────────┐
                        │              TX Pipeline    ▼              │
 XGMII 64-bit  ◄────── │  XGMII TX ← FCS Insert ← AXI-Stream      │
 @ 156.25 MHz           │                                            │
                        └────────────────────────────────────────────┘
```

## Key Features

- **XGMII RX** with 1-beat pipeline for correct TERM-in-lane-0 handling
- **Parallel CRC32** — auto-generated XOR trees for 1-8 byte widths, no loops or conditionals (synthesizable at line-rate)
- **Streaming FCS check** — CRC32 residue verification, zero-copy passthrough
- **Pipelined header parser** — extracts ETH/IPv4/UDP fields in-flight over 5 AXI-Stream beats
- **Configurable packet filter** — 4 match rules with IP src/dst subnet masking, UDP port filtering, per-rule enable, frame statistics
- **FCS insert** — computes CRC32 and appends 4-byte FCS with proper AXI-Stream backpressure
- **XGMII TX** — preamble/SFD generation, data transmission, TERM/IFG insertion
- **Full loopback verification** — byte-exact match through RX → FCS → strip → FCS insert → TX

## Test Results

```
make test-rx        →  8/8  PASSED   XGMII RX (aligned, unaligned, back-to-back)
make test-fcs       →  5/5  PASSED   Parallel CRC32 FCS check
make test-rx-fcs    →  4/4  PASSED   End-to-end RX + FCS pipeline
make test-filter    →  6/6  PASSED   Header parser + packet filter
make test-loopback  →  3/3  PASSED   Full RX → TX loopback (byte-exact)
                      ─────
                      26/26 ALL TESTS PASSED
```

## Directory Structure

```
eth_10g/
├── rtl/
│   ├── eth_pkg.sv              # XGMII constants (START/TERM/IDLE/SFD)
│   ├── crc32_parallel.svh      # Auto-generated parallel CRC32 XOR trees
│   ├── xgmii_rx.sv             # XGMII → AXI-Stream receiver
│   ├── eth_fcs_check.sv        # Streaming CRC32 FCS checker
│   ├── xgmii_rx_fcs_pipe.sv    # RX + FCS structural wrapper
│   ├── eth_header_parse.sv     # ETH/IPv4/UDP header extractor
│   ├── pkt_filter.sv           # Configurable IP/port packet filter
│   ├── eth_fcs_insert.sv       # CRC32 compute + append (with backpressure)
│   ├── xgmii_tx.sv             # AXI-Stream → XGMII transmitter
│   └── tx_pipeline.sv          # FCS insert + XGMII TX wrapper
├── tb/
│   ├── xgmii_rx_tb.sv          # 8 RX tests
│   ├── eth_fcs_check_tb.sv     # 5 FCS tests (good/bad/error propagation)
│   ├── xgmii_rx_fcs_pipe_tb.sv # 4 end-to-end RX+FCS tests
│   ├── header_filter_tb.sv     # 6 filter tests (match/drop/subnet/port)
│   └── loopback_tb.sv          # 3 loopback tests (byte-exact verify)
├── scripts/
│   └── gen_crc32.py            # CRC32 XOR equation generator
├── Makefile
└── README.md
```

## Requirements

- `iverilog` (Icarus Verilog 12+) or Synopsys VCS
- `python3` (for CRC32 generation only)
- Optional: `gtkwave` for waveform viewing

```bash
# Ubuntu/Debian
sudo apt install iverilog
```

## Quick Start

```bash
# Run all tests
make test-rx && make test-fcs && make test-rx-fcs && make test-filter && make test-loopback
```

Or run individual test suites:

```bash
make test-loopback   # full end-to-end loopback (the most comprehensive test)
make wave-loopback   # view loopback waveforms in GTKWave
```

## Build Targets

| Target              | Description                                    |
|---------------------|------------------------------------------------|
| `make test-rx`      | XGMII RX tests (8 tests)                      |
| `make test-fcs`     | FCS check tests (5 tests)                     |
| `make test-rx-fcs`  | RX + FCS pipeline tests (4 tests)             |
| `make test-filter`  | Header parser + filter tests (6 tests)        |
| `make test-loopback`| Full RX → TX loopback tests (3 tests)         |
| `make wave-rx`      | View RX waveforms                              |
| `make wave-fcs`     | View FCS waveforms                             |
| `make wave-filter`  | View filter waveforms                          |
| `make wave-loopback`| View loopback waveforms                        |
| `make clean`        | Remove all generated files                     |

## Module Details

### XGMII RX (`xgmii_rx.sv`)

Converts 64-bit XGMII (8 bytes/cycle @ 156.25 MHz) to AXI-Stream. Detects START character, validates preamble/SFD, strips them, and outputs frame data. Uses a 1-beat pipeline register to handle the case where TERM appears in lane 0 of the beat *after* the last data — the pipeline delays output by 1 cycle so `tlast` can be applied retroactively.

### Parallel CRC32 (`crc32_parallel.svh`)

Auto-generated by `scripts/gen_crc32.py` from the Ethernet CRC32 polynomial (`0xEDB88320`, reflected). Contains 8 functions (`crc32_1byte` through `crc32_8byte`) that compute the next CRC state using pure XOR expressions — no loops, no conditionals, no iteration. A top-level `crc32_64b` function dispatches by `tkeep` to the correct width. This is the same approach used in production ASIC/FPGA Ethernet MACs.

To regenerate:
```bash
python3 scripts/gen_crc32.py
```

### Header Parser (`eth_header_parse.sv`)

Extracts Ethernet, IPv4, and UDP header fields from the first 5 AXI-Stream beats as they pass through. No buffering — fields are captured into registers on each beat using a beat counter. Outputs parsed metadata (`dst_mac`, `src_mac`, `ethertype`, `ip_src`, `ip_dst`, `ip_proto`, `udp_src_port`, `udp_dst_port`, `is_ipv4`, `is_udp`) alongside `tlast` of the data stream.

Parsed field locations in the 64-bit beat stream:

| Beat | Bytes   | Fields extracted                           |
|------|---------|--------------------------------------------|
| 0    | 0–7     | dst MAC (6B) + src MAC (2B)                |
| 1    | 8–15    | src MAC (4B) + ethertype (2B) + IP start   |
| 2    | 16–23   | IP total len, ID, flags, TTL, protocol     |
| 3    | 24–31   | IP checksum + src IP (4B) + dst IP (2B)    |
| 4    | 32–39   | dst IP (2B) + UDP src port + UDP dst port  |

### Packet Filter (`pkt_filter.sv`)

Store-and-forward filter with 4 configurable match rules. Each rule can match on:
- IP source address (with subnet mask)
- IP destination address (with subnet mask)
- UDP destination port (exact match)
- Per-rule enable bit

A frame passes if **any** enabled rule matches. If no rules are enabled, all frames pass (default-allow). Includes frame statistics counters (in, passed, dropped).

### FCS Insert (`eth_fcs_insert.sv`)

Buffers the outgoing frame in a FIFO, computes CRC32 in-flight using the parallel CRC engine, then replays the frame with 4 FCS bytes appended. Properly merges FCS bytes into the last data beat when there's room, or emits overflow FCS bytes in a separate beat. Implements AXI-Stream backpressure (`tready`/`tvalid` handshaking).

### XGMII TX (`xgmii_tx.sv`)

Converts AXI-Stream back to XGMII. Emits idle characters, then START + preamble/SFD, then frame data, then TERM + idle (IFG). Handles both full-beat and partial-beat termination. Asserts `tready` only during the data phase to prevent data loss.

## GTKWave Verification

### Loopback (`make wave-loopback`)

Add signals from `u_rx`, `u_fcs_check`, `u_tx`:
- `u_rx.state` — RX FSM: 0(IDLE) → 1(DATA) → 2(LAST)
- `u_fcs_check.crc_state` — CRC32 accumulating per beat
- `u_fcs_check.fcs_bad` — 0 for valid frames
- `u_tx.u_xgmii_tx.state` — TX FSM: 0(IDLE) → 1(PREAMBLE) → 2(DATA) → 3(TERM) → 4(IFG)
- `tx_xgmii_txd`, `tx_xgmii_txc` — output XGMII bus

### Filter (`make wave-filter`)

- `u_parse.beat_cnt` — counts header beats 0→1→2→3→4
- `u_parse.r_ip_dst` — destination IP settling by beat 4
- `u_filter.state` — 0(STORE) → 1(DECIDE) → 2(FORWARD) or 3(DROP)
- `u_filter.any_rule_matched` — 1 = pass, 0 = drop
- `u_filter.stat_frames_passed` / `stat_frames_dropped`

## Design Decisions

**1-beat RX pipeline**: XGMII can place TERM in lane 0 of the cycle after the last data, meaning you don't know the current beat is the final one until you see the next beat. The pipeline adds 1 cycle of latency but correctly handles all terminate positions.

**Parallel CRC over iterative**: The iterative `crc32_byte` function (8 XOR iterations per byte × 8 bytes = 64 serial operations per cycle) works in simulation but wouldn't meet timing at 156.25 MHz on an FPGA. The auto-generated XOR trees compute all 64 bit updates in a single combinational step.

**Store-and-forward filter**: The filter must buffer the entire frame because the match decision depends on metadata that's only complete at `tlast`. This adds latency proportional to frame size but is architecturally simple. A cut-through design could start forwarding after beat 4 (once headers are parsed) with a kill mechanism for non-matching frames.

## License

MIT License
