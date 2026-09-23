#!/usr/bin/env python3
import json
import sys
import pathlib

def fmt_bytes(b):
    if b is None: return "—"
    b = float(b)
    for unit in ["B", "KB", "MB", "GB"]:
        if b < 1024: return f"{b:.1f} {unit}"
        b /= 1024
    return f"{b:.1f} GB"

def fmt(v, dec=0):
    if v is None: return "—"
    return f"{float(v):,.{dec}f}"

bm_path = pathlib.Path(sys.argv[1])
data    = json.loads(bm_path.read_text())
res     = data.get("results", {})
env     = data.get("metadata", {}).get("env", {})
benchmark_timing = data.get("measurements", {}).get("timings", {}).get("benchmark", {})

PAGES        = ["home", "catalog", "component", "catalog_tab", "page_n"]
PAGES_VITALS = ["home", "catalog", "component", "catalog_tab", "page_n"]

def gv(key, field, sub="mean"):
    return (res.get(key) or {}).get(field, {}).get(sub)

def net(page, ml, sub="mean"):  return gv(f"net_{page}_{ml}",  "call_count",        sub)
def sz(page,  ml, sub="mean"):  return gv(f"size_{page}_{ml}", "bytes_transferred",  sub)
def vital(key):                  return gv(key, "locust_requests_avg_response_time")

# Dynamically discover all MIME labels present across net_* keys.
PAGES_BY_LEN = sorted(PAGES, key=len, reverse=True)
mime_labels = set()
for k in res:
    if k.startswith("net_"):
        suffix = k[4:]
        for p in PAGES_BY_LEN:
            if suffix.startswith(p + "_"):
                mime_labels.add(suffix[len(p) + 1:])
                break
mime_labels = sorted(mime_labels)

# vitals:*/heap_used_mb fires exactly once per page load
def page_iterations(page): return gv(f"vitals_{page}_heap_used_mb", "call_count")

page_iters = {p: page_iterations(p) for p in PAGES}
total_iters = page_iters.get("home")

lines = []

# ── Header ────────────────────────────────────────────────────────────────────
lines += [
    "# UI Browser Metrics Report\n",
    "## Test Configuration\n",
    "| Field | Value |",
    "|-------|-------|",
    f"| Scenario       | `{env.get('SCENARIO', 'ui-browser-metrics')}` |",
    f"| Started        | {benchmark_timing.get('started') or data.get('started', '—')} |",
    f"| Ended          | {benchmark_timing.get('ended') or data.get('ended', '—')} |",
    f"| Users          | {env.get('USERS', '—')} |",
    f"| Spawn Rate     | {env.get('SPAWN_RATE', '—')}/s |",
    f"| Workers        | {env.get('WORKERS', '—')} |",
    f"| Duration       | {env.get('DURATION', '—')} |",
    f"| Total Iterations | {fmt(total_iters)} |",
    "",
]

# ── Web Vitals by page (heap + long tasks) ────────────────────────────────────
lines += [
    "## Web Vitals by Page\n",
    f"### LCP for Home Page is {fmt(vital('vitals_home_lcp_ms'), 0)} ms\n",
    "| Page | Heap (MB) | Long Task Count | Long Task Duration (ms) |",
    "|------|-----------|------------------|--------------------------|",
]
for p in PAGES_VITALS:
    lines.append(
        f"| {p} | {fmt(vital(f'vitals_{p}_heap_used_mb'))}"
        f" | {fmt(vital(f'vitals_{p}_long_task_count'), 1)}"
        f" | {fmt(vital(f'vitals_{p}_long_task_ms'))} |"
    )
lines.append("")

# ── Network calls & data transferred per page (per page load) ────────────────
mime_display = [ml.replace("_", "/", 1) for ml in mime_labels]
col_sep = " | ".join(["------"] * len(mime_labels))

lines += [
    "## Network Calls & Data Transferred per Page Load\n",
    "| Page | " + " | ".join(mime_display) + " | **Total** |",
    "|------|" + col_sep + "| --------- |",
]
for p in PAGES:
    iters = page_iters.get(p)
    vals, total_calls, total_bytes = [], 0, 0
    for ml in mime_labels:
        calls = net(p, ml)
        nbytes = sz(p, ml)
        per_load = float(calls) / float(iters) if calls is not None and iters else None
        if per_load is None and nbytes is None:
            vals.append("—")
        else:
            calls_str = fmt(per_load) if per_load is not None else "—"
            bytes_str = fmt_bytes(nbytes) if nbytes is not None else "—"
            vals.append(f"{calls_str} ({bytes_str})")
        if per_load: total_calls += per_load
        if nbytes: total_bytes += float(nbytes)
    total_str = f"{fmt(total_calls)} ({fmt_bytes(total_bytes)})" if (total_calls or total_bytes) else "—"
    lines.append(f"| {p} | " + " | ".join(vals) + f" | **{total_str}** |")
lines.append("")

out_path = bm_path.parent / "ui-browser-metrics-report.md"
out_path.write_text("\n".join(lines))
print(f"Report written → {out_path}")
