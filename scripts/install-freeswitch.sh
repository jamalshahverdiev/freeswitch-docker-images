#!/usr/bin/env bash
set -euo pipefail

: "${FS_REPO_PATH:=debian-release}"
: "${FS_PACKAGE:=freeswitch-meta-all}"
: "${FS_VERSION:=}"

TOKEN="$(cat /run/secrets/signalwire_token)"
export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y --no-install-recommends gnupg2 wget ca-certificates lsb-release
CODENAME="$(lsb_release -sc)"

wget -q --http-user=signalwire --http-password="$TOKEN" \
  -O /usr/share/keyrings/signalwire-freeswitch-repo.gpg \
  "https://freeswitch.signalwire.com/repo/deb/${FS_REPO_PATH}/signalwire-freeswitch-repo.gpg"

echo "machine freeswitch.signalwire.com login signalwire password ${TOKEN}" > /etc/apt/auth.conf
chmod 600 /etc/apt/auth.conf

cat > /etc/apt/sources.list.d/freeswitch.list <<EOF
deb [signed-by=/usr/share/keyrings/signalwire-freeswitch-repo.gpg] https://freeswitch.signalwire.com/repo/deb/${FS_REPO_PATH}/ ${CODENAME} main
EOF

apt-get update
if [ -n "$FS_VERSION" ]; then
  apt-get install -y --no-install-recommends "${FS_PACKAGE}=${FS_VERSION}"
else
  apt-get install -y --no-install-recommends "${FS_PACKAGE}"
fi

rm -f /etc/apt/auth.conf
apt-get clean
rm -rf /var/lib/apt/lists/*
