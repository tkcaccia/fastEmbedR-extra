import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time

work = Path('/Users/silvanopiazza/Documents/Stefano/fastEmbedR-coil20-unified-pilot-20261105')
lock = work / 'runner.lock'
fd = os.open(lock, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
os.write(fd, str(os.getpid()).encode())
os.close(fd)
env = os.environ.copy()
env['R_LIBS'] = ':'.join([
    '/Users/silvanopiazza/Documents/Stefano/fastEmbedR-api-unified-v4-20261104/library',
    '/Users/silvanopiazza/Documents/Stefano/data/Rlib',
])
env['TMPDIR'] = str(work / 'tmp')
env['R_MAX_VSIZE'] = '16G'
env['VECLIB_MAXIMUM_THREADS'] = '1'
start = time.time()
with (work / 'run.log').open('wb') as log:
    proc = subprocess.Popen([
        '/Library/Frameworks/R.framework/Resources/bin/Rscript',
        '--vanilla', str(work / 'run.R')
    ], cwd=work, env=env, stdout=log, stderr=subprocess.STDOUT,
       start_new_session=True)
    try:
        code = proc.wait(timeout=1800)
        timed_out = False
    except subprocess.TimeoutExpired:
        os.killpg(proc.pid, signal.SIGTERM)
        try:
            proc.wait(timeout=15)
        except subprocess.TimeoutExpired:
            os.killpg(proc.pid, signal.SIGKILL)
            proc.wait()
        code = 124
        timed_out = True
record = {'status': 'completed' if code == 0 else 'failed',
          'exit_code': code, 'timed_out': timed_out,
          'elapsed_seconds': round(time.time()-start, 3),
          'package_sha256': '18902d45dd0a6d0278f52d3712e8892a38d6ec16516644fc9ee2114f5be92973',
          'input_sha256': '8e53030869bcfbc228edc06ca970e69b78ddae13fb188327e8899194d5841d66'}
(work / 'exit.json').write_text(json.dumps(record, indent=2) + '\n')
