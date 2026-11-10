#!/usr/bin/env python3
"""Generate a Markdown UI browser metrics report from benchmark.json.

    python3 ci-scripts/generate-ui-browser-report.py benchmark.json

    python3 ci-scripts/generate-ui-browser-report.py benchmark.json \\
        --compare-to other/benchmark.json

With --compare-to, each metric column is followed by that run's value and the
percentage change of that run relative to this run: (other - this) / this.
A second header row gives the RHDH version for each value column. Omit
--compare-to, or pass an empty value, to keep the single-run report unchanged.
"""

import argparse
import json
import pathlib
import sys

PAGES = ["home", "catalog", "component", "catalog_tab_n", "page_n", "home_warm", "catalog_warm", "component_warm", "catalog_tab_n_warm", "page_n_warm"]
PAGES_VITALS = ["home", "catalog", "component", "catalog_tab_n", "page_n", "home_warm", "catalog_warm", "component_warm", "catalog_tab_n_warm", "page_n_warm"]
PAGES_BY_LEN = sorted(PAGES, key=len, reverse=True)

VITALS = (
    ("Heap (MB)", "_heap_used_mb", 0),
    ("Long Task Count", "_long_task_count", 1),
    ("Long Task Duration (ms)", "_long_task_ms", 0),
)


def fmt_bytes(b):
    if b is None:
        return "—"
    b = float(b)
    for unit in ["B", "KB", "MB", "GB"]:
        if b < 1024:
            return f"{b:.1f} {unit}"
        b /= 1024
    return f"{b:.1f} GB"


def fmt(v, dec=0):
    if v is None:
        return "—"
    return f"{float(v):,.{dec}f}"


def fmt_pct(main, other):
    """Percent change of other relative to main. None on either side is unknown."""
    if main is None or other is None:
        return "—"
    main_f = float(main)
    other_f = float(other)
    if main_f == 0:
        return "+0%" if other_f == 0 else "—"
    rounded = int(round((other_f - main_f) / main_f * 100))
    return f"{rounded:+d}%"


def version_cell(version):
    return f"`{version}`" if version else "—"


def as_number(value):
    if value is None or value == "—":
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def pair_cell(calls, nbytes):
    if calls is None and nbytes is None:
        return "—"
    calls_str = fmt(calls) if calls is not None else "—"
    bytes_str = fmt_bytes(nbytes) if nbytes is not None else "—"
    return f"{calls_str} ({bytes_str})"


def pair_pct(calls_main, bytes_main, calls_other, bytes_other):
    call_pct = fmt_pct(calls_main, calls_other)
    byte_pct = fmt_pct(bytes_main, bytes_other)
    if call_pct == "—" and byte_pct == "—":
        return "—"
    return f"{call_pct} ({byte_pct})"


def metric_cells(main, other, render, comparing):
    cells = [render(main)]
    if comparing:
        cells.append(render(other))
        cells.append(fmt_pct(main, other))
    return cells


def row(cells):
    return "| " + " | ".join(cells) + " |"


def comparison_header(names, main_version, other_version, leading="Page"):
    """Metric names on the first header row, RHDH versions on the next row."""
    titles = [leading] if leading else []
    versions = ["RHDH Version"] if leading else []
    for name in names:
        titles.extend((name, name, "% diff"))
        versions.extend((f"**{main_version}**", f"**{other_version}**", ""))
    separator = "|" + "|".join(["------"] * len(titles)) + "|"
    return [row(titles), separator, row(versions)]


