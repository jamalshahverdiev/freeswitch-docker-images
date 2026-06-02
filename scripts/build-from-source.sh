#!/usr/bin/env bash
# Builds FreeSWITCH from a git tag/branch on an (often EOL) Debian base.
# Best-effort: very old lines may need per-version configure tweaks.
set -euo pipefail

: "${FS_REF:?FS_REF (git tag or branch) is required}"
export DEBIAN_FRONTEND=noninteractive

# EOL Debian suites are served from archive.debian.org with stale Valid-Until,
# and the *-updates suites do not exist there (would 404 and fail apt-get update).
if grep -qiE 'jessie|stretch|buster' /etc/apt/sources.list 2>/dev/null; then
  sed -i -E 's#https?://[^ ]*debian.org/debian-security#http://archive.debian.org/debian-security#g' /etc/apt/sources.list
  sed -i -E 's#https?://[^ ]*debian.org/debian#http://archive.debian.org/debian#g' /etc/apt/sources.list
  sed -i -E '/-updates/d' /etc/apt/sources.list
  echo 'Acquire::Check-Valid-Until "false";' > /etc/apt/apt.conf.d/99no-check-valid
fi

apt-get update
apt-get install -y --no-install-recommends \
  git ca-certificates wget \
  build-essential automake autoconf libtool libtool-bin pkg-config yasm \
  libssl-dev libcurl4-openssl-dev libpcre3-dev libedit-dev libsqlite3-dev \
  libspeex-dev libspeexdsp-dev libldns-dev libopus-dev libsndfile1-dev \
  libtiff5-dev libjpeg-dev uuid-dev zlib1g-dev libncurses5-dev libperl-dev \
  libogg-dev libvorbis-dev unixodbc-dev

git clone https://github.com/signalwire/freeswitch.git /usr/src/freeswitch
cd /usr/src/freeswitch
git checkout "$FS_REF"

# Old FreeSWITCH lines were written for older GCC; newer GCC promotes extra
# warnings to errors (-Werror). CFLAGS is appended last in the automake compile
# rule, so -Wno-error overrides the in-tree -Werror.
export CFLAGS="${CFLAGS:-} -Wno-error -Wno-deprecated-declarations"
export CXXFLAGS="${CXXFLAGS:-} -Wno-error -Wno-deprecated-declarations"

./bootstrap.sh -j
./configure --disable-dependency-tracking
make -j"$(nproc)"
make install
make sounds-install moh-install || true

cd /
rm -rf /usr/src/freeswitch
apt-get clean
rm -rf /var/lib/apt/lists/*
