# Rejection metadata setup repair candidate

Source8cdc30b8df0496e3f6b4aaf4847eb33c21b092f1, GDS43660443359,
fails setup by1.226435876 ns. Source-verified retained-report inspection
43714348542/job132812524754 identifies command_class[1]→reject_command[4]
and reject_sequence paths through request/cache/digest classification.

Capture command and sequence metadata at the existing frame_valid edge
when the rejection slot is empty. Keep the original classification,
reject_pending publication, status/detail, overrun and TX arbitration.
Metadata is unobservable while reject_pending is0. If a slot is full,
neither another frame nor simultaneous TX take can overwrite its metadata.
No protocol cycle, deadline, clock, RAM bank or required function changes.

The local reject_metadata_invariant proves published metadata equivalence
for arbitrary frame, classification and clear inputs under documented
clock/reset abstraction. A deliberately unguarded full-slot overwrite
fails the same proof. This is local queue refinement, not whole-bridge
formal equivalence. Actual-module simulation injects parser publications
to isolate full-slot hold, overrun, exact TX dispatch and reset; a real
guard-removal source mutant must be detected. CRC/frame parsing remains
covered separately by the complete host matrix.

tools/check_reject_metadata.py is required by tools/check.sh. Immutable
joint CI now pins CARD4ea89ba3d056db4405229a95074044f11587c652 so the
new fetch CPU and this Reader are tested together at CPB16 and347;
legacy, fault and asynchronous matrices remain enabled. Every new-source
manufacturing/STA/GL/Precheck check is still mandatory. Until those finish,
this is a timing candidate only. Physical testing is deferred by the user;
digital fixtures do not establish actual secure-device/factory/service
acceptance or TT formal submission.
