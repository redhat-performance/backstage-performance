#!/usr/bin/env python3
"""Upload benchmark.json results to AWS OpenSearch for time-series visualization.

Extracts key performance metrics from benchmark.json files and indexes them
into OpenSearch with proper timestamps for Kibana/Grafana dashboards.

Usage:
    python upload_benchmark.py benchmark.json [benchmark2.json ...]
    python upload_benchmark.py --dir /path/to/artifacts/

Environment variables:
    OPENSEARCH_URL      - OpenSearch endpoint (e.g. https://...es.amazonaws.com)
    OPENSEARCH_USER     - Master username (default: admin)
    OPENSEARCH_PASSWORD - Master password
    OPENSEARCH_INDEX    - Index name (default: rhdh-performance.default)
"""

import argparse
import hashlib
import json
import logging
import os
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

from opensearchpy import OpenSearch, helpers

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
)
log = logging.getLogger(__name__)

# ---------------------------------------------------------------------------

INDEX_NAME = os.environ.get("OPENSEARCH_INDEX", "rhdh-performance.default")

INDEX_MAPPING = {
    "mappings": {
        "properties": {
            "@timestamp": {"type": "date"},
            "test_name": {"type": "keyword"},
            "scenario_name": {"type": "keyword"},
            "scenario_version": {"type": "integer"},
            "image_version": {"type": "keyword"},
            "image_name": {"type": "keyword"},
            "git_commit": {"type": "keyword"},
            "build_id": {"type": "keyword"},
            "job_name": {"type": "keyword"},
            "prow_job_id": {"type": "keyword"},
            "cluster_context": {"type": "keyword"},
            "compute_node_flavor": {"type": "keyword"},
            "compute_node_count": {"type": "integer"},
            "rhdh_replicas": {"type": "integer"},
            "rhdh_db_replicas": {"type": "integer"},
            "rhdh_db_storage": {"type": "keyword"},
            "rhdh_keycloak_replicas": {"type": "integer"},
            "rhdh_cpu_limits": {"type": "keyword"},
            "rhdh_cpu_requests": {"type": "keyword"},
            "rhdh_memory_limits": {"type": "keyword"},
            "rhdh_memory_requests": {"type": "keyword"},
            "users": {"type": "integer"},
            "workers": {"type": "integer"},
            "spawn_rate": {"type": "integer"},
            "duration": {"type": "keyword"},
            "backstage_user_count": {"type": "integer"},
            "group_count": {"type": "integer"},
            "component_count": {"type": "integer"},
            "api_count": {"type": "integer"},
            "page_n_count": {"type": "integer"},
            "catalog_tab_n_count": {"type": "integer"},
            "rbac_policy": {"type": "keyword"},
            "rbac_policy_size": {"type": "integer"},
            "pre_load_db": {"type": "keyword"},
            "wait_for_search_index": {"type": "keyword"},
            "scalability_iteration": {"type": "integer"},
            "measurements": {"type": "object", "dynamic": True},
            "results": {"type": "object", "dynamic": True},
            "timings": {
                "properties": {
                    "benchmark_duration": {"type": "float"},
                    "deploy_duration": {"type": "float"},
                    "populate_duration": {"type": "float"},
                    "populate_catalog_duration": {"type": "float"},
                }
            },
        }
    },
    "settings": {
        "number_of_shards": 1,
        "number_of_replicas": 1,
        "index.mapping.total_fields.limit": 5000,
    },
}


def connect_opensearch() -> OpenSearch:
    url = os.environ.get("OPENSEARCH_URL")
    if not url:
        log.error("OPENSEARCH_URL environment variable is required")
        sys.exit(1)

    user = os.environ.get("OPENSEARCH_USER", "admin")
    password = os.environ.get("OPENSEARCH_PASSWORD")
    if not password:
        log.error("OPENSEARCH_PASSWORD environment variable is required")
        sys.exit(1)

    url = url.rstrip("/")
    use_ssl = url.startswith("https")
    host = url.replace("https://", "").replace("http://", "")
    port = 443 if use_ssl else 9200
    if ":" in host:
        host, port_str = host.rsplit(":", 1)
        port = int(port_str)

    client = OpenSearch(
        hosts=[{"host": host, "port": port}],
        http_auth=(user, password),
        use_ssl=use_ssl,
        verify_certs=True,
        ssl_show_warn=False,
    )

    info = client.info()
    log.info(
        "Connected to OpenSearch %s at %s",
        info["version"]["number"],
        url,
    )
    return client


def ensure_index(client: OpenSearch) -> None:
    if not client.indices.exists(index=INDEX_NAME):
        client.indices.create(index=INDEX_NAME, body=INDEX_MAPPING)
        log.info("Created index '%s'", INDEX_NAME)
    else:
        log.info("Index '%s' already exists", INDEX_NAME)


