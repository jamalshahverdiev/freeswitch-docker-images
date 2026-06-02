#!/usr/bin/env bash
# Probes each matrix entry against the SignalWire token apt repo, decides which
# (version, codename) pairs are available but not yet on Docker Hub, and emits a
# build matrix on GITHUB_OUTPUT (keys: matrix, any).
set -euo pipefail

: "${SIGNALWIRE_TOKEN:?SIGNALWIRE_TOKEN is required}"
: "${DOCKERHUB_REPO:=jamalshahverdiev/freeswitch}"
MATRIX_FILE="${MATRIX_FILE:-matrix.json}"

builds='[]'
count=$(jq length "$MATRIX_FILE")

for i in $(seq 0 $((count - 1))); do
  entry=$(jq -c ".[$i]" "$MATRIX_FILE")
  major=$(jq -r '.major'        <<<"$entry")
  base=$(jq -r  '.base_image'   <<<"$entry")
  codename=$(jq -r '.codename'  <<<"$entry")
  repo=$(jq -r  '.repo_path'    <<<"$entry")
  pkg=$(jq -r   '.package'      <<<"$entry")
  aliases=$(jq -c '.aliases // []' <<<"$entry")

  echo "::group::Probe FreeSWITCH ${major} (${codename})"

  full=$(docker run --rm \
      -e TOKEN="$SIGNALWIRE_TOKEN" -e REPO="$repo" -e CODENAME="$codename" -e PKG="$pkg" \
      "$base" bash -c '
        set -e
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -qq            >/dev/null 2>&1 || exit 7
        apt-get install -y -qq gnupg2 wget ca-certificates lsb-release >/dev/null 2>&1 || exit 7
        wget -q --http-user=signalwire --http-password="$TOKEN" \
          -O /usr/share/keyrings/sw.gpg \
          "https://freeswitch.signalwire.com/repo/deb/${REPO}/signalwire-freeswitch-repo.gpg" || exit 7
        echo "machine freeswitch.signalwire.com login signalwire password ${TOKEN}" > /etc/apt/auth.conf
        chmod 600 /etc/apt/auth.conf
        echo "deb [signed-by=/usr/share/keyrings/sw.gpg] https://freeswitch.signalwire.com/repo/deb/${REPO}/ ${CODENAME} main" > /etc/apt/sources.list.d/fs.list
        apt-get update -qq            >/dev/null 2>&1 || exit 7
        apt-cache madison "$PKG" 2>/dev/null | head -1 | awk "{print \$3}"
      ' 2>/dev/null || true)

  if [ -z "$full" ]; then
    echo "no package available in repo -> skip"
    echo "::endgroup::"
    continue
  fi

  clean=$(sed -E 's/[-~].*$//' <<<"$full")
  tag="${clean}-${codename}"
  echo "available: ${full} -> tag ${tag}"

  if [ "${FORCE:-false}" != "true" ]; then
    http=$(curl -s -o /dev/null -w '%{http_code}' \
        "https://hub.docker.com/v2/repositories/${DOCKERHUB_REPO}/tags/${tag}/")
    if [ "$http" = "200" ]; then
      echo "tag ${tag} already on Docker Hub -> skip"
      echo "::endgroup::"
      continue
    fi
  fi

  tags="${DOCKERHUB_REPO}:${tag},${DOCKERHUB_REPO}:${major}"
  while IFS= read -r a; do
    [ -n "$a" ] && tags="${tags},${DOCKERHUB_REPO}:${a}"
  done < <(jq -r '.[]' <<<"$aliases")

  echo "queued for build with tags: ${tags}"
  builds=$(jq -c \
      --arg base "$base" --arg repo "$repo" --arg pkg "$pkg" \
      --arg ver "$full" --arg codename "$codename" --arg tags "$tags" \
      '. += [{base_image:$base, repo_path:$repo, package:$pkg, version:$ver, codename:$codename, tags:$tags}]' \
      <<<"$builds")
  echo "::endgroup::"
done

n=$(jq length <<<"$builds")
echo "planned ${n} build(s)"

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  {
    echo "matrix=$(jq -c . <<<"$builds")"
    [ "$n" -gt 0 ] && echo "any=true" || echo "any=false"
  } >> "$GITHUB_OUTPUT"
else
  jq . <<<"$builds"
fi