class Run:
    def __init__(self, path):
        self.path = pathlib.Path(path)
        self.data = json.loads(self.path.read_text())
        self.res = self.data.get("results", {})
        self.env = self.data.get("metadata", {}).get("env", {})
        self.timing = self.data.get("measurements", {}).get("timings", {}).get("benchmark", {})
        self.page_iters = {page: self.page_iterations(page) for page in PAGES}

    def gv(self, key, field, sub="mean"):
        return (self.res.get(key) or {}).get(field, {}).get(sub)

    def net(self, page, ml, sub="mean"):
        return self.gv(f"net_{page}_{ml}", "call_count", sub)

    def sz(self, page, ml, sub="mean"):
        return self.gv(f"size_{page}_{ml}", "bytes_transferred", sub)

    def vital(self, key):
        return self.gv(key, "locust_requests_avg_response_time")

    def page_iterations(self, page):
        return self.gv(f"vitals_{page}_heap_used_mb", "call_count")

    def mime_labels(self):
        found = set()
        for key in self.res:
            if not key.startswith("net_"):
                continue
            suffix = key[4:]
            for page in PAGES_BY_LEN:
                if suffix.startswith(page + "_"):
                    found.add(suffix[len(page) + 1:])
                    break
        return found

    def page_network(self, page, mime_labels):
        iters = self.page_iters.get(page)
        per_loads, sizes = [], []
        total_calls, total_bytes = 0, 0
        for ml in mime_labels:
            calls = self.net(page, ml)
            nbytes = self.sz(page, ml)
            if calls is not None and iters:
                per_load = float(calls) / float(iters)
            else:
                per_load = None
            per_loads.append(per_load)
            sizes.append(nbytes)
            if per_load:
                total_calls += per_load
            if nbytes:
                total_bytes += float(nbytes)
        if not total_calls and not total_bytes:
            total = (None, None)
        else:
            total = (total_calls or 0, total_bytes or 0)
        return per_loads, sizes, total

    def rhdh_version(self):
        """Last tag in metadata.image["konflux.additional-tags"], e.g. '2.1-131'."""
        image = (self.data.get("metadata") or {}).get("image") or {}
        tags = image.get("konflux.additional-tags")
        if isinstance(tags, str):
            parts = [part.strip() for part in tags.split(",") if part.strip()]
            return parts[-1] if parts else None
        if isinstance(tags, list) and tags:
            last = str(tags[-1]).strip()
            return last or None
        return None

    def started(self):
        return self.timing.get("started") or self.data.get("started", "—")

    def ended(self):
        return self.timing.get("ended") or self.data.get("ended", "—")


