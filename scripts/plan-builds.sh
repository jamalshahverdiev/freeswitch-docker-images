#!/usr/bin/env bash
# Decides which (version, codename) images are available but not yet on Docker
# Hub, and emits a build matrix on GITHUB_OUTPUT (keys: matrix, any).
#
# Two discovery methods per matrix entry:
#   token-apt : probe the SignalWire token apt repo via `apt-cache madison`
#   source    : pick the latest matching git tag via `git ls-remote`
set -euo pipefail

: "${SIGNALWIRE_TOKEN:?SIGNALWIRE_TOKEN is required}"
: "${DOCKERHUB_REPO:=jamalshahverdiev/freeswitch}"
MATRIX_FILE="${MATRIX_FILE:-matrix.json}"
FS_GIT="https://github.com/signalwire/freeswitch.git"

builds='[]'
count=$(jq length "$MATRIX_FILE")

# tag_exists <tag> -> 0 if already on Docker Hub
tag_exists() {
  [ "${FORCE:-false}" = "true" ] && return 1
  local code
  code=$(curl -s -o /dev/null -w '%{http_code}' \
      "https://hub.docker.com/v2/repositories/${DOCKERHUB_REPO}/tags/$1/")
  [ "$code" = "200" ]
}

# queue <base> <dockerfile> <codename> <major> <aliases-json> <tag> \
#       <repo_path> <package> <version> <ref>
queue() {
  local tags="${DOCKERHUB_REPO}:$6,${DOCKERHUB_REPO}:$4"
  local a
  while IFS= read -r a; do
    [ -n "$a" ] && tags="${tags},${DOCKERHUB_REPO}:${a}"
  done < <(jq -r '.[]' <<<"$5")
  echo "queued ${1} -> ${tags}"
  builds=$(jq -c \
      --arg base "$1" --arg dockerfile "$2" --arg codename "$3" \
      --arg repo "${7:-}" --arg pkg "${8:-}" --arg ver "${9:-}" --arg ref "${10:-}" \
      --arg tags "$tags" \
      '. += [{base_image:$base, dockerfile:$dockerfile, codename:$codename, repo_path:$repo, package:$pkg, version:$ver, ref:$ref, tags:$tags}]' \
      <<<"$builds")
}

for i in $(seq 0 $((count - 1))); do
  entry=$(jq -c ".[$i]" "$MATRIX_FILE")
  method=$(jq -r '.method // "token-apt"' <<<"$entry")
  major=$(jq -r   '.major'         <<<"$entry")
  base=$(jq -r    '.base_image'    <<<"$entry")
  codename=$(jq -r '.codename'     <<<"$entry")
  aliases=$(jq -c '.aliases // []' <<<"$entry")

  echo "::group::Plan FreeSWITCH ${major} (${codename}, ${method})"

  if [ "$method" = "source" ]; then
    ref_prefix=$(jq -r '.ref_prefix' <<<"$entry")
    esc=$(sed 's/\./\\./g' <<<"$ref_prefix")
    full=$(git ls-remote --tags --refs "$FS_GIT" \
        | awk -F/ '{print $NF}' \
        | grep -E "^${esc}[0-9]" \
        | sort -V | tail -1 || true)
    if [ -z "$full" ]; then
      echo "no git tag matching ${ref_prefix}* -> skip"; echo "::endgroup::"; continue
    fi
    clean="${full#v}"
    tag="${clean}-${codename}"
    echo "latest tag: ${full} -> tag ${tag}"
    if tag_exists "$tag"; then
      echo "tag ${tag} already on Docker Hub -> skip"; echo "::endgroup::"; continue
    fi
    queue "$base" "Dockerfile.source" "$codename" "$major" "$aliases" "$tag" "" "" "" "$full"
    echo "::endgroup::"; continue
  fi

  # token-apt
  repo=$(jq -r '.repo_path' <<<"$entry")
  pkg=$(jq -r  '.package'   <<<"$entry")
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
    echo "no package available in repo -> skip"; echo "::endgroup::"; continue
  fi
  clean=$(sed -E 's/[-~].*$//' <<<"$full")
  tag="${clean}-${codename}"
  echo "available: ${full} -> tag ${tag}"
  if tag_exists "$tag"; then
    echo "tag ${tag} already on Docker Hub -> skip"; echo "::endgroup::"; continue
  fi
  queue "$base" "Dockerfile" "$codename" "$major" "$aliases" "$tag" "$repo" "$pkg" "$full" ""
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
