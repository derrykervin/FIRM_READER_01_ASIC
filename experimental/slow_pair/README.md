# Production-default paired M0 busy-window qualification

This adds a separate slow-device digital qualification. The existing CPB16/347
20-scenario accelerated suite and all manufacturing checks remain mandatory.
Neither production RTL nor any product deadline or clock constraint changes.

The actual23 CARD +9 Reader formal source files drive both TT wrappers, UARTs,
CPU/MMIO, ownership logic and resolved open-drain I2C. The bench applies no
defparam timing overrides:40MHz, CPB347, DIV100,128 polls,200ms command and1s
CARD session,1.2s Reader child and1.25s host operation use their product defaults.
The physical chip, board, contacts and secure device are not being measured.

The independent device model starts its busy window at actual command STOP.
It NACKs until the pinned Microchip608-M0 estimates: Read5ms, GenKey115ms,
Random23ms, Nonce20ms and Sign115ms. All accepted ACKs must meet those lower
bounds; the test does not reinterpret them as measured silicon/PVT maxima.
The verbatim vendor source and copyright/license header are preserved in
vendor/calib_execution.c, pinned to cryptoauthlib d49c7d578efb09d4a498d5ab86839d4c17812f15,
Git blob13e65d52d6bb43d42bfc2e81a158f15ec8f4578d,
SHA256 b86e6357088556b8641cdec0a23fb85419e61248159541ef7819c664ddb70e87.
M1/M2 or unknown clock modes are outside this proposed M0 profile.

Additional configurations:

- normal: identity then fresh software-fixture proof, with one identical cached
  retry of each.18 real command STOP/ACK windows; no I2C execution on retry.
- late_key: post-sign public-key mismatch discards all provisional proof at the
  host; a fresh subsequent context succeeds without external reset.26 windows,
  two executions and two cache retries, strict reference consumption/replay checks.
- old20: mutate only the staged CARD default128 polls to20. It must fail at
  GenKey after exactly20 busy NACKs, with no GenKey ACK and no success marker.
- early_model: corrupt only the staged model to ACK immediately. Its independent
  lower-bound assertion must fail. An arbitrary simulator exit is not accepted.

Fixtures use known software private keys and preissued fresh reference-store
challenges. UART bytes are actually consumed by the reference registry/strict
one-use verifier. This is not device cryptography, authenticated factory
provisioning, interactive production server validation or a secure-login claim.
Physical testing is deferred because the user has no dedicated test capability;
electrical, mechanical and real-device residual risks remain unverified.

Run the additional CVC qualification:

```sh
python3 -B experimental/slow_pair/check.py --card /path/to/FIRM_CARD_01_ASIC \
  --out /tmp/slow-pair --cvc /path/to/cvc64
```

An independent full normal Icarus replay can use run.py without --cvc and with
`--simulation-timeout 2400`.
The wall-clock host budget does not change any simulated cycle deadline.
run.py reports exactly which source/staged bytes and ACK cycles were exercised.
The existing CVC statement coverage controls remain unqualified; no100% claim.