def safe_int(val, default=None):
    if val is None:
        return default
    try:
        return int(val)
    except (ValueError, TypeError):
        return default


def safe_float(val, default=None):
    if val is None:
        return default
    try:
        return float(val)
    except (ValueError, TypeError):
        return default


def nested_get(data: dict, *keys, default=None):
    """Safely traverse nested dicts."""
    current = data
    for key in keys:
        if not isinstance(current, dict):
            return default
        current = current.get(key)
        if current is None:
            return default
    return current


def parse_timestamp(raw: str) -> str:
    """Normalize timestamp strings to ISO-8601 for OpenSearch."""
    if not raw:
        return None
    raw = raw.replace(",", ".")
    try:
        dt = datetime.fromisoformat(raw)
        return dt.isoformat()
    except ValueError:
        return raw


def compute_doc_id(benchmark: dict, filepath: str) -> str:
    """Deterministic document ID so re-uploads are idempotent."""
    started = benchmark.get("started", "")
    name = benchmark.get("name", "")
    scenario = nested_get(benchmark, "metadata", "scenario", "name", default="")
    iteration = str(nested_get(benchmark, "metadata", "scalability", "iteration", default=""))
    env_users = str(nested_get(benchmark, "metadata", "env", "USERS", default=""))
    key = f"{started}|{name}|{scenario}|{iteration}|{env_users}|{filepath}"
    return hashlib.sha256(key.encode()).hexdigest()[:20]


_SANITIZE_RE = re.compile(r"[^a-zA-Z0-9]+")

MEASUREMENTS_SKIP_KEYS = {"timings"}


def _sanitize_field_name(name: str) -> str:
    """Replace any non-alphanumeric characters with underscores and strip edges."""
    return _SANITIZE_RE.sub("_", name).strip("_").lower()


_KEEP_STATS = {"max", "min", "mean", "median", "percentile95", "percentile99"}


def _extract_stats(data: dict) -> dict:
    """Copy selected numeric stats from a stats dict."""
    return {k: v for k, v in data.items() if k in _KEEP_STATS and isinstance(v, (int, float))}


def _extract_measurements(meas: dict) -> dict:
    """Extract all measurements preserving the benchmark JSON structure."""
    out = {}
    for json_key, data in meas.items():
        if json_key in MEASUREMENTS_SKIP_KEYS or not isinstance(data, dict):
            continue
        name = _sanitize_field_name(json_key)
        first_val = next(iter(data.values()), None)
        if isinstance(first_val, dict):
            out[name] = {
                sub_key: _extract_stats(sub_data)
                for sub_key, sub_data in data.items()
                if isinstance(sub_data, dict)
            }
        else:
            out[name] = _extract_stats(data)
    return out


def _extract_results(results: dict) -> dict:
    """Extract all results preserving the benchmark JSON structure."""
    out = {}
    for req_name, req_data in results.items():
        if not isinstance(req_data, dict):
            continue
        name = _sanitize_field_name(req_name)
        first_val = next(iter(req_data.values()), None)
        if isinstance(first_val, dict):
            out[name] = {
                metric_key.replace("locust_requests_", ""): _extract_stats(metric_data)
                for metric_key, metric_data in req_data.items()
                if isinstance(metric_data, dict)
            }
        else:
            out[name] = _extract_stats(req_data)
    return out


