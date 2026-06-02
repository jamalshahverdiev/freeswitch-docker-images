# freeswitch-docker-images

Scheduled GitHub Actions automation that watches for new FreeSWITCH releases,
builds them on the matching Debian base, and pushes to
[`jamalshahverdiev/freeswitch`](https://hub.docker.com/r/jamalshahverdiev/freeswitch).

## How it works

1. A daily cron (`.github/workflows/build-and-push.yml`) runs `scripts/plan-builds.sh`.
2. For every entry in `matrix.json` the planner spins up the base image, wires up
   the SignalWire **token** apt repo, and asks `apt-cache madison` which version is
   available for that Debian codename.
3. If a version exists **and** the corresponding tag is not yet on Docker Hub, the
   pair is queued. Anything not found in the repo is logged and skipped — never a
   silent failure.
4. The `build` job builds each queued image with `Dockerfile` and pushes it.

The SignalWire Personal Access Token is only ever passed as a BuildKit
`--mount=type=secret`, so it never lands in an image layer.

## Version / base matrix

Old FreeSWITCH lines do not compile on modern Debian (OpenSSL 3.x removed the
APIs they use), so each line is pinned to its own era:

| FreeSWITCH | Debian base   | apt repo path     | Status today |
|------------|---------------|-------------------|--------------|
| 1.6        | `debian:stretch` (9)  | debian-release  | **Skipped** — not in token repo, Debian 9 archive offline |
| 1.8        | `debian:buster` (10)  | debian-release  | **Skipped** — not in token repo |
| 1.10       | `debian:bookworm` (12)| debian-release  | **Builds** — current stable, also tagged `latest` |
| 1.11       | `debian:trixie` (13)  | debian-unstable | Best-effort — Debian 13 token repo currently broken |

The token apt repo realistically serves only the **1.10.x** line. 1.6/1.8 are not
published there at all; to actually produce those images you would need to switch
their matrix entries to a source build (`git checkout v1.6.x && ./configure && make`)
on the era-correct base — left as a follow-up.

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
