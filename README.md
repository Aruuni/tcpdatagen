# SAGE / ATHENA TCP Experiment

This repo contains a simple TCP **server** (`sage.cc` / `athena.cc`) and **client** (`client.c`) used to run congestion-control experiments and log per-interval TCP metrics. A Python script (`plot.py`) turns the whitespace-separated logs into a multi‑page PDF of metrics, needed for RL training.

---

## Contents

- `sage.cc` and `athena.cc` — TCP servers that accept a single client, stream data, and periodically read TCP kernel stats to a log.
- `client.c` — connects to the server and reads until EOF.
- `define.h`, `flow.cc`, `common.h` — shared types, helpers, and metric containers.
- `plot.py` — reads the numeric log and plots pages for gradients, RTT, throughput, inflight, loss, and more.
- `Makefile` — build rules.

> **Tip:** `sage.cc` and `athena.cc` are very similar; both expose the same CLI shape and the same logging mechanics. Use either depending on the experiment you’re running.

---

## Build

```bash
make
```
This should produce binaries like `sage`/`athena` (server) and `client` (client).

If your system uses a different compiler or needs extra include/library paths, edit the `Makefile` accordingly.

---

## Run

### 1) Start the server

Both `sage` and `athena` expect **11 arguments** after the program name:

```
./sage  <port> <flow_interval_csv> <env_bw_mbps> <scheme> <delay_ms> <log_file_prefix> <duration_s> <loss_rate> <timestamp_start> <bw2_mbps> <bw2_flip_period_s>
```

- `port` — base port to listen on (the code currently configures a single flow).
- `flow_interval_csv` — e.g., `3,5,7` (used to decide when new flows join).
- `env_bw_mbps` / `bw2_mbps` and `bw2_flip_period_s` — capacity and an optional second capacity to toggle to every *N* seconds.
- `scheme` — desired TCP congestion control (e.g., `cubic`, `bbr`, or an in‑kernel module name).
- `delay_ms` — one‑way delay to use in the experiment’s logic.
- `log_file_prefix` — log is written to `<prefix>.txt`.
- `duration_s` — stop sending after this many seconds (0 = run until manually stopped).
- `loss_rate` — emulated loss to factor into reward/metrics.
- `timestamp_start` — base timestamp string (used for trace alignment).

Example:

```bash
# Server on port 5001, single flow interval list, env bw 50 Mbps, CUBIC, 20 ms OWD,
# write logs to out.txt for 60 s, with 0.0 loss, timestamp "0",
# and no second bandwidth (set bw2=bw, period large).
./sage 5001 10 50 cubic 20 out 60 0.0 0 50 99999
```

### 2) Run the client

```
./client <server_ip> <flowid> <server_port>
```

Example:

```bash
./client 127.0.0.1 1 5001
```

The client sends a small request header and then simply receives until the server closes the connection.

---

## What gets logged

The server samples TCP kernel stats at a fixed **report period** and writes a whitespace‑separated row per sample to `<log_file_prefix>.txt`. Columns include:

- **Base TCP:** RTT (×100), RTO (×100), ATO (×100), pacing & delivery rate, `snd_ssthresh`, `ca_state`.
- **Windowed metrics:** short/medium/long windows for RTT, throughput, gradient (RTT rate), RTT variance, inflight, loss — each as avg/min/max.
- **Tail metrics:** derived rates, queue‑delay proxy, delivered minus loss, reward, etc.

See “Plotting” below for the exact column map used by `plot.py`.

---

## Plotting

Convert a log into a PDF of figures:

```bash
python3 plot.py out.txt --out out_all_metrics.pdf
```

The script writes a 10+ page PDF covering gradients & reward, base TCP variables, throughput windows, RTT windows, inflight, loss, and derived tail metrics.

---

## Socket options (the “get sock opts” bit)

This project uses both **`setsockopt`** and **`getsockopt`** to configure and query TCP. Here’s what they do and why they matter.

### On the server sockets

- **`TCP_CONGESTION` (level: `IPPROTO_TCP`)**
  - **When:** after `socket()` and before `listen()`.
  - **Why:** selects the TCP congestion control algorithm for the connection, e.g. `cubic`, `bbr`, or a custom module.
  - **How:** `setsockopt(sock, IPPROTO_TCP, TCP_CONGESTION, scheme, strlen(scheme))`

- **`TCP_INFO` via `getsockopt` (level: `SOL_TCP`)**
  - **When:** periodically in the control thread.
  - **Why:** reads kernel TCP statistics such as `bytes_acked`, `delivered`, `lost`, `min_rtt`, `snd_cwnd`, `pacing_rate`, and more. These drive all the rolling‑window metrics and the reward/gradient logic.
  - **How:** `getsockopt(conn, SOL_TCP, TCP_INFO, &info, &len)`

  The struct fields are accumulated into short/medium/long windows to compute **throughput**, **RTT gradients**, **inflight**, **loss**, etc., and then formatted into the log row.


## Column map used by `plot.py`

`plot.py` assumes the server prints a row with the following indices (subset shown here; see the script for the complete map):

```
0: time_on_trace_sec
1: max_tmp
2..7: base TCP: rtt(×100 ms), rttvar, rto(×100 ms), ato(×100 ms), pacing_rate_norm, delivery_rate_norm
8: snd_ssthresh
9: ca_state
10..18: rtt_s/m/l (avg,min,max)
19..27: thr_s/m/l (avg,min,max)
28..36: rtt_rate_s/m/l (avg,min,max)
37..45: rtt_var_s/m/l (avg,min,max)
46..54: inflight_s/m/l (avg,min,max)
55..63: lost_s/m/l (avg,min,max)
64..76: tail metrics (delivered−loss, time_delta_norm, rtt_rate_scalar, loss_norm, acked_rate_norm, dr_w*, queue_delay_proxy, cwnd_*, reward)
```

If your log’s layout changes, update `COLS` in `plot.py` accordingly.

---

## Troubleshooting

- **`TCP congestion doesn't exist`** — your `scheme` name doesn’t match an installed kernel algorithm. Check `sysctl net.ipv4.tcp_available_congestion_control`.

---