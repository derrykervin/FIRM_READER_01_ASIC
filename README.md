# FIRM_READER_01 ¡ª SKY26d candidate

Port of the existing FIRM_READER_01 v0.1 controller to Tiny Tapeout.
See docs/info.md for interfaces and limitations. Core source attribution is
preserved. This is test-only authentication, not production security.

Target: SKY130A, 40 MHz, UART divisor 347, 1x2 tiles. Both chips use an external
shared oscillator; no clock is forwarded through a 40 MHz output pad.

GDS/DRC/LVS/precheck, gate-level tests and portal revision status must each be
verified before calling this submitted. A successful FPGA build is insufficient.
