#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────
#  AI-HONEYPOT — Server Setup Script
#  Installs Docker, clones repo, configures
#  environment, and starts the honeypot.
# ─────────────────────────────────────────────

REPO_URL="https://github.com/andersonvalentim/AI-HONEYPOT.git"
INSTALL_DIR="/opt/ai-honeypot"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

banner() {
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════╗"
    echo "║       AI-HONEYPOT  Setup Script          ║"
    echo "║  OpenCanary + AI Decoy + Fluent Bit      ║"
    echo "╚══════════════════════════════════════════╝"
    echo -e "${NC}"
}

info()  { echo -e "${GREEN}[INFO]${NC}  $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $1"; }
fail()  { echo -e "${RED}[FAIL]${NC}  $1"; exit 1; }

# ── Pre-flight ──────────────────────────────

check_root() {
    if [ "$EUID" -ne 0 ]; then
        fail "Execute como root: sudo bash setup.sh"
    fi
}

detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_ID="${ID}"
        OS_NAME="${PRETTY_NAME}"
    else
        fail "Sistema operacional nao suportado."
    fi
    info "Sistema detectado: ${OS_NAME}"
}

# ── Docker ──────────────────────────────────

install_docker() {
    if command -v docker &>/dev/null; then
        info "Docker ja instalado: $(docker --version)"
        return
    fi

    info "Instalando Docker..."
    case "${OS_ID}" in
        ubuntu|debian|pop)
            apt-get update -qq
            apt-get install -y -qq ca-certificates curl gnupg lsb-release
            install -m 0755 -d /etc/apt/keyrings
            curl -fsSL "https://download.docker.com/linux/${OS_ID}/gpg" | \
                gpg --dearmor -o /etc/apt/keyrings/docker.gpg
            chmod a+r /etc/apt/keyrings/docker.gpg
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
                https://download.docker.com/linux/${OS_ID} $(lsb_release -cs) stable" | \
                tee /etc/apt/sources.list.d/docker.list > /dev/null
            apt-get update -qq
            apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin
            ;;
        centos|rhel|fedora|rocky|alma)
            dnf install -y -q dnf-plugins-core
            dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
            dnf install -y -q docker-ce docker-ce-cli containerd.io docker-compose-plugin
            ;;
        *)
            warn "Distribuicao '${OS_ID}' nao tem instalacao automatica."
            warn "Instale Docker manualmente: https://docs.docker.com/engine/install/"
            fail "Docker nao encontrado."
            ;;
    esac

    systemctl enable --now docker
    info "Docker instalado com sucesso: $(docker --version)"
}

check_compose() {
    if docker compose version &>/dev/null; then
        info "Docker Compose: $(docker compose version --short)"
    else
        fail "Docker Compose nao encontrado. Atualize o Docker."
    fi
}

# ── Clone / Update ──────────────────────────

setup_repo() {
    if [ -d "${INSTALL_DIR}/.git" ]; then
        info "Repositorio ja existe em ${INSTALL_DIR}, atualizando..."
        cd "${INSTALL_DIR}"
        git pull --ff-only || warn "Nao foi possivel atualizar (changes locais?)"
    else
        info "Clonando repositorio em ${INSTALL_DIR}..."
        git clone "${REPO_URL}" "${INSTALL_DIR}"
        cd "${INSTALL_DIR}"
    fi
    info "Projeto em: ${INSTALL_DIR}"
}

# ── Port mode ───────────────────────────────

choose_port_mode() {
    echo ""
    echo -e "${CYAN}Escolha o modo de portas:${NC}"
    echo "  1) VPS/Dedicado — portas padrao (21, 22, 80, 3306, etc.)"
    echo "     Ideal para VPS/VM isolada, captura scanners reais."
    echo ""
    echo "  2) Cloud/Compartilhado — portas altas (10021, 10022, 18080, etc.)"
    echo "     Ideal para Railway, EasyPanel, ambientes compartilhados."
    echo ""
    read -rp "Opcao [1/2] (default: 1): " PORT_MODE
    PORT_MODE="${PORT_MODE:-1}"

    if [ "${PORT_MODE}" = "1" ]; then
        info "Modo VPS selecionado — portas padrao"
        apply_vps_ports
    else
        info "Modo Cloud selecionado — portas altas"
        apply_cloud_ports
    fi
}

