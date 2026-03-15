# Agents-IA-Honeypot (EN)

Academic honeypot lab for threat intelligence, designed for:
- mapping scanner behavior across classic protocols
- mapping AI tooling attack surface exposure
- centralized audit telemetry with `Fluent Bit -> logz.io`

## Architecture

| Component | Purpose | Main file |
|---|---|---|
| OpenCanary | Emulates classic internet-facing services | `opencanary/opencanary.conf` |
| AI Decoy | Emulates ports/endpoints used by AI tools | `ai-decoy/server.py` |
| Fluent Bit | Collects, enriches, and ships logs to `logz.io` | `fluent-bit/fluent-bit.conf` |

## Safety Notice

Run this project only in a controlled lab:
- isolated VLAN / segmented network
- never expose in production
- no real credentials or sensitive data
- outbound traffic monitoring and egress controls

## Requirements

- Docker Engine
- Docker Compose plugin
- `logz.io` ingest token

## Project layout

- `docker-compose.yml`: main stack
- `opencanary/`: classic honeypot services
- `ai-decoy/`: AI-focused decoy services
- `fluent-bit/`: audit pipeline
- `logs/opencanary/`: local log storage
- `.env.example`: environment variables template

## Emulated ports

### OpenCanary

- `80` HTTP
- `21` FTP
- `22` SSH
- `23` Telnet
- `25` SMTP
- `110` POP3
- `143` IMAP
- `3306` MySQL
- `5432` PostgreSQL
- `3389` RDP

### AI Decoy

- `5678` n8n
- `3000` OpenClaw
- `3001` Open WebUI
- `11434` Ollama API
- `7860` Gradio
- `8888` Jupyter
- `8080` Flowise
- `9000` AnythingLLM

## Getting started

1) Copy environment template:

```bash
cp .env.example .env
```

2) Edit `.env` and set:
- `LOGZIO_TOKEN`
- `LOGZIO_LISTENER_HOST`
- `LOGZIO_LISTENER_PORT`

3) Start stack:

```bash
docker compose up -d --build
```

4) Follow logs:

```bash
docker compose logs -f opencanary
docker compose logs -f ai-decoy
docker compose logs -f fluent-bit
```

## EasyPanel deployment (high ports)

Use the dedicated compose file:

```bash
docker compose -f docker-compose.easypanel.yml up -d --build
```

Recommended external mapping (host -> internal service):

- `18080 -> 80` (OpenCanary HTTP)
- `10022 -> 22` (SSH decoy)
- `13306 -> 3306` (MySQL decoy)
- `15678 -> 5678` (n8n decoy)
- `21434 -> 11434` (Ollama decoy)
- `18888 -> 8888` (Jupyter decoy)

In EasyPanel, expose these TCP ports on the imported app/service to preserve scanner visibility.

## Quick tests

```bash
curl -i http://127.0.0.1:18080/
nc -vz 127.0.0.1 10022
curl -i http://127.0.0.1:15678/
curl -i http://127.0.0.1:21434/api/tags
curl -i http://127.0.0.1:18888/
```

## Where events land

- `logs/opencanary/opencanary.log`
- `logs/opencanary/ai-decoy.log`
- `fluent-bit` container output
- your `logz.io` account

## Teaching ideas

- Build dashboards by `src_host`, `dst_port`, `service_name`, and `http_path`.
- Alert on high connection burst per source IP.
- Track API probing patterns (`/api/*`, `/rest/*`).
- Compare horizontal scanner behavior vs targeted brute-force attempts.