def parse_args(argv):
    parser = argparse.ArgumentParser(
        description="Generate a Markdown UI browser metrics report from benchmark.json.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument("benchmark", type=pathlib.Path, help="Primary benchmark.json (this run)")
    parser.add_argument(
        "--compare-to",
        default="",
        metavar="BENCHMARK_JSON",
        help="Optional second benchmark.json. Each metric column is repeated for that run, with the RHDH version on a second header row, plus a %% diff column. An empty value leaves the single-run report unchanged.",
    )
    return parser.parse_args(argv)


def load_compare(compare_to):
    text = (compare_to or "").strip()
    if not text:
        return None
    path = pathlib.Path(text)
    if not path.is_file():
        print(f"Compare benchmark not found: {path}", file=sys.stderr)
        sys.exit(1)
    return Run(path)


def config_rows(main, other, comparing):
    # Label padding keeps the single-run configuration table aligned.
    rows = [
        ("Scenario      ", f"`{main.env.get('SCENARIO', 'ui-browser-metrics')}`", f"`{other.env.get('SCENARIO', 'ui-browser-metrics')}`" if other else None, None, None),
        ("Started       ", main.started(), other.started() if other else None, None, None),
        ("Ended         ", main.ended(), other.ended() if other else None, None, None),
        ("Users         ", main.env.get("USERS", "—"), other.env.get("USERS", "—") if other else None, as_number(main.env.get("USERS")), as_number(other.env.get("USERS")) if other else None),
        ("Spawn Rate    ", f"{main.env.get('SPAWN_RATE', '—')}/s", f"{other.env.get('SPAWN_RATE', '—')}/s" if other else None, as_number(main.env.get("SPAWN_RATE")), as_number(other.env.get("SPAWN_RATE")) if other else None),
        ("Workers       ", main.env.get("WORKERS", "—"), other.env.get("WORKERS", "—") if other else None, as_number(main.env.get("WORKERS")), as_number(other.env.get("WORKERS")) if other else None),
        ("Duration      ", main.env.get("DURATION", "—"), other.env.get("DURATION", "—") if other else None, None, None),
        ("Total Iterations", fmt(main.page_iters.get("home")), fmt(other.page_iters.get("home")) if other else None, main.page_iters.get("home"), other.page_iters.get("home") if other else None),
    ]
    lines = []
    if not comparing:
        lines.append(f"| RHDH Version   | {version_cell(main.rhdh_version())} |")
    for label, value, other_value, main_num, other_num in rows:
        if comparing:
            lines.append(f"| {label} | {value} | {other_value} | {fmt_pct(main_num, other_num)} |")
        else:
            lines.append(f"| {label} | {value} |")
    return lines


def build_report(main, other):
    comparing = other is not None
    main_version = main.rhdh_version() or "—"
    other_version = (other.rhdh_version() or "—") if other else None
    mime_labels = sorted(main.mime_labels() | (other.mime_labels() if other else set()))
    lines = ["# UI Browser Metrics Report\n"]
    if comparing:
        lines.append(
            f"Compared against `{other_version}` (`{other.path}`). "
            f"% diff is the change of `{other_version}` relative to `{main_version}`: "
            f"`({other_version} - {main_version}) / {main_version}`.\n"
        )

    if comparing:
        config_header = [
            "## Test Configuration\n",
            "| Field | Value | Value | % diff |",
            "|-------|-------|-------|--------|",
            f"| RHDH Version | **{main_version}** | **{other_version}** | |",
        ]
    else:
        config_header = [
            "## Test Configuration\n",
            "| Field | Value |",
            "|-------|-------|",
        ]
    lines += config_header
    lines += config_rows(main, other, comparing)
    lines.append("")

    lcp_main = main.vital("vitals_home_lcp_ms")
    lcp_other = other.vital("vitals_home_lcp_ms") if other else None
    lines.append("## Web Vitals by Page\n")
    if comparing:
        lines += [
            "### LCP for Home Page\n",
            *comparison_header(["LCP (ms)"], main_version, other_version, leading=None),
            row(metric_cells(lcp_main, lcp_other, lambda v: fmt(v, 0), True)),
            "",
        ]
    else:
        lines.append(f"### LCP for Home Page is {fmt(lcp_main, 0)} ms\n")

    if comparing:
        vital_names = [name for name, _suffix, _dec in VITALS]
        lines += comparison_header(vital_names, main_version, other_version)
    else:
        lines += [
            "| Page | Heap (MB) | Long Task Count | Long Task Duration (ms) |",
            "|------|-----------|------------------|--------------------------|",
        ]
    for page in PAGES_VITALS:
        cells = [page]
        for _name, suffix, dec in VITALS:
            key = f"vitals_{page}{suffix}"
            cells.extend(metric_cells(main.vital(key), other.vital(key) if other else None, lambda v, dec=dec: fmt(v, dec), comparing))
        lines.append(row(cells))
    lines.append("")

    mime_display = [ml.replace("_", "/", 1) for ml in mime_labels]
    lines.append("## Network Calls & Data Transferred per Page Load\n")
    if comparing:
        lines.append("Each cell is `calls (bytes transferred)`. The % diff column uses the same order.\n")
        lines += [
            *comparison_header(mime_display + ["**Total**"], main_version, other_version),
        ]
    else:
        col_sep = " | ".join(["------"] * len(mime_labels))
        lines += [
            "| Page | " + " | ".join(mime_display) + " | **Total** |",
            "|------|" + col_sep + "| --------- |",
        ]

    for page in PAGES:
        calls_m, bytes_m, (total_calls_m, total_bytes_m) = main.page_network(page, mime_labels)
        if other:
            calls_o, bytes_o, (total_calls_o, total_bytes_o) = other.page_network(page, mime_labels)
        else:
            calls_o = [None] * len(mime_labels)
            bytes_o = [None] * len(mime_labels)
            total_calls_o, total_bytes_o = None, None
        cells = [page]
        for i in range(len(mime_labels)):
            main_cell = pair_cell(calls_m[i], bytes_m[i])
            cells.append(main_cell)
            if comparing:
                cells.append(pair_cell(calls_o[i], bytes_o[i]))
                cells.append(pair_pct(calls_m[i], bytes_m[i], calls_o[i], bytes_o[i]))
        total_main = pair_cell(total_calls_m, total_bytes_m)
        if comparing:
            total_other = pair_cell(total_calls_o, total_bytes_o)
            total_pct = pair_pct(total_calls_m, total_bytes_m, total_calls_o, total_bytes_o)
            cells.extend((f"**{total_main}**", f"**{total_other}**", f"**{total_pct}**"))
        else:
            cells.append(f"**{total_main}**")
        lines.append(row(cells))
    lines.append("")
    return "\n".join(lines)


def main(argv=None):
    args = parse_args(sys.argv[1:] if argv is None else argv)
    if not args.benchmark.is_file():
        print(f"Benchmark not found: {args.benchmark}", file=sys.stderr)
        sys.exit(1)
    main_run = Run(args.benchmark)
    other = load_compare(args.compare_to)
    out_path = args.benchmark.parent / "ui-browser-metrics-report.md"
    out_path.write_text(build_report(main_run, other))
    print(f"Report written → {out_path}")


if __name__ == "__main__":
    main()
