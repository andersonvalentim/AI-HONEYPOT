# Agents-IA-Honeypot (PT-BR)

Ambiente de honeypot para laboratorio academico de threat intelligence, com foco em:
- mapeamento de scanners em protocolos tradicionais
- mapeamento de superficie de ataque em ferramentas de IA
- trilha de auditoria centralizada com envio para `logz.io`

## Arquitetura

| Componente | Funcao | Arquivo principal |
|---|---|---|
| OpenCanary | Emula servicos classicos (HTTP, SSH, FTP, etc.) | `opencanary/opencanary.conf` |
| AI Decoy | Emula portas e endpoints de ferramentas de IA | `ai-decoy/server.py` |
| Fluent Bit | Coleta, enriquece e envia logs para `logz.io` | `fluent-bit/fluent-bit.conf` |

## Aviso de seguranca

Use somente em ambiente controlado:
- isole em VLAN/rede dedicada
- nao publique em producao
- nao use dados ou credenciais reais
- restrinja e monitore trafego de saida

## Requisitos

- Docker Engine
- Docker Compose plugin
- Token de ingestao do `logz.io`

## Estrutura do projeto

- `docker-compose.yml`: stack principal
- `opencanary/`: servicos honeypot classicos
- `ai-decoy/`: emulacao de servicos voltados a IA
- `fluent-bit/`: pipeline de auditoria
- `logs/opencanary/`: logs locais
- `.env.example`: variaveis de ambiente

## Portas emuladas

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

## Como subir

1) Copie variaveis de ambiente:

```bash
cp .env.example .env
```

2) Edite `.env` e configure:
- `LOGZIO_TOKEN`
- `LOGZIO_LISTENER_HOST`
- `LOGZIO_LISTENER_PORT`

3) Suba os servicos:

```bash
docker compose up -d --build
```

4) Acompanhe os logs:

```bash
docker compose logs -f opencanary
docker compose logs -f ai-decoy
docker compose logs -f fluent-bit
```

## Deploy no EasyPanel (portas altas)

Use o arquivo dedicado:

```bash
docker compose -f docker-compose.easypanel.yml up -d --build
```

Mapeamentos externos recomendados (host -> servico interno):

- `18080 -> 80` (HTTP OpenCanary)
- `10022 -> 22` (SSH decoy)
- `13306 -> 3306` (MySQL decoy)
- `15678 -> 5678` (n8n decoy)
- `21434 -> 11434` (Ollama decoy)
- `18888 -> 8888` (Jupyter decoy)

No EasyPanel, publique esses TCP ports no app/servico importado para manter visibilidade de scans.

## Testes rapidos

```bash
curl -i http://127.0.0.1:18080/
nc -vz 127.0.0.1 10022
curl -i http://127.0.0.1:15678/
curl -i http://127.0.0.1:21434/api/tags
curl -i http://127.0.0.1:18888/
```

## Onde os eventos aparecem

- `logs/opencanary/opencanary.log`
- `logs/opencanary/ai-decoy.log`
- saida do `fluent-bit`
- dashboard no `logz.io`

## Sugestoes para aula

- Crie dashboards por `src_host`, `dst_port`, `service_name` e `http_path`.
- Configure alertas para burst de conexoes por IP.
- Monitore tentativas em rotas de API (`/api/*`, `/rest/*`).
- Compare comportamentos entre scanner horizontal e brute-force vertical.
