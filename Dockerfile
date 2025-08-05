# https://www.haproxy.com/documentation/haproxy-data-plane-api/installation/install-on-haproxy/
FROM haproxytech/haproxy-ubuntu:3.3

ARG SFTP_USER=nmagent
ENV SFTP_USER=${SFTP_USER}
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
      openssh-server \
  && apt-get clean && rm -rf /var/lib/apt/lists/* \
  && mkdir /run/sshd
RUN echo "\
Match User ${SFTP_USER}\n\
    ChrootDirectory /etc/haproxy/certs\n\
    ForceCommand internal-sftp\n\
    PasswordAuthentication yes\n\
    X11Forwarding no\n\
    AllowTcpForwarding no" >>/etc/ssh/sshd_config

COPY entrypoint.sh entrypoint.sh
COPY reload.sh /etc/haproxy/reload.sh
COPY restart.sh /etc/haproxy/restart.sh
RUN chmod +x /etc/haproxy/restart.sh \
  && chmod +x /etc/haproxy/reload.sh \
  && chmod +x /entrypoint.sh
CMD ["/entrypoint.sh"]