apply_vps_ports() {
    cat > "${INSTALL_DIR}/opencanary/opencanary.conf" << 'OCEOF'
{
  "device.node_id": "agents-ia-honeypot",
  "logger": {
    "class": "PyLogger",
    "kwargs": {
      "formatters": {
        "plain": { "format": "%(message)s" }
      },
      "handlers": {
        "console": {
          "class": "logging.StreamHandler",
          "stream": "ext://sys.stdout"
        },
        "file": {
          "class": "logging.handlers.WatchedFileHandler",
          "filename": "/var/log/opencanary/opencanary.log"
        }
      },
      "root": {
        "level": "INFO",
        "handlers": ["console", "file"]
      }
    }
  },
  "ip.ignorelist": [],
  "mac.address": "00:11:22:33:44:55",
  "sniffer.interface": "",
  "ftp.enabled": true,
  "ftp.port": 21,
  "ftp.banner": "FTP server ready",
  "http.enabled": true,
  "http.port": 80,
  "httphoney.banner": "Apache/2.4.7 (Ubuntu)",
  "httphoney.skin": "nasLogin",
  "ssh.enabled": true,
  "ssh.port": 22,
  "ssh.version": "SSH-2.0-OpenSSH_7.2p2 Ubuntu-4ubuntu2.10",
  "telnet.enabled": true,
  "telnet.port": 23,
  "mysql.enabled": true,
  "mysql.port": 3306,
  "mysql.banner": "5.5.43-0ubuntu0.14.04.1",
  "rdp.enabled": true,
  "rdp.port": 3389,
  "smtp.enabled": true,
  "smtp.port": 25,
  "pop3.enabled": true,
  "pop3.port": 110,
  "imap.enabled": true,
  "imap.port": 143,
  "postgres.enabled": true,
  "postgres.port": 5432
}
OCEOF

    cat > "${INSTALL_DIR}/docker-compose.yml" << 'DCEOF'
services:
  opencanary:
    build:
      context: ./opencanary
      dockerfile: Dockerfile
    container_name: opencanary
    restart: unless-stopped
    network_mode: host
    environment:
      OPENCANARY_DEVICE_NODE_ID: "${OPENCANARY_DEVICE_NODE_ID:-agents-ia-honeypot}"
      OPENCANARY_HTTP_BANNER: "${OPENCANARY_HTTP_BANNER:-Apache/2.4.7 (Ubuntu)}"
      OPENCANARY_SSH_BANNER: "${OPENCANARY_SSH_BANNER:-SSH-2.0-OpenSSH_7.2p2 Ubuntu-4ubuntu2.10}"
    volumes:
      - ./opencanary/opencanary.conf:/etc/opencanaryd/opencanary.conf:ro
      - ./logs/opencanary:/var/log/opencanary

  ai-decoy:
    build:
      context: ./ai-decoy
      dockerfile: Dockerfile
    container_name: ai-decoy
    restart: unless-stopped
    network_mode: host
    environment:
      AI_DECOY_NODE_ID: "${AI_DECOY_NODE_ID:-agents-ia-honeypot-ai-decoy}"
      AI_DECOY_LOG_PATH: "/var/log/opencanary/ai-decoy.log"
      AI_DECOY_PORTS: "5678:n8n:n8n Automation Platform,3000:openclaw:OpenClaw AI Workspace,3001:open-webui:Open WebUI,11434:ollama:Ollama API,7860:gradio:Gradio Interface,8888:jupyter:Jupyter Server,8080:flowise:Flowise AI,9000:anythingllm:AnythingLLM"
    volumes:
      - ./logs/opencanary:/var/log/opencanary

  fluent-bit:
    image: cr.fluentbit.io/fluent/fluent-bit:3.2
    container_name: fluent-bit
    restart: unless-stopped
    depends_on:
      - opencanary
      - ai-decoy
    environment:
      LOGZIO_TOKEN: "${LOGZIO_TOKEN}"
      LOGZIO_LISTENER_HOST: "${LOGZIO_LISTENER_HOST:-listener.logz.io}"
      LOGZIO_LISTENER_PORT: "${LOGZIO_LISTENER_PORT:-8071}"
      HONEYPOT_ENV: "${HONEYPOT_ENV:-vps}"
    volumes:
      - ./fluent-bit/fluent-bit.conf:/fluent-bit/etc/fluent-bit.conf:ro
      - ./fluent-bit/parsers.conf:/fluent-bit/etc/parsers.conf:ro
      - ./logs/opencanary:/var/log/opencanary:ro
DCEOF
}

