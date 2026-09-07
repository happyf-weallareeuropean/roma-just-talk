#!/usr/bin/env python3
"""Prepare public runtime cases and a hard-linked verified cache; no network or inference."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil


def digest(path):
    result = hashlib.sha256()
    with path.open('rb') as source:
        for block in iter(lambda: source.read(1024 * 1024), b''):
            result.update(block)
    return result.hexdigest()


def prepare(fixtures, model, resources, destination):
    manifest = json.loads((fixtures / 'manifest.json').read_text())
    snapshot = json.loads((resources / 'snapshot.json').read_text())
    by_id = {item['id']: item for item in manifest['fixtures']}
    # An existing destination is evidence, never silently replace it.
    destination.mkdir(parents=True, exist_ok=False)
    cache = destination / 'cache' / snapshot['revision']
    cache.mkdir(parents=True)
    for item in snapshot['files']:
        source = model / item['file']
        if (not source.is_file() or source.is_symlink()
                or source.stat().st_size != item['bytes'] or digest(source) != item['sha256']):
            raise ValueError(f'Pinned model file invalid: {source}')
        os.link(source, cache / item['file'])
    tokenizer = resources / 'tokenizer.json'
    token_record = snapshot['tokenizer']
    if tokenizer.stat().st_size != token_record['bytes'] or digest(tokenizer) != token_record['sha256']:
        raise ValueError('Bundled tokenizer differs from pinned snapshot')
    shutil.copyfile(tokenizer, cache / 'tokenizer.json')
    cases, references = [], []

    def add(identifier, fixture, **overrides):
        count = overrides.pop('repeat', 1)
        item = by_id[fixture]
        source = fixtures / item['audio']
        if digest(source) != item['audio_sha256']:
            raise ValueError(f'Pinned fixture invalid: {source}')
        target = destination / item['audio']
        if not target.exists():
            shutil.copyfile(source, target)
        case = dict(id=identifier, inputs=[dict(file=item['audio'], sha256=item['audio_sha256'])] * count,
                    preRoll='silence', gapMilliseconds=0, trailingSilenceMilliseconds=0,
                    packetSamples=[1280], deliveryHoldMilliseconds=0, tailHoldMilliseconds=0,
                    unloadBefore=False, prewarmBefore=True)
        case.update(overrides)
        cases.append(case)
        references.append(dict(id=identifier, text=' '.join([item['reference']] * count),
                               source=item['reference_provenance'], repetitions=count))

    short, medium, long = 'zhtw-short-early-eos', 'mixed-8s-privacy', 'mixed-11s-long'
    add('short-unloaded-silence-preroll', short, unloadBefore=True, prewarmBefore=False)
    add('short-warm-no-preroll', short, preRoll='none')
    add('short-warm-silence-preroll', short)
    add('short-speech-preroll-quick-release', short, preRoll='speechPrefix', trailingSilenceMilliseconds=350)
    add('mixed8-silence-preroll', medium)
    add('mixed11-silence-preroll', long)
    add('mixed11-speech-preroll', long, preRoll='speechPrefix')
    add('mixed8-tail-backlog', medium, tailHoldMilliseconds=1050)
    add('mixed8-startup-backlog', medium, deliveryHoldMilliseconds=8352)
    add('mixed11-repeated-three-times', long, repeat=3, gapMilliseconds=250)
    add('mixed8-uneven-packets', medium, packetSamples=[127, 1601, 11, 2560])
    (destination / 'cases.json').write_text(json.dumps(cases, indent=2) + '\n')
    (destination / 'references.json').write_text(json.dumps(references, ensure_ascii=False, indent=2) + '\n')
    (destination / 'provenance.json').write_text(json.dumps(dict(
        fixtureManifestSHA256=digest(fixtures / 'manifest.json'), snapshot=snapshot,
        tokenizerSHA256=digest(tokenizer), caseCount=len(cases),
        boundary='Production runtime; no microphone, app key handling, transport insertion, or UI observation.',
        syntheticCases=['mixed8-tail-backlog', 'mixed8-startup-backlog', 'mixed11-repeated-three-times'],
    ), indent=2) + '\n')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('fixtures', type=Path)
    parser.add_argument('model', type=Path)
    parser.add_argument('resources', type=Path)
    parser.add_argument('destination', type=Path)
    arguments = parser.parse_args()
    prepare(arguments.fixtures, arguments.model, arguments.resources, arguments.destination)
