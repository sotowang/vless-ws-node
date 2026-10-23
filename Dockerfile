FROM debian:bookworm-slim

RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates wget \
 && rm -rf /var/lib/apt/lists/*

ENV SINGBOX_VERSION=1.14.3

# sing-box's linux/amd64 binary is dynamically linked against glibc,
# so we use debian-slim (not alpine/musl) as the base image.
RUN wget -qO /tmp/sb.tar.gz "https://github.com/SagerNet/sing-box/releases/download/v${SINGBOX_VERSION}/sing-box-${SINGBOX_VERSION}-linux-amd64.tar.gz" \
 && tar -xzf /tmp/sb.tar.gz -C /tmp \
 && SB_BIN="$(find /tmp -maxdepth 2 -name sing-box -type f | head -1)" \
 && mv "$SB_BIN" /usr/local/bin/sing-box \
 && chmod +x /usr/local/bin/sing-box \
 && rm -rf /tmp/sb.tar.gz /tmp/sing-box-* \
 && /usr/local/bin/sing-box version

WORKDIR /app

# Single-file project: Netrun's Paste saves content as app.sh (breaking
# Dockerfile detection), so the other two files are generated here via
# quoted heredocs (no variable expansion inside).
RUN cat > /app/config.template.json <<'EOF'
{
  "log": {
    "level": "warn"
  },
  "inbounds": [
    {
      "type": "vless",
      "tag": "vless-in",
      "listen": "0.0.0.0",
      "listen_port": __PORT__,
      "users": [
        {
          "uuid": "__UUID__"
        }
      ],
      "transport": {
        "type": "ws",
        "path": "/__WS_PATH__"
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    },
    {
      "type": "block",
      "tag": "block"
    }
  ]
}
EOF

RUN cat > /app/entrypoint.sh <<'EOF'
#!/bin/sh
# Renders sing-box config from env vars and starts the VLESS+WS node.
# Env: PORT (platform-provided), UUID (client id), WS_PATH (websocket path, no leading slash)
set -e

PORT="${PORT:-8080}"

if [ -z "$UUID" ]; then
  if command -v uuidgen >/dev/null 2>&1; then
    UUID="$(uuidgen)"
  else
    UUID="$(cat /proc/sys/kernel/random/uuid)"
  fi
  echo "[netrun-vless] UUID not provided, generated: $UUID"
fi

if [ -z "$WS_PATH" ]; then
  WS_PATH="$(head -c 9 /dev/urandom | od -An -tx1 | tr -d ' \n')"
  echo "[netrun-vless] WS_PATH not provided, generated: $WS_PATH"
fi

sed -e "s/__PORT__/${PORT}/" \
    -e "s/__UUID__/${UUID}/" \
    -e "s|__WS_PATH__|${WS_PATH}|" \
    /app/config.template.json > /tmp/config.json

/usr/local/bin/sing-box check -c /tmp/config.json
echo "[netrun-vless] VLESS node listening on 0.0.0.0:${PORT}, ws path /${WS_PATH}"

exec /usr/local/bin/sing-box run -c /tmp/config.json
EOF

RUN chmod +x /app/entrypoint.sh

ENTRYPOINT ["/app/entrypoint.sh"]
