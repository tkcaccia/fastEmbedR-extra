#!/usr/bin/env python3
"""Run source-locked paired Mac clustering fits; stop on any mismatch."""
import json
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path('/Users/silvanopiazza/Documents/Stefano/fastEmbedR-multicpu-threadpool-c288af6-20261106')
RSCRIPT = '/Library/Frameworks/R.framework/Resources/bin/Rscript'
ORDER = ('baseline', 'candidate')


def swap_mib():
    value = subprocess.check_output(
        ['/usr/sbin/sysctl', '-n', 'vm.swapusage'], text=True)
    found = re.search(r'used\s*=\s*([0-9.]+)([KMG])', value)
    if found is None:
        raise RuntimeError('macOS swapusage format changed')
    unit = {'K': 1 / 1024, 'M': 1, 'G': 1024}[found.group(2)]
    return float(found.group(1)) * unit


def one(variant, case, method, cores, repetition):
    name = f'{variant}-{case}-{method}-cpu{cores}-r{repetition}'
    log = ROOT / 'runs' / f'{name}.log'
    command = ['/usr/bin/time', '-l', RSCRIPT,
               str(ROOT / 'one_case.R'), variant, case, method,
               str(cores), str(repetition)]
    before_swap = swap_mib()
    with log.open('x') as output:
        result = subprocess.run(command, stdout=output,
                                stderr=subprocess.STDOUT, check=False)
    after_swap = swap_mib()
    metric_path = ROOT / 'runs' / f'{name}.json'
    if result.returncode or not metric_path.is_file():
        raise RuntimeError(f'{name} failed; see {log}')
    found = re.search(r'(\d+)\s+maximum resident set size',
                      log.read_text())
    if found is None:
        raise RuntimeError(f'{name} has no process peak RSS; see {log}')
    metric = json.loads(metric_path.read_text())
    metric['peak_rss_bytes'] = int(found.group(1))
    metric['system_swap_before_mib'] = before_swap
    metric['system_swap_after_mib'] = after_swap
    metric_path.write_text(json.dumps(metric, indent=2) + '\n')
    return metric


def main():
    (ROOT / 'runs').mkdir(exist_ok=False)
    for repetition in range(1, 4):
        variants = ORDER if repetition % 2 else ORDER[::-1]
        for case in ('low', 'high'):
            for method in ('louvain', 'leiden'):
                for cores in (1, 4, 8):
                    pair = {name: one(name, case, method, cores,
                                      repetition) for name in variants}
                    a, b = pair['baseline'], pair['candidate']
                    if (a['labels_sha256'] != b['labels_sha256'] or
                            a['communities'] != b['communities'] or
                            a['modularity'] != b['modularity']):
                        raise RuntimeError(
                            f'Partition mismatch: {case} {method} '
                            f'cpu{cores} repeat {repetition}')
                    print(json.dumps({'case': case, 'method': method,
                        'cores': cores, 'repetition': repetition,
                        'baseline_seconds': a['seconds'],
                        'candidate_seconds': b['seconds'],
                        'exact_partition_parity': True}), flush=True)
    print('THREADPOOL_PAIR_GATE_PASS', flush=True)


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print(f'THREADPOOL_PAIR_GATE_FAIL: {error}', file=sys.stderr)
        raise
