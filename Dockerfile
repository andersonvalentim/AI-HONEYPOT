FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

# --- OpenCanary + Supervisor + Fluent Bit ---
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       libssl-dev libffi-dev libpcap-dev \
       build-essential supervisor \
       curl ca-certificates gnupg \
    && pip install --no-cache-dir opencanary \
    && curl https://raw.githubusercontent.com/fluent/fluent-bit/master/install.sh | sh \
    && apt-get purge -y build-essential gnupg \
    && apt-get autoremove -y \
    && rm -rf /var/lib/apt/lists/*

# --- Logz.io Fluent Bit output plugin ---
RUN mkdir -p /fluent-bit/plugins \
    && curl -sSL -o /fluent-bit/plugins/out_logzio.so \
       https://github.com/logzio/fluent-bit-logzio-output/raw/master/build/out_logzio-linux.so

# --- Directories ---
RUN mkdir -p /etc/opencanaryd /var/log/opencanary /fluent-bit/etc /app

# --- OpenCanary ---
COPY opencanary/opencanary.conf /etc/opencanaryd/opencanary.conf
COPY opencanary/entrypoint.sh  /entrypoint-opencanary.sh
RUN chmod +x /entrypoint-opencanary.sh

# --- AI Decoy ---
COPY ai-decoy/server.py /app/server.py

# --- Health Check ---
COPY healthcheck.py /app/healthcheck.py

# --- Fluent Bit config ---
COPY fluent-bit/fluent-bit.conf /fluent-bit/etc/fluent-bit.conf
COPY fluent-bit/parsers.conf    /fluent-bit/etc/parsers.conf
COPY fluent-bit/plugins.conf    /fluent-bit/etc/plugins.conf

# --- Supervisord ---
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# --- Default env vars (override in Railway dashboard) ---
ENV OPENCANARY_DEVICE_NODE_ID=agents-ia-honeypot
ENV OPENCANARY_HTTP_BANNER="Apache/2.4.7 (Ubuntu)"
ENV OPENCANARY_SSH_BANNER="SSH-2.0-OpenSSH_7.2p2 Ubuntu-4ubuntu2.10"
ENV AI_DECOY_NODE_ID=agents-ia-honeypot-ai-decoy
ENV AI_DECOY_LOG_PATH=/var/log/opencanary/ai-decoy.log
ENV LOGZIO_TOKEN=""
ENV LOGZIO_LISTENER_HOST=listener.logz.io
ENV LOGZIO_LISTENER_PORT=8071
ENV HONEYPOT_ENV=railway

CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
