# syntax=docker/dockerfile:1.7
ARG BASE_IMAGE=debian:bookworm
FROM ${BASE_IMAGE}

ARG FS_REPO_PATH=debian-release
ARG FS_PACKAGE=freeswitch-meta-all
ARG FS_VERSION=
ENV FS_REPO_PATH=${FS_REPO_PATH} \
    FS_PACKAGE=${FS_PACKAGE} \
    FS_VERSION=${FS_VERSION}

COPY scripts/install-freeswitch.sh /tmp/install-freeswitch.sh
RUN --mount=type=secret,id=signalwire_token \
    chmod +x /tmp/install-freeswitch.sh \
    && /tmp/install-freeswitch.sh \
    && rm -f /tmp/install-freeswitch.sh

EXPOSE 5060/udp 5060/tcp 5080/udp 5080/tcp 8021/tcp 16384-32768/udp

CMD ["freeswitch", "-nf", "-nonat"]
