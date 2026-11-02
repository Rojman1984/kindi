"""Start-up self-check of the decode speed: build the engine, time a short greedy decode, and when it is below a
threshold re-execute the whole process (os.execv) to draw a new decode state.

Why: on the MI25 (gfx900) the 27B's decode runs in one of two states, 15.1 or 13.9 tok/s, all of it in the
weight-streaming kernel (docs/MI25.md, "Known issue: two decode states"). The state is fixed PER PROCESS: rebuilding the
engine inside one process never changed it (36 builds in 9 processes, also with 1 GiB held to move the weights;
scripts/mi25-lab/selfcheck_probe.py). A new process draws again (about half are fast), so the check re-executes itself;
the container and the port stay, a supervisor such as llama-swap only sees a longer start. Output is never affected.

    KINDI_SELFCHECK_TPS    threshold in tokens/s (0 or unset: off). MI25 27B: 14.6 (between 14.2 and 15.15 measured).
    KINDI_SELFCHECK_TRIES  processes at most (default 5); the last one is kept whatever its speed.
    KINDI_SELFCHECK_STEPS  timed decode steps (default 48, after 4 warm-up steps; ~3 s).
    KINDI_SELFCHECK_TRY    set by the check itself: the number of this attempt.
"""
import os
import sys
import time


def _rate(eng, steps):
    import cupy as cp
    eng.reset()
    tok = 1000
    for pos in range(4):                    # warm-up: kernel loads, first launches
        tok = int(eng.step(tok, pos))
    cp.cuda.Device().synchronize()
    t0 = time.time()
    for pos in range(4, 4 + steps):
        tok = int(eng.step(tok, pos))
    cp.cuda.Device().synchronize()
    rate = steps / (time.time() - t0)
    eng.reset()
    return rate


def checked(make, log=print):
    """make() builds an engine. With KINDI_SELFCHECK_TPS set, time its decode; below the threshold, re-execute this
    process (new GPU state) unless the attempts are used up. Returns the engine."""
    eng = make()
    thr = float(os.environ.get("KINDI_SELFCHECK_TPS", "0") or 0)
    if thr <= 0:
        return eng
    tries = max(1, int(os.environ.get("KINDI_SELFCHECK_TRIES", "5")))
    steps = max(8, int(os.environ.get("KINDI_SELFCHECK_STEPS", "48")))
    attempt = int(os.environ.get("KINDI_SELFCHECK_TRY", "1"))
    rate = _rate(eng, steps)
    if rate >= thr:
        log("self-check %d/%d: decode %.2f tokens/s (threshold %.2f) - ok" % (attempt, tries, rate, thr))
        return eng
    if attempt >= tries:
        log("self-check %d/%d: decode %.2f tokens/s (threshold %.2f) - kept (last attempt)" % (attempt, tries, rate, thr))
        return eng
    log("self-check %d/%d: decode %.2f tokens/s (threshold %.2f) - restarting the process" % (attempt, tries, rate, thr))
    sys.stdout.flush(); sys.stderr.flush()
    os.environ["KINDI_SELFCHECK_TRY"] = str(attempt + 1)
    # the original command line (keeps "-m kindi"; sys.argv[0] would be .../__main__.py, which breaks the package imports)
    argv = list(getattr(sys, "orig_argv", None) or [sys.executable] + sys.argv)
    os.execv(sys.executable, [sys.executable] + argv[1:])
