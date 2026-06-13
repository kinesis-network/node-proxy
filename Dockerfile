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
# Custom HAProxy 3.4 image linked against OpenSSL instead of AWS-LC.
# haproxytech's official images (both :3.3 and :3.4 tags) now ship AWS-LC, which
# rejects the nodes' self-signed *leaf* certs (no CA:TRUE / keyCertSign) under
# `verify required`, so every gRPC/WS backend TLS handshake fails (503 SC--);
# OpenSSL accepts such certs as trust anchors, AWS-LC does not. This image is
# built from haproxytech/haproxy-docker-ubuntu (3.4) with USE_OPENSSL=1 in place
# of USE_OPENSSL_AWSLC=1.
# Durable fix: regenerate node certs as proper CAs (IsCA + BasicConstraintsValid
# + KeyUsageCertSign in kinesis-dynamo's utils/crypto.go); after that we can move
# back to the stock haproxytech (AWS-LC) image. See commit 55411e0 for the
# original 3.3 -> 3.4 bump.
FROM kinesisorg/haproxy-ubuntu-openssl:3.4.0

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