apply_cloud_ports() {
    cat > "${INSTALL_DIR}/opencanary/opencanary.conf" << 'OCEOF'
{
  "device.node_id": "agents-ia-honeypot",
  "logger": {
    "class": "PyLogger",
    "kwargs": {
      "formatters": {
        "plain": { "format": "%(message)s" }
      },
      "handlers": {
        "console": {
          "class": "logging.StreamHandler",
          "stream": "ext://sys.stdout"
        },
        "file": {
          "class": "logging.handlers.WatchedFileHandler",
          "filename": "/var/log/opencanary/opencanary.log"
        }
      },
      "root": {
        "level": "INFO",
        "handlers": ["console", "file"]
      }
    }
  },
  "ip.ignorelist": [],
  "mac.address": "00:11:22:33:44:55",
  "sniffer.interface": "",
  "ftp.enabled": true,
  "ftp.port": 10021,
  "ftp.banner": "FTP server ready",
  "http.enabled": true,
  "http.port": 18080,
  "httphoney.banner": "Apache/2.4.7 (Ubuntu)",
  "httphoney.skin": "nasLogin",
  "ssh.enabled": true,
  "ssh.port": 10022,
  "ssh.version": "SSH-2.0-OpenSSH_7.2p2 Ubuntu-4ubuntu2.10",
  "telnet.enabled": true,
  "telnet.port": 10023,
  "mysql.enabled": true,
  "mysql.port": 13306,
  "mysql.banner": "5.5.43-0ubuntu0.14.04.1",
  "rdp.enabled": true,
  "rdp.port": 13389,
  "smtp.enabled": true,
  "smtp.port": 10025,
  "pop3.enabled": true,
  "pop3.port": 10110,
  "imap.enabled": true,
  "imap.port": 10143,
  "postgres.enabled": true,
  "postgres.port": 15432
}
OCEOF
}

# ── Configuracao ────────────────────────────

configure_env() {
    echo ""
    echo -e "${CYAN}─── Configuracao do ambiente ───${NC}"
    echo ""

    read -rp "Token do logz.io (Data Shipping Token): " INPUT_TOKEN
    if [ -z "${INPUT_TOKEN}" ]; then
        warn "Token vazio — logs NAO serao enviados ao logz.io."
        INPUT_TOKEN=""
    fi

    read -rp "Listener host do logz.io [listener.logz.io]: " INPUT_HOST
    INPUT_HOST="${INPUT_HOST:-listener.logz.io}"

    read -rp "Nome do ambiente (ex: vps, lab, prod) [vps]: " INPUT_ENV
    INPUT_ENV="${INPUT_ENV:-vps}"

    read -rp "Node ID do honeypot [agents-ia-honeypot]: " INPUT_NODE
    INPUT_NODE="${INPUT_NODE:-agents-ia-honeypot}"

    cat > "${INSTALL_DIR}/.env" << ENVEOF
LOGZIO_TOKEN=${INPUT_TOKEN}
LOGZIO_LISTENER_HOST=${INPUT_HOST}
LOGZIO_LISTENER_PORT=8071
HONEYPOT_ENV=${INPUT_ENV}
OPENCANARY_DEVICE_NODE_ID=${INPUT_NODE}
OPENCANARY_HTTP_BANNER=Apache/2.4.7 (Ubuntu)
OPENCANARY_SSH_BANNER=SSH-2.0-OpenSSH_7.2p2 Ubuntu-4ubuntu2.10
AI_DECOY_NODE_ID=${INPUT_NODE}-ai-decoy
ENVEOF

    info "Arquivo .env criado em ${INSTALL_DIR}/.env"
}

# ── SSH guard ───────────────────────────────

check_ssh_conflict() {
    if [ "${PORT_MODE}" != "1" ]; then
        return
    fi

    if ss -tlnp | grep -q ':22 ' 2>/dev/null; then
        echo ""
        warn "O SSH do servidor esta escutando na porta 22."
        warn "O OpenCanary tambem quer a porta 22 para o honeypot SSH."
        echo ""
        echo -e "${YELLOW}Opcoes:${NC}"
        echo "  1) Mover o SSH real para outra porta (ex: 2222) — recomendado"
        echo "  2) Desativar o honeypot SSH (manter SSH real na 22)"
        echo "  3) Ignorar (pode causar conflito)"
        echo ""
        read -rp "Opcao [1/2/3] (default: 1): " SSH_CHOICE
        SSH_CHOICE="${SSH_CHOICE:-1}"

        case "${SSH_CHOICE}" in
            1)
                info "Movendo SSH para porta 2222..."
                if [ -f /etc/ssh/sshd_config ]; then
                    sed -i 's/^#\?Port .*/Port 2222/' /etc/ssh/sshd_config
                    systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null || true
                    warn "SSH movido para porta 2222. Reconecte com: ssh -p 2222 user@host"
                fi
                ;;
            2)
                info "Desativando honeypot SSH..."
                cd "${INSTALL_DIR}"
                python3 -c "
