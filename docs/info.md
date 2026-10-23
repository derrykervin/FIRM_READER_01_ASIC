## How it works
FIRM_READER_01 sequences VERSION, CARD_ID and test AUTH over UART.
Both ASICs must use the same external 40 MHz clock. UART divisor is 347
(115273.8 baud). Do not wire reserved output uo[1] as a card clock.
The original core clock-forwarding output is unconnected in this wrapper.
Authentication uses a public fixed challenge and reversible XOR/rotate;
it is not secure authentication. No persistent unique identity or secret storage
is provided. Contact debounce, ESD, level translation, power and mux selection
are external hardware responsibilities. The complete controller core is included;
1x2 tile capacity and timing are unverified until hardening/precheck passes.

## How to test
Reset both packages and configure each shuttle mux to the respective project.
Connect reader uo[0] to card ui[0], card uo[0] to reader ui[0], reader uo[3]
to card rst_n. Share the external oscillator and ground. Set card detect ui[1].
Expect uo[5] TEST_AUTH_PASS high and uo[6] AUTH_FAIL low. Removal clears results.
ui[6:2] selects diagnostic data: 0 state/error, 1 version, 2..9 card ID
most-significant byte first, 10..17 response most-significant byte first.

## External hardware
Two separate physical shuttle ASICs are required to run CARD and READER
concurrently. Use separate mux controllers, decoupled core/IO supplies,
and a buffered external oscillator. This is a candidate, not a submitted design.
