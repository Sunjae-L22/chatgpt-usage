# Background refresh and resource check

Date: 2026-10-18 (Asia/Seoul). Apple Silicon Mac, app 0.3.0 build 8, Chrome extension 0.3.1.

## Live refresh

Both Claude and Gemini service tabs remained closed. Reloading the existing paired extension delivered both providers. With no manual refresh, the next five-minute alarm delivered both again; the native panel's observation times advanced by five minutes and reset countdowns remained visible. Opening the status popup does not trigger a provider request. The extension worker was observed inactive between checks and after the automatic refresh. No provider tabs or DevTools sessions were used during this check.

## Resource sample

The native detail window remained open. Sampled the native app and its process descendants using `ps` at approximately one-second intervals over 360.06 seconds (346 samples), including a local Codex refresh and a browser-provider alarm.

| Measurement | Result |
|---|---:|
| Native app CPU time over the sample | 0.48 seconds |
| Native app average CPU, percent of one core | 0.133% |
| Native app resident memory (RSS) | 93.27–93.67 MiB |
| App plus sampled Codex child: peak summed RSS | 207.41 MiB |
| Observed Codex child CPU time | 0.14 seconds |
| Samples containing a child process | 1 |

The sampled app did not show sustained CPU load or progressive memory growth. The brief higher process-tree memory value came from the local Codex quota probe, not a permanently running additional process. The browser worker was inactive during idle observations. Chrome's own Task Manager was used to confirm worker inactivity; a separate worker peak-memory figure was not captured, so the numbers above do **not** include Chrome's shared browser/network processes.

By code inspection and synthetic alarm tests, one successful browser refresh makes three provider GET requests (Gemini once, Claude organization plus usage) and two loopback POSTs. No full provider pages are loaded, no `setInterval` loop keeps the worker alive, and all requests are bounded. This is a request-count check, not a measurement of transferred bytes.

This six-minute sample covers one Mac/account combination. One-second sampling may miss short-lived child work; summed RSS can count shared pages more than once. It is not a long-duration memory-leak or battery-life test.
