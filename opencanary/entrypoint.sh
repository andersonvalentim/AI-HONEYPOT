#!/usr/bin/env sh
set -eu

mkdir -p /var/log/opencanary /tmp/opencanaryd

cp /etc/opencanaryd/opencanary.conf /tmp/opencanaryd/opencanary.conf

python - <<'PY'
import json
import os
from pathlib import Path

cfg_path = Path("/tmp/opencanaryd/opencanary.conf")
cfg = json.loads(cfg_path.read_text(encoding="utf-8"))

cfg["device.node_id"] = os.getenv("OPENCANARY_DEVICE_NODE_ID", cfg.get("device.node_id", "agents-ia-honeypot"))

http_banner = os.getenv("OPENCANARY_HTTP_BANNER")
if http_banner:
    cfg["httphoney.banner"] = http_banner

ssh_banner = os.getenv("OPENCANARY_SSH_BANNER")
if ssh_banner:
    cfg["ssh.version"] = ssh_banner

cfg_path.write_text(json.dumps(cfg, indent=2), encoding="utf-8")
PY

export OPENCANARY_CONF=/tmp/opencanaryd/opencanary.conf
exec opencanaryd --dev
