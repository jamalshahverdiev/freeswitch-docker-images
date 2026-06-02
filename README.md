# freeswitch-docker-images

Scheduled GitHub Actions automation that watches for new FreeSWITCH releases,
builds them on the matching Debian base, and pushes to
[`jamalshahverdiev/freeswitch`](https://hub.docker.com/r/jamalshahverdiev/freeswitch).

## How it works

1. A daily cron (`.github/workflows/build-and-push.yml`) runs `scripts/plan-builds.sh`.
2. For every entry in `matrix.json` the planner discovers the latest version, by one
   of two methods (per the entry's `method` field):
   - **`token-apt`** — spins up the base image, wires up the SignalWire token apt
     repo, and asks `apt-cache madison` what is available for that codename.
   - **`source`** — picks the latest git tag matching `ref_prefix` (e.g. `v1.6.`)
     via `git ls-remote`.
3. If a version exists **and** the tag is not yet on Docker Hub, it is queued.
   Anything not found is logged and skipped — never a silent failure.
4. The `build` job builds each queued image with the per-entry Dockerfile
   (`Dockerfile` for apt, `Dockerfile.source` for source) and pushes it.

The SignalWire Personal Access Token is only ever passed as a BuildKit
`--mount=type=secret`, so it never lands in an image layer.

## Version / base matrix

Old FreeSWITCH lines do not compile on modern Debian (OpenSSL 3.x removed the
APIs they use), so each line is pinned to its own era:

| FreeSWITCH | Debian base   | Method      | Notes |
|------------|---------------|-------------|-------|
| 1.6        | `debian:jessie` (8)   | source     | Latest `v1.6.*` tag; needs OpenSSL 1.0.2 (bundled libsrtp breaks on OpenSSL 1.1) |
| 1.8        | `debian:buster` (10)  | source     | Latest `v1.8.*` tag, compiled on Debian 10 |
| 1.10       | `debian:bookworm` (12)| token-apt  | Current stable, also tagged `latest` |
| 1.11       | `debian:trixie` (13)  | token-apt  | Debian 13; trixie token repo is currently flaky |

### Source builds (1.6 / 1.8)

`Dockerfile.source` + `scripts/build-from-source.sh` clone the git tag and compile
on the era-correct base. The script rewrites `sources.list` to
`archive.debian.org` (those Debian suites are EOL) and disables the stale
`Valid-Until` check, then installs build deps and runs
`./bootstrap.sh && ./configure && make && make install` (prefix
`/usr/local/freeswitch`).

This is **best-effort**: a specific old tag may need a configure flag or a module
disabled. Tune `build-from-source.sh` (e.g. `cp build/modules.conf.in modules.conf`
and comment out a failing module) if a build breaks.

## Tags produced

For an available version `X.Y.Z` on codename `cn`:

- `jamalshahverdiev/freeswitch:X.Y.Z-cn` — immutable, pinned
- `jamalshahverdiev/freeswitch:X.Y`       — moving, latest of the line
- `jamalshahverdiev/freeswitch:latest`    — only for the entry whose `aliases` include it (currently 1.10)

## Required GitHub secrets

| Secret | Purpose |
|--------|---------|
| `SIGNALWIRE_TOKEN`  | SignalWire PAT used to authenticate against the token apt repo |
| `DOCKERHUB_USERNAME`| Docker Hub login (push) |
| `DOCKERHUB_TOKEN`   | Docker Hub access token (push) |

## Manual run

`Actions → Build & push FreeSWITCH images → Run workflow`. Tick **force** to
rebuild even when the tag already exists.

## Local probe

```bash
SIGNALWIRE_TOKEN=pat_xxx DOCKERHUB_REPO=jamalshahverdiev/freeswitch \
  ./scripts/plan-builds.sh
```

Prints the planned build matrix as JSON (requires Docker + jq).
