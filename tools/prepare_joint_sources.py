"""Keep both UART implementations in joint simulation without changing RTL.

Only Reader module declarations and their two instantiation type names are
namespaced in generated build copies. Port names and instance names stay intact.
This preparation step does not compile or simulate HDL.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re


def prepare(reader, card, output, manifest):
    output.mkdir(parents=True, exist_ok=True)
    records = []
    for filename in ('firm_reader_01.v', 'uart_rx.v', 'uart_tx.v'):
        original = (reader / 'src' / filename).read_bytes()
        generated = original
        substitutions = []
        kinds = ('uart_rx', 'uart_tx') if filename == 'firm_reader_01.v' else (filename[:-2],)
        for kind in kinds:
            if filename == 'firm_reader_01.v':
                pattern = rb'\b' + kind.encode() + rb'(?=\s*#\s*\()'
            else:
                pattern = rb'(?<=module )' + kind.encode() + rb'\b'
            renamed = ('joint_reader_' + kind).encode()
            if renamed in original:
                raise ValueError('reserved joint module identifier already present')
            generated, count = re.subn(pattern, renamed, generated)
            if count != 1:
                raise ValueError(f'{filename}: expected exactly one {kind} type, got {count}')
            substitutions.append({'from': kind, 'to': renamed.decode(), 'count': count})
        # Byte-level inverse proves the copies differ only by the module names.
        inverse = generated
        for change in substitutions:
            inverse = inverse.replace(change['to'].encode(), change['from'].encode())
        if inverse != original:
            raise ValueError('unexpected transformation beyond module names')
        target = output / filename
        target.write_bytes(generated)
        records.append({'source': str((reader/'src'/filename).resolve()),
                        'source_sha256': hashlib.sha256(original).hexdigest(),
                        'generated': str(target.resolve()),
                        'generated_sha256': hashlib.sha256(generated).hexdigest(),
                        'substitutions': substitutions})
    for filename in ('card.v', 'card_cpu.v', 'program_rom.v', 'spi_master.v', 'uart_rx.v', 'uart_tx.v'):
        path = card / 'src' / filename
        records.append({'source': str(path.resolve()),
                        'source_sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
                        'transformation': 'none'})
    manifest.parent.mkdir(parents=True, exist_ok=True)
    manifest.write_text(json.dumps({'scope': 'source preparation only; not HDL verification',
                                    'files': records}, indent=2)+'\n')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--reader', type=Path, default=Path('.'))
    parser.add_argument('--card', type=Path, required=True)
    parser.add_argument('--output', type=Path, default=Path('build/joint_reader'))
    parser.add_argument('--manifest', type=Path, default=Path('reports/current/joint-sources.json'))
    args = parser.parse_args()
    prepare(args.reader, args.card, args.output, args.manifest)
