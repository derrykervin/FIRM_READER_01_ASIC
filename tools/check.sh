#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
card_dir="${1:-../FIRM_CARD_01_ASIC}"
for tool in python3 iverilog vvp; do
 command -v "$tool" >/dev/null || { printf 'BLOCKED: missing %s\n' "$tool" >&2; exit 127; }
done
test -f "$card_dir/src/card.v"
mkdir -p build reports/current
python3 -B tools/prepare_joint_sources.py --card "$card_dir"
sources=(build/joint_reader/firm_reader_01.v build/joint_reader/uart_rx.v build/joint_reader/uart_tx.v "$card_dir/src/card.v" "$card_dir/src/card_cpu.v" "$card_dir/src/program_rom.v" "$card_dir/src/spi_master.v" "$card_dir/src/uart_rx.v" "$card_dir/src/uart_tx.v")
# Each core now uses its own UART source. Generated Reader type names avoid collision.
for cpb in 8 16 347; do
 iverilog -g2012 -s tb_reader_internal_faults -Ptb_reader_internal_faults.CPB="$cpb" -o build/internal_faults src/firm_reader_01.v src/uart_rx.v src/uart_tx.v test/tb_reader_internal_faults.v
 vvp build/internal_faults | tee "reports/current/internal_faults_$cpb.log"
 iverilog -g2012 -s uart_rx_fault_tb -Puart_rx_fault_tb.CPB="$cpb" -o build/uart_rx_fault src/uart_rx.v test/uart_rx_fault_tb.v
 vvp build/uart_rx_fault | tee "reports/current/uart_rx_fault_$cpb.log"
 for vector in 0 1 2; do
  for alternate in 0 1; do
   iverilog -g2012 -s tb_firm_system -Ptb_firm_system.CPB="$cpb" -Ptb_firm_system.VECTOR="$vector" -Ptb_firm_system.ALT_ID="$alternate" -o build/system "${sources[@]}" test/tb_firm_system.v
   vvp build/system | tee "reports/current/system_${cpb}_${vector}_${alternate}.log"
  done
 done
 iverilog -g2012 -s tb_reader_faults -Ptb_reader_faults.CPB="$cpb" -o build/faults "${sources[@]}" test/tb_reader_faults.v
 vvp build/faults | tee "reports/current/faults_$cpb.log"
done
printf 'PASS: prototype protocol regression only; not production authentication.\n'
