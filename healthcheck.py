"""
Audit monitor for the honeypot log pipeline.
Tracks whether events are being collected, forwarded to logz.io,
and writes a structured audit trail to /var/log/opencanary/audit.log.
"""

import json
import os
import ssl
import time
import urllib.request
import urllib.error

FLUENTBIT_METRICS = os.getenv("FLUENTBIT_METRICS_URL", "http://127.0.0.1:2020/api/v1/metrics")
FLUENTBIT_HEALTH = os.getenv("FLUENTBIT_HEALTH_URL", "http://127.0.0.1:2020/api/v1/health")
LOGZIO_TOKEN = os.getenv("LOGZIO_TOKEN", "")
LOGZIO_HOST = os.getenv("LOGZIO_LISTENER_HOST", "listener.logz.io")
LOGZIO_PORT = int(os.getenv("LOGZIO_LISTENER_PORT", "8071"))
NODE_ID = os.getenv("AI_DECOY_NODE_ID", "agents-ia-honeypot-ai-decoy")
HONEYPOT_ENV = os.getenv("HONEYPOT_ENV", "railway")

INTERVAL = int(os.getenv("HEALTHCHECK_INTERVAL", "60"))
STARTUP_GRACE = int(os.getenv("HEALTHCHECK_STARTUP_GRACE", "30"))

AUDIT_LOG = "/var/log/opencanary/audit.log"
OPENCANARY_LOG = "/var/log/opencanary/opencanary.log"
AIDECOY_LOG = os.getenv("AI_DECOY_LOG_PATH", "/var/log/opencanary/ai-decoy.log")

prev_output_records = 0
prev_output_errors = 0
prev_opencanary_lines = 0
prev_aidecoy_lines = 0
consecutive_flb_failures = 0


def utc_iso() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def write_audit(event: dict) -> None:
    event["audit_ts"] = utc_iso()
    event["node_id"] = NODE_ID
    event["honeypot_env"] = HONEYPOT_ENV
    event["event_source"] = "audit-monitor"
    line = json.dumps(event, ensure_ascii=True)
    try:
        with open(AUDIT_LOG, "a", encoding="utf-8") as f:
            f.write(line + "\n")
    except OSError:
        pass
    print(line, flush=True)


def count_lines(path: str) -> int:
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as f:
            return sum(1 for _ in f)
    except FileNotFoundError:
        return 0


# --------------- Fluent Bit checks ---------------

def check_fluentbit_alive() -> bool:
    try:
        req = urllib.request.Request(FLUENTBIT_HEALTH, method="GET")
        with urllib.request.urlopen(req, timeout=5) as resp:
            return resp.status == 200
    except Exception:
        return False


def get_fluentbit_metrics() -> dict | None:
    try:
        req = urllib.request.Request(FLUENTBIT_METRICS, method="GET")
        with urllib.request.urlopen(req, timeout=5) as resp:
            return json.loads(resp.read().decode())
    except Exception:
        return None


def safe_int(val) -> int:
    return int(val) if isinstance(val, (int, float)) else 0


def extract_plugin_stats(plugin_data) -> dict:
    if isinstance(plugin_data, dict):
        return plugin_data
    if isinstance(plugin_data, list):
        merged = {}
        for item in plugin_data:
            if isinstance(item, dict):
                for k, v in item.items():
                    if isinstance(v, (int, float)):
                        merged[k] = merged.get(k, 0) + safe_int(v)
                    else:
                        merged[k] = v
        return merged
    return {}


def extract_pipeline_stats(metrics: dict) -> dict:
    total_out = 0
    total_errors = 0
    total_retries = 0
    total_retries_failed = 0

    output = metrics.get("output", {})
    for _, plugin_data in output.items():
        stats = extract_plugin_stats(plugin_data)
        total_out += safe_int(stats.get("proc_records", stats.get("records", 0)))
        total_errors += safe_int(stats.get("errors", 0))
        total_retries += safe_int(stats.get("retries", 0))
        total_retries_failed += safe_int(stats.get("retries_failed", 0))

    total_in = 0
    input_data = metrics.get("input", {})
    for _, plugin_data in input_data.items():
        stats = extract_plugin_stats(plugin_data)
        total_in += safe_int(stats.get("records", 0))

    return {
        "records_in": total_in,
        "records_out": total_out,
        "errors": total_errors,
        "retries": total_retries,
        "retries_failed": total_retries_failed,
    }


# --------------- Logz.io connectivity check ---------------

def test_logzio_connectivity() -> dict:
    """Send a test probe to logz.io and return status."""
    if not LOGZIO_TOKEN:
        return {"reachable": False, "status_code": 0, "reason": "LOGZIO_TOKEN is empty"}

    test_payload = json.dumps({
        "message": "honeypot audit probe",
        "type": "honeypot-audit",
        "audit_ts": utc_iso(),
        "node_id": NODE_ID,
        "probe": True,
    }).encode("utf-8")

    url = f"https://{LOGZIO_HOST}:{LOGZIO_PORT}/?token={LOGZIO_TOKEN}&type=honeypot-audit"
    try:
        ctx = ssl.create_default_context()
        req = urllib.request.Request(url, data=test_payload, method="POST",
                                     headers={"Content-Type": "application/json"})
        with urllib.request.urlopen(req, timeout=10, context=ctx) as resp:
            return {"reachable": True, "status_code": resp.status, "reason": "OK"}
    except urllib.error.HTTPError as e:
        return {"reachable": True, "status_code": e.code, "reason": e.reason}
    except Exception as e:
        return {"reachable": False, "status_code": 0, "reason": str(e)}


