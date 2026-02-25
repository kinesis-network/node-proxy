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
FROM haproxytech/haproxy-ubuntu:3.4

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
      openssh-server \
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
RUN chmod +x /etc/haproxy/restart.sh \
  && chmod +x /etc/haproxy/reload.sh \
  && chmod +x /entrypoint.sh
CMD ["/entrypoint.sh"]
