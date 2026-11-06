import signal
import time

warned = False

def warning(number, _frame):
    global warned
    warned = True
    print('SCHEDULER_WARNING_RECEIVED', signal.Signals(number).name,
          flush=True)

signal.signal(signal.SIGUSR1, warning)
end = time.monotonic() + 95
while not warned and time.monotonic() < end:
    time.sleep(0.5)
if not warned:
    raise SystemExit('SCHEDULER_WARNING_MISSING')
print('SCHEDULER_SIGNAL_ROUTE_PASS', flush=True)
