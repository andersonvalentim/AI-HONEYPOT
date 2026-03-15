"""
Fluent Bit -> logz.io health monitor.
Queries Fluent Bit's metrics API every INTERVAL seconds and logs
pipeline status (records in, records out, errors, retries).
"""

import json
import os
import sys
import time
import urllib.request
import urllib.error

FLUENTBIT_METRICS = os.getenv("FLUENTBIT_METRICS_URL", "http://127.0.0.1:2020/api/v1/metrics")
FLUENTBIT_HEALTH = os.getenv("FLUENTBIT_HEALTH_URL", "http://127.0.0.1:2020/api/v1/health")
INTERVAL = int(os.getenv("HEALTHCHECK_INTERVAL", "60"))
STARTUP_GRACE = int(os.getenv("HEALTHCHECK_STARTUP_GRACE", "30"))

prev_output_records = 0
prev_output_errors = 0
consecutive_failures = 0


def log(level: str, msg: str) -> None:
    ts = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    prefix = {"OK": "[HEALTH OK]", "WARN": "[HEALTH WARN]", "FAIL": "[HEALTH FAIL]"}
    print(f"{ts} {prefix.get(level, '[HEALTH]')} {msg}", flush=True)


def check_health() -> bool:
    try:
        req = urllib.request.Request(FLUENTBIT_HEALTH, method="GET")
        with urllib.request.urlopen(req, timeout=5) as resp:
            return resp.status == 200
    except Exception:
        return False


def get_metrics() -> dict | None:
    try:
        req = urllib.request.Request(FLUENTBIT_METRICS, method="GET")
        with urllib.request.urlopen(req, timeout=5) as resp:
            return json.loads(resp.read().decode())
    except Exception:
        return None


def safe_int(val) -> int:
    return int(val) if isinstance(val, (int, float)) else 0


def extract_plugin_stats(plugin_data) -> dict:
    """Handle both dict and list formats from different Fluent Bit versions."""
    if isinstance(plugin_data, dict):
        return plugin_data
    if isinstance(plugin_data, list):
        merged = {}
        for item in plugin_data:
            if isinstance(item, dict):
                for k, v in item.items():
                    merged[k] = merged.get(k, 0) + safe_int(v) if isinstance(v, (int, float)) else v
        return merged
    return {}


def extract_output_stats(metrics: dict) -> dict:
    total_out = 0
    total_errors = 0
    total_retries = 0
    total_retries_failed = 0

    output = metrics.get("output", {})
    for plugin_name, plugin_data in output.items():
        stats = extract_plugin_stats(plugin_data)
        total_out += safe_int(stats.get("proc_records", stats.get("records", 0)))
        total_errors += safe_int(stats.get("errors", 0))
        total_retries += safe_int(stats.get("retries", 0))
        total_retries_failed += safe_int(stats.get("retries_failed", 0))

    total_in = 0
    input_data = metrics.get("input", {})
    for plugin_name, plugin_data in input_data.items():
        stats = extract_plugin_stats(plugin_data)
        total_in += safe_int(stats.get("records", 0))

    return {
        "records_in": total_in,
        "records_out": total_out,
        "errors": total_errors,
        "retries": total_retries,
        "retries_failed": total_retries_failed,
    }


def main() -> None:
    global prev_output_records, prev_output_errors, consecutive_failures

    log("OK", f"Health monitor starting (interval={INTERVAL}s, grace={STARTUP_GRACE}s)")
    time.sleep(STARTUP_GRACE)

    while True:
        healthy = check_health()

        if not healthy:
            consecutive_failures += 1
            log("FAIL", f"Fluent Bit health endpoint unreachable (failures={consecutive_failures})")
            if consecutive_failures >= 5:
                log("FAIL", ">>> ALERTA: Fluent Bit pode estar DOWN. Logs NAO estao sendo enviados ao logz.io! <<<")
            time.sleep(INTERVAL)
            continue

        metrics = get_metrics()
        if not metrics:
            log("WARN", "Fluent Bit running but metrics unavailable")
            time.sleep(INTERVAL)
            continue

        stats = extract_output_stats(metrics)
        new_records = stats["records_out"] - prev_output_records
        new_errors = stats["errors"] - prev_output_errors

        consecutive_failures = 0

        if stats["errors"] > 0 and new_errors > 0:
            log("WARN", f">>> ALERTA: {new_errors} novo(s) erro(s) de envio ao logz.io! "
                        f"Total: in={stats['records_in']} out={stats['records_out']} "
                        f"errors={stats['errors']} retries={stats['retries']} <<<")
        elif stats["retries_failed"] > 0:
            log("FAIL", f">>> ALERTA: {stats['retries_failed']} retentativa(s) falharam permanentemente. "
                        f"Verifique LOGZIO_TOKEN e conectividade! <<<")
        elif new_records > 0:
            log("OK", f"Pipeline ativo: +{new_records} registros enviados ao logz.io "
                      f"(total: in={stats['records_in']} out={stats['records_out']})")
        else:
            log("OK", f"Pipeline idle (sem novos eventos). "
                      f"Acumulado: in={stats['records_in']} out={stats['records_out']}")

        if stats["records_in"] > 0 and stats["records_out"] == 0 and stats["errors"] == 0:
            log("WARN", ">>> ALERTA: Eventos coletados mas NENHUM enviado. "
                        "Verifique se LOGZIO_TOKEN esta configurado! <<<")

        prev_output_records = stats["records_out"]
        prev_output_errors = stats["errors"]

        time.sleep(INTERVAL)


if __name__ == "__main__":
    main()