# --------------- Main loop ---------------

def main() -> None:
    global prev_output_records, prev_output_errors
    global prev_opencanary_lines, prev_aidecoy_lines
    global consecutive_flb_failures

    write_audit({
        "audit_type": "startup",
        "message": "Audit monitor started",
        "interval_seconds": INTERVAL,
        "logzio_host": LOGZIO_HOST,
        "logzio_token_set": bool(LOGZIO_TOKEN),
    })

    time.sleep(STARTUP_GRACE)

    # Initial connectivity test
    logzio_test = test_logzio_connectivity()
    write_audit({
        "audit_type": "logzio_connectivity_test",
        "logzio_reachable": logzio_test["reachable"],
        "logzio_status_code": logzio_test["status_code"],
        "logzio_reason": logzio_test["reason"],
        "delivery_status": "OK" if logzio_test.get("status_code") == 200 else "FAIL",
    })

    cycle = 0
    while True:
        cycle += 1
        oc_lines = count_lines(OPENCANARY_LOG)
        ai_lines = count_lines(AIDECOY_LOG)
        new_oc = oc_lines - prev_opencanary_lines
        new_ai = ai_lines - prev_aidecoy_lines

        # --- Fluent Bit health ---
        flb_alive = check_fluentbit_alive()

        if not flb_alive:
            consecutive_flb_failures += 1
            write_audit({
                "audit_type": "pipeline_status",
                "fluentbit_alive": False,
                "consecutive_failures": consecutive_flb_failures,
                "delivery_status": "FAIL",
                "message": "Fluent Bit unreachable - logs NOT being sent to logz.io",
                "opencanary_events_total": oc_lines,
                "aidecoy_events_total": ai_lines,
            })
            prev_opencanary_lines = oc_lines
            prev_aidecoy_lines = ai_lines
            time.sleep(INTERVAL)
            continue

        consecutive_flb_failures = 0

        # --- Pipeline metrics ---
        metrics = get_fluentbit_metrics()
        if not metrics:
            write_audit({
                "audit_type": "pipeline_status",
                "fluentbit_alive": True,
                "delivery_status": "UNKNOWN",
                "message": "Fluent Bit running but metrics API unavailable",
            })
            time.sleep(INTERVAL)
            continue

        stats = extract_pipeline_stats(metrics)
        new_out = stats["records_out"] - prev_output_records
        new_errors = stats["errors"] - prev_output_errors

        # --- Determine delivery status ---
        if stats["errors"] > 0 and new_errors > 0:
            delivery_status = "FAIL"
            message = (f"{new_errors} new delivery error(s) to logz.io! "
                       f"Check LOGZIO_TOKEN and network connectivity.")
        elif stats["retries_failed"] > 0:
            delivery_status = "FAIL"
            message = (f"{stats['retries_failed']} retry(ies) permanently failed. "
                       f"logz.io may be rejecting data.")
        elif stats["records_in"] > 0 and stats["records_out"] == 0:
            delivery_status = "WARN"
            message = "Events collected but NONE delivered. Check if LOGZIO_TOKEN is set."
        elif new_out > 0:
            delivery_status = "OK"
            message = f"+{new_out} records delivered to logz.io this cycle."
        else:
            delivery_status = "IDLE"
            message = "No new events to deliver."

        write_audit({
            "audit_type": "pipeline_status",
            "fluentbit_alive": True,
            "delivery_status": delivery_status,
            "message": message,
            "cycle": cycle,
            "opencanary_events_total": oc_lines,
            "opencanary_events_new": new_oc,
            "aidecoy_events_total": ai_lines,
            "aidecoy_events_new": new_ai,
            "pipeline_records_in": stats["records_in"],
            "pipeline_records_out": stats["records_out"],
            "pipeline_records_new_out": new_out,
            "pipeline_errors": stats["errors"],
            "pipeline_errors_new": new_errors,
            "pipeline_retries": stats["retries"],
            "pipeline_retries_failed": stats["retries_failed"],
        })

        prev_output_records = stats["records_out"]
        prev_output_errors = stats["errors"]
        prev_opencanary_lines = oc_lines
        prev_aidecoy_lines = ai_lines

        # Periodic logz.io connectivity test (every 10 cycles)
        if cycle % 10 == 0:
            logzio_test = test_logzio_connectivity()
            write_audit({
                "audit_type": "logzio_connectivity_test",
                "logzio_reachable": logzio_test["reachable"],
                "logzio_status_code": logzio_test["status_code"],
                "logzio_reason": logzio_test["reason"],
                "delivery_status": "OK" if logzio_test.get("status_code") == 200 else "FAIL",
            })

        time.sleep(INTERVAL)


if __name__ == "__main__":
    main()
