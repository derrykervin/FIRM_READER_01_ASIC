"""Qualify the additional production-default, SDK M0 busy-window paired model.

Existing accelerated tests remain mandatory and unchanged. This does not certify
an actual device, factory profile, deployed server or physical implementation.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--card', type=Path, required=True)
    p.add_argument('--out', type=Path, required=True)
    p.add_argument('--cvc', type=Path, required=True)
    p.add_argument('--review-only', action='store_true')
    a = p.parse_args()
    here = Path(__file__).resolve().parent
    a.out.mkdir(parents=True, exist_ok=True)
    records = []
    for control in ['normal', 'old20', 'early_model', 'late_key']:
        folder = a.out / (control + '-cvc')
        command = [sys.executable, '-B', str(here / 'run.py'), '--card', str(a.card.resolve()),
                   '--out', str(folder.resolve()), '--cvc', str(a.cvc.resolve()),
                   '--control', control, '--simulation-timeout', '1200']
        if not a.review_only:
            subprocess.run(command, check=True)
        result = json.loads((folder / 'results.json').read_text())
        expected = 'DETECTED_EXPECTED_DEFECT' if control in ['old20', 'early_model'] else 'PASS'
        assert result['status'] == expected, (control, result['status'])
        assert result['cpb'] == 347 and result['share_digest'] == 1
        # Both positive configurations use precisely the same32 source RTL bytes.
        if control in ['normal', 'late_key']:
            assert result['cases'] == 4
            wire = json.loads((folder / 'wire-server-results.json').read_text())
            assert wire['status'] == 'PASS_REFERENCE_ONLY' and len(wire['results']) == 2
            for item in wire['results']:
                assert not item.get('login_granted', False)
                assert not item.get('cached_replay_accepted', False)
            if control == 'late_key':
                assert [item['status'] for item in wire['results']] == [8, 0]
                assert [item['reference_signature_accepted'] for item in wire['results']] == [False, True]
        logs = {}
        for name in ['results.json', 'compile.log', 'simulation.log']:
            logs[name] = hashlib.sha256((folder / name).read_bytes()).hexdigest()
        records.append(dict(control=control, status=expected, acknowledgement_windows=result['ack'],
                            source_sha256=result['source_sha256'], staged_sha256=result['staged_sha256'],
                            evidence_sha256=logs))
    normal_rtl = {k: v for k, v in records[0]['source_sha256'].items() if '/src/' in k}
    late_rtl = {k: v for k, v in records[3]['source_sha256'].items() if '/src/' in k}
    assert len(normal_rtl) == 32 and normal_rtl == late_rtl
    report = dict(status='PASS_ADDITIONAL_M0_DIGITAL_MODEL_ONLY', cases=records,
                  clock_hz=40000000, uart_cpb=347, product_rtl_modified=False,
                  scope=__doc__, real_device='NOT_VERIFIED', factory='NOT_VERIFIED',
                  production_server='NOT_VERIFIED', physical_tests='DEFERRED_BY_USER_NO_TEST_CAPABILITY')
    (a.out / 'qualification.json').write_text(json.dumps(report, indent=2) + '\n')
    print(report['status'])


if __name__ == '__main__':
    main()
