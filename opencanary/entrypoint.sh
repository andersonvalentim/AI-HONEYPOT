#!/usr/bin/env sh
set -eu

mkdir -p /var/log/opencanary /tmp/opencanaryd

python - <<'PY'
import json
import os
import shutil
from pathlib import Path

src = Path("/etc/opencanaryd/opencanary.conf")
dst = Path("/tmp/opencanaryd/opencanary.conf")

shutil.copy2(src, dst)

cfg = json.loads(dst.read_text(encoding="utf-8"))

cfg["device.node_id"] = os.getenv("OPENCANARY_DEVICE_NODE_ID", cfg.get("device.node_id", "agents-ia-honeypot"))

http_banner = os.getenv("OPENCANARY_HTTP_BANNER")
if http_banner:
    cfg["httphoney.banner"] = http_banner

ssh_banner = os.getenv("OPENCANARY_SSH_BANNER")
if ssh_banner:
    cfg["ssh.version"] = ssh_banner

dst.write_text(json.dumps(cfg, indent=2), encoding="utf-8")
PY

exec opencanaryd --dev --config /tmp/opencanaryd/opencanary.conf
