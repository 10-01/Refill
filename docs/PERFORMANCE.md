# Performance

Refill is idle most of the time. Provider work runs at utility quality of service on a queue capped at three concurrent operations. The menu and all visible state updates stay on the main thread.

## Current measurement

Measured on 2026-09-02 on an Apple silicon Mac with three Claude accounts, two Codex accounts, and one Grok account:

| Check | Before | Current |
|---|---:|---:|
| Live six-account `--probe` wall time | 7.13 s | 2.25 s |
| Live probe user CPU time | 0.21 s | 0.18 s |
| Live probe system CPU time | 0.11 s | 0.09 s |
| Installed app idle CPU | 0.0% | 0.0% |
| Installed app resident memory after refresh | not recorded | 64 MB |

The 65% wall-time reduction comes from sending Grok's usage request as soon as its terminal is ready and canceling its retry timer after a complete response. Provider and network timing varies, so these values are a regression baseline rather than a general guarantee.

The diagnostic probe reads accounts sequentially to keep its output deterministic. The menu-bar app uses bounded concurrency, so its six-account refresh does not wait on each provider in series.

## Reproduce

Build an optimized app, then run:

```sh
make build
/usr/bin/time -lp build/Refill.app/Contents/MacOS/Refill --probe >/tmp/refill-probe.json
```

The probe contacts configured providers. Its JSON contains account display names and quota values, so inspect the file before sharing it.

For idle CPU and resident memory:

```sh
pid="$(pgrep -x Refill | head -1)"
ps -o pid=,%cpu=,rss=,etime=,command= -p "$pid"
```