def transform_benchmark(benchmark: dict, filepath: str) -> dict:
    """Transform a benchmark.json into a flat OpenSearch document."""
    meta = benchmark.get("metadata", {})
    env = meta.get("env", {})
    meas = benchmark.get("measurements", {})
    results = benchmark.get("results", {})
    timings = nested_get(meas, "timings", default={})

    started = parse_timestamp(benchmark.get("started"))
    if not started:
        started = parse_timestamp(nested_get(timings, "benchmark", "started"))

    doc = {
        "@timestamp": started,
        "test_name": benchmark.get("name"),
        "scenario_name": nested_get(meta, "scenario", "name"),
        "scenario_version": safe_int(nested_get(meta, "scenario", "version")),
        "image_version": nested_get(meta, "image", "version"),
        "image_name": nested_get(meta, "image", "name"),
        "git_commit": nested_get(meta, "git", "last_commit", "hash"),
        "build_id": env.get("BUILD_ID"),
        "job_name": env.get("JOB_NAME"),
        "prow_job_id": env.get("PROW_JOB_ID"),
        "cluster_context": nested_get(meta, "cluster", "context"),
        "compute_node_flavor": nested_get(meta, "cluster", "compute-nodes", "flavor"),
        "compute_node_count": safe_int(nested_get(meta, "cluster", "compute-nodes", "count")),
        "rhdh_replicas": safe_int(env.get("RHDH_DEPLOYMENT_REPLICAS")),
        "rhdh_db_replicas": safe_int(env.get("RHDH_DB_REPLICAS")),
        "rhdh_db_storage": env.get("RHDH_DB_STORAGE"),
        "rhdh_keycloak_replicas": safe_int(env.get("RHDH_KEYCLOAK_REPLICAS")),
        "rhdh_cpu_limits": env.get("RHDH_RESOURCES_CPU_LIMITS"),
        "rhdh_cpu_requests": env.get("RHDH_RESOURCES_CPU_REQUESTS"),
        "rhdh_memory_limits": env.get("RHDH_RESOURCES_MEMORY_LIMITS"),
        "rhdh_memory_requests": env.get("RHDH_RESOURCES_MEMORY_REQUESTS"),
        "users": safe_int(env.get("USERS")),
        "workers": safe_int(env.get("WORKERS")),
        "spawn_rate": safe_int(env.get("SPAWN_RATE")),
        "duration": env.get("DURATION"),
        "backstage_user_count": safe_int(env.get("BACKSTAGE_USER_COUNT")),
        "group_count": safe_int(env.get("GROUP_COUNT")),
        "component_count": safe_int(env.get("COMPONENT_COUNT")),
        "api_count": safe_int(env.get("API_COUNT")),
        "page_n_count": safe_int(env.get("PAGE_N_COUNT")),
        "catalog_tab_n_count": safe_int(env.get("CATALOG_TAB_N_COUNT")),
        "rbac_policy": env.get("RBAC_POLICY"),
        "rbac_policy_size": safe_int(env.get("RBAC_POLICY_SIZE")),
        "pre_load_db": env.get("PRE_LOAD_DB"),
        "wait_for_search_index": env.get("WAIT_FOR_SEARCH_INDEX"),
        "scalability_iteration": safe_int(nested_get(meta, "scalability", "iteration")),
    }

    doc["measurements"] = _extract_measurements(meas)
    doc["results"] = _extract_results(results)

    doc["timings"] = {
        "benchmark_duration": safe_float(nested_get(timings, "benchmark", "duration")),
        "deploy_duration": safe_float(nested_get(timings, "deploy", "duration")),
        "populate_duration": safe_float(nested_get(timings, "populate", "duration")),
        "populate_catalog_duration": safe_float(nested_get(timings, "populate_catalog", "duration")),
    }

    return doc


def find_benchmark_files(paths: list[str]) -> list[Path]:
    """Resolve file paths and directories into a list of benchmark.json files."""
    files = []
    for p in paths:
        path = Path(p)
        if path.is_file() and path.name == "benchmark.json":
            files.append(path)
        elif path.is_file() and path.suffix == ".json":
            files.append(path)
        elif path.is_dir():
            files.extend(sorted(path.rglob("benchmark.json")))
        else:
            log.warning("Skipping %s (not a json file or directory)", p)
    return files


def upload_documents(client: OpenSearch, docs: list[dict]) -> None:
    actions = [
        {
            "_index": INDEX_NAME,
            "_id": doc.pop("_id"),
            "_source": doc,
        }
        for doc in docs
    ]

    success, errors = helpers.bulk(client, actions, raise_on_error=False)
    log.info("Indexed %d documents", success)
    if errors:
        for err in errors:
            log.error("Bulk error: %s", json.dumps(err, indent=2))


def main():
    parser = argparse.ArgumentParser(
        description="Upload benchmark.json results to OpenSearch"
    )
    parser.add_argument(
        "paths",
        nargs="+",
        help="benchmark.json file(s) or directory containing them",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Parse and print documents without uploading",
    )
    args = parser.parse_args()

    files = find_benchmark_files(args.paths)
    if not files:
        log.error("No benchmark.json files found in the provided paths")
        sys.exit(1)

    log.info("Found %d benchmark file(s)", len(files))

    docs = []
    for filepath in files:
        log.info("Processing %s", filepath)
        with open(filepath) as f:
            benchmark = json.load(f)
        doc = transform_benchmark(benchmark, str(filepath))
        doc["_id"] = compute_doc_id(benchmark, str(filepath))
        docs.append(doc)

    if args.dry_run:
        for doc in docs:
            print(json.dumps(doc, indent=2, default=str))
        log.info("Dry run complete — %d document(s) parsed", len(docs))
        return

    client = connect_opensearch()
    ensure_index(client)
    upload_documents(client, docs)


if __name__ == "__main__":
    main()
