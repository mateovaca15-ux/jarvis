#!/bin/bash
# Provisions a fresh Oracle Cloud Always Free VM (Ubuntu 24.04, ARM or x86) for the WhatsApp assistant. Run as root (sudo).
# Usage: setup.sh <public-hostname>
set -euo pipefail
HOST=$1
U=assistant
ARCH=$(dpkg --print-architecture)   # arm64 on the Always Free Ampere VM

export DEBIAN_FRONTEND=noninteractive
apt-get update -q
apt-get install -yq git curl ffmpeg python3 python3-pip build-essential cmake jq debian-keyring debian-archive-keyring apt-transport-https

# Node 22
curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
apt-get install -yq nodejs

# Caddy (HTTPS in front of the bridge)
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor --yes -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' > /etc/apt/sources.list.d/caddy-stable.list
apt-get update -q && apt-get install -yq caddy

# Chrome (headless, for Instagram embeds)
# Google Chrome has no arm64 build: use the Chromium snap there
if [ "$ARCH" = amd64 ]; then
  curl -fsSL -o /tmp/chrome.deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
  apt-get install -yq /tmp/chrome.deb && ln -sf /usr/bin/google-chrome /usr/local/bin/chromium
else
  snap install chromium && ln -sf /snap/bin/chromium /usr/local/bin/chromium
fi

# yt-dlp
curl -fsSL -o /usr/local/bin/yt-dlp https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_linux$([ "$ARCH" = arm64 ] && echo _aarch64)
chmod +x /usr/local/bin/yt-dlp

# whisper.cpp + small model
if [ ! -x /usr/local/bin/whisper-cli ]; then
  git clone --depth 1 https://github.com/ggml-org/whisper.cpp /opt/whisper.cpp
  cmake -S /opt/whisper.cpp -B /opt/whisper.cpp/build -DCMAKE_BUILD_TYPE=Release
  cmake --build /opt/whisper.cpp/build -j"$(nproc)" --target whisper-cli
  cp /opt/whisper.cpp/build/bin/whisper-cli /usr/local/bin/
  cp /opt/whisper.cpp/build/src/libwhisper.so* /opt/whisper.cpp/build/ggml/src/libggml*.so* /usr/local/lib/ 2>/dev/null || true
  ldconfig
fi

# user
id $U >/dev/null 2>&1 || useradd -m -s /bin/bash $U
mkdir -p /home/$U/.ssh /home/$U/models
# Oracle's root key only prints "login as ubuntu": take the ubuntu user's key
cp /home/ubuntu/.ssh/authorized_keys /home/$U/.ssh/authorized_keys
[ -f /home/$U/models/ggml-small.bin ] || curl -fsSL -o /home/$U/models/ggml-small.bin https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin
[ -f /home/$U/.ssh/id_ed25519 ] || ssh-keygen -t ed25519 -N '' -C "whatsapp-assistant deploy key" -f /home/$U/.ssh/id_ed25519
ssh-keyscan github.com >> /home/$U/.ssh/known_hosts 2>/dev/null
chown -R $U:$U /home/$U
chmod 700 /home/$U/.ssh

# Claude Code, installed for the assistant user
sudo -iu $U bash -c 'curl -fsSL https://claude.ai/install.sh | bash'

# bridge service
cat > /etc/systemd/system/whatsapp-assistant.service <<EOF
[Unit]
Description=WhatsApp assistant bridge
After=network-online.target

[Service]
User=$U
WorkingDirectory=/home/$U/whatsapp-assistant
Environment=PATH=/home/$U/.local/bin:/usr/local/bin:/usr/bin:/bin
Environment=CLAUDE_BIN=/home/$U/.local/bin/claude
ExecStart=/usr/bin/node server.mjs
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload

cat > /etc/caddy/Caddyfile <<EOF
$HOST {
  @bridge path /webhook /health /privacy /whoop/* /jarvis /jarvis/*
  handle @bridge {
    reverse_proxy 127.0.0.1:8787
  }
  handle {
    respond 404
  }
}
EOF
systemctl restart caddy

# Oracle images ship iptables rules that reject everything but SSH, and Oracle advises against ufw.
# Open 80/443 above the REJECT rule. Also add them to the VCN security list in the console.
for p in 443 80; do
  iptables -C INPUT -p tcp --dport $p -j ACCEPT 2>/dev/null || iptables -I INPUT 6 -m state --state NEW -p tcp --dport $p -j ACCEPT
done
netfilter-persistent save
systemctl restart caddy   # retry HTTPS now that 80/443 are open
echo "setup done"
