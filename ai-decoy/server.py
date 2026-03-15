import asyncio
import datetime as dt
import json
import os
from typing import Dict, Tuple

LOG_PATH = os.getenv("AI_DECOY_LOG_PATH", "/var/log/opencanary/ai-decoy.log")
NODE_ID = os.getenv("AI_DECOY_NODE_ID", "agents-ia-honeypot-ai-decoy")

SERVICE_MAP: Dict[int, Dict[str, str]] = {
    5678: {"service": "n8n", "banner": "n8n Automation Platform"},
    3000: {"service": "openclaw", "banner": "OpenClaw AI Workspace"},
    3001: {"service": "open-webui", "banner": "Open WebUI"},
    11434: {"service": "ollama", "banner": "Ollama API"},
    7860: {"service": "gradio", "banner": "Gradio Interface"},
    8888: {"service": "jupyter", "banner": "Jupyter Server"},
    8080: {"service": "flowise", "banner": "Flowise AI"},
    9000: {"service": "anythingllm", "banner": "AnythingLLM"},
}


def utc_iso() -> str:
    return dt.datetime.utcnow().replace(microsecond=0).isoformat() + "Z"


def write_event(event: dict) -> None:
    line = json.dumps(event, ensure_ascii=True)
    with open(LOG_PATH, "a", encoding="utf-8") as f:
        f.write(line + "\n")
    print(line, flush=True)


def parse_http_request(raw: bytes) -> Tuple[str, str, Dict[str, str], str]:
    try:
        text = raw.decode("utf-8", errors="replace")
        headers_part, _, body = text.partition("\r\n\r\n")
        lines = headers_part.split("\r\n")
        req_line = lines[0] if lines else "GET / HTTP/1.1"
        parts = req_line.split(" ")
        method = parts[0] if len(parts) > 0 else "GET"
        path = parts[1] if len(parts) > 1 else "/"
        headers: Dict[str, str] = {}
        for line in lines[1:]:
            if ":" in line:
                k, v = line.split(":", 1)
                headers[k.strip().lower()] = v.strip()
        return method, path, headers, body[:512]
    except Exception:
        return "GET", "/", {}, ""


def build_response(port: int, path: str) -> bytes:
    service = SERVICE_MAP.get(port, {"service": "unknown", "banner": "AI Service"})
    payload = {
        "service": service["service"],
        "message": service["banner"],
        "status": "ok",
        "path": path,
        "ts": utc_iso(),
    }

    if service["service"] == "ollama" and path.startswith("/api/"):
        payload.update({"models": [{"name": "llama3:latest"}, {"name": "mistral:latest"}]})
    elif service["service"] == "n8n" and path.startswith("/rest/"):
        payload.update({"workflowCount": 12, "executionMode": "queue"})
    elif service["service"] == "jupyter":
        payload.update({"base_url": "/", "default_kernel": "python3"})

    body = json.dumps(payload, ensure_ascii=True).encode("utf-8")
    headers = (
        "HTTP/1.1 200 OK\r\n"
        "Content-Type: application/json\r\n"
        f"Content-Length: {len(body)}\r\n"
        "Server: nginx/1.18.0\r\n"
        "Connection: close\r\n"
        "\r\n"
    ).encode("utf-8")
    return headers + body


async def handle_client(reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
    peer = writer.get_extra_info("peername")
    sock = writer.get_extra_info("sockname")
    src_ip = peer[0] if peer else "unknown"
    src_port = peer[1] if peer else 0
    dst_port = sock[1] if sock else 0
    service = SERVICE_MAP.get(dst_port, {"service": "unknown"})["service"]

    data = b""
    try:
        data = await asyncio.wait_for(reader.read(4096), timeout=5.0)
    except asyncio.TimeoutError:
        pass

    method, path, headers, body = parse_http_request(data)

    event = {
        "local_time_adjusted": utc_iso(),
        "node_id": NODE_ID,
        "logtype": 9100,
        "event_source": "ai-decoy",
        "service_name": service,
        "dst_port": dst_port,
        "src_host": src_ip,
        "src_port": src_port,
        "http_method": method,
        "http_path": path,
        "user_agent": headers.get("user-agent", ""),
        "auth_header": headers.get("authorization", ""),
        "body_sample": body,
    }
    write_event(event)

    response = build_response(dst_port, path)
    writer.write(response)
    await writer.drain()
    writer.close()
    await writer.wait_closed()


async def main() -> None:
    os.makedirs(os.path.dirname(LOG_PATH), exist_ok=True)
    servers = []
    for port in SERVICE_MAP:
        server = await asyncio.start_server(handle_client, host="0.0.0.0", port=port)
        servers.append(server)
        write_event(
            {
                "local_time_adjusted": utc_iso(),
                "node_id": NODE_ID,
                "logtype": 9101,
                "event_source": "ai-decoy",
                "service_name": SERVICE_MAP[port]["service"],
                "dst_port": port,
                "message": "listener_started",
            }
        )

    await asyncio.gather(*(srv.serve_forever() for srv in servers))


if __name__ == "__main__":
    asyncio.run(main())
