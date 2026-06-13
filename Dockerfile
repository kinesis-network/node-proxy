# Stage 1: Build the Go binary
FROM --platform=$BUILDPLATFORM golang:1.25-alpine AS builder
WORKDIR /app

# These ARGs are automatically filled by Docker Buildx
ARG TARGETOS
ARG TARGETARCH

COPY acme-handler/* .

# Use GOOS and GOARCH to ensure we build for the correct target
RUN CGO_ENABLED=0 GOOS=$TARGETOS GOARCH=$TARGETARCH \
  go build -ldflags="-s -w" -o acme-handler .

# Stage 2: Final HAProxy image
# https://www.haproxy.com/documentation/haproxy-data-plane-api/installation/install-on-haproxy/
#
# Pinned to 3.3 (built with OpenSSL). The 3.4 image switched to AWS-LC, which
# rejects the nodes' self-signed *leaf* certs (no CA:TRUE / keyCertSign) under
# `verify required`, so all gRPC/WS backend TLS handshakes fail (503 SC--).
# OpenSSL accepts such certs as trust anchors; AWS-LC does not.
# Only re-bump to 3.4+ after the nodes regenerate their certs as proper CAs
# (IsCA + BasicConstraintsValid + KeyUsageCertSign in kinesis-dynamo's
# utils/crypto.go). See commit 55411e0 for the original 3.3 -> 3.4 bump.
FROM haproxytech/haproxy-ubuntu:3.3

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
      openssh-server \
      syslog-ng \
  && apt-get clean && rm -rf /var/lib/apt/lists/* \
  && mkdir /run/sshd
RUN mv /etc/ssh/sshd_config /etc/ssh/sshd_config.template \
  && echo "\
Match User @SFTP_USER@\n\
    ChrootDirectory /etc/haproxy/certs\n\
    ForceCommand internal-sftp\n\
    PasswordAuthentication yes\n\
    X11Forwarding no\n\
    AllowTcpForwarding no" >>/etc/ssh/sshd_config.template

COPY --from=builder /app/acme-handler /usr/local/bin/acme-handler
COPY entrypoint.sh entrypoint.sh
COPY reload.sh /etc/haproxy/reload.sh
COPY restart.sh /etc/haproxy/restart.sh

# Add syslog-ng config
COPY syslog-haproxy.conf /etc/syslog-ng/syslog-ng.conf

RUN chmod +x /etc/haproxy/restart.sh \
  && chmod +x /etc/haproxy/reload.sh \
  && chmod +x /entrypoint.sh
CMD ["/entrypoint.sh"]