import json
with open('opencanary/opencanary.conf') as f: c = json.load(f)
c['ssh.enabled'] = False
with open('opencanary/opencanary.conf', 'w') as f: json.dump(c, f, indent=2)
"
                ;;
            3)
                warn "Conflito ignorado — o OpenCanary pode falhar na porta 22."
                ;;
        esac
    fi
}

# ── Firewall hint ───────────────────────────

setup_firewall_hint() {
    echo ""
    echo -e "${CYAN}─── Firewall ───${NC}"

    if command -v ufw &>/dev/null; then
        echo -e "Detectado: ${GREEN}ufw${NC}"
        echo ""
        echo "Para liberar as portas do honeypot, execute:"
        if [ "${PORT_MODE}" = "1" ]; then
            echo "  ufw allow 21,22,23,25,80,110,143,3306,3389,5432/tcp"
            echo "  ufw allow 3000,3001,5678,7860,8080,8888,9000,11434/tcp"
        else
            echo "  ufw allow 10021,10022,10023,10025,18080,10110,10143,13306,13389,15432/tcp"
            echo "  ufw allow 3000,3001,5678,7860,8080,8888,9000,11434/tcp"
        fi
        echo ""
        read -rp "Aplicar agora? [y/N]: " FW_APPLY
        if [[ "${FW_APPLY}" =~ ^[yYsS]$ ]]; then
            if [ "${PORT_MODE}" = "1" ]; then
                ufw allow 21,22,23,25,80,110,143,3306,3389,5432/tcp
                ufw allow 3000,3001,5678,7860,8080,8888,9000,11434/tcp
            else
                ufw allow 10021,10022,10023,10025,18080,10110,10143,13306,13389,15432/tcp
                ufw allow 3000,3001,5678,7860,8080,8888,9000,11434/tcp
            fi
            info "Regras de firewall aplicadas."
        fi
    else
        warn "Nenhum firewall detectado. Configure manualmente se necessario."
    fi
}

# ── Build & Start ───────────────────────────

start_honeypot() {
    echo ""
    info "Construindo e iniciando containers..."
    cd "${INSTALL_DIR}"
    mkdir -p logs/opencanary
    docker compose up -d --build

    echo ""
    info "Aguardando containers..."
    sleep 5
    docker compose ps
}

# ── Status ──────────────────────────────────

show_status() {
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════╗"
    echo -e "║          Honeypot Ativo!                 ║"
    echo -e "╚══════════════════════════════════════════╝${NC}"
    echo ""

    SERVER_IP=$(curl -4 -s --max-time 5 ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
    info "IP do servidor: ${SERVER_IP}"
    echo ""

    echo -e "${GREEN}Comandos uteis:${NC}"
    echo "  cd ${INSTALL_DIR}"
    echo "  docker compose logs -f              # Ver todos os logs"
    echo "  docker compose logs -f opencanary   # Logs do OpenCanary"
    echo "  docker compose logs -f ai-decoy     # Logs do AI Decoy"
    echo "  docker compose logs -f fluent-bit   # Logs do Fluent Bit"
    echo "  docker compose ps                   # Status dos containers"
    echo "  docker compose down                 # Parar tudo"
    echo "  docker compose up -d --build        # Reiniciar tudo"
    echo ""

    if [ "${PORT_MODE}" = "1" ]; then
        echo -e "${GREEN}Teste rapido:${NC}"
        echo "  curl http://${SERVER_IP}                 # HTTP honeypot"
        echo "  curl http://${SERVER_IP}:5678            # n8n decoy"
        echo "  curl http://${SERVER_IP}:11434/api/tags  # Ollama decoy"
        echo "  nc -zv ${SERVER_IP} 22                   # SSH honeypot"
    else
        echo -e "${GREEN}Teste rapido:${NC}"
        echo "  curl http://${SERVER_IP}:18080           # HTTP honeypot"
        echo "  curl http://${SERVER_IP}:5678            # n8n decoy"
        echo "  curl http://${SERVER_IP}:11434/api/tags  # Ollama decoy"
        echo "  nc -zv ${SERVER_IP} 10022                # SSH honeypot"
    fi
    echo ""

    echo -e "${GREEN}Logs:${NC}"
    echo "  ${INSTALL_DIR}/logs/opencanary/opencanary.log"
    echo "  ${INSTALL_DIR}/logs/opencanary/ai-decoy.log"
    echo "  ${INSTALL_DIR}/logs/opencanary/audit.log"
    echo ""
}

# ── Main ────────────────────────────────────

main() {
    banner
    check_root
    detect_os
    install_docker
    check_compose
    setup_repo
    choose_port_mode
    configure_env
    check_ssh_conflict
    setup_firewall_hint
    start_honeypot
    show_status
}

main "$@"
