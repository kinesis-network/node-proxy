# https://www.haproxy.com/documentation/haproxy-data-plane-api/installation/install-on-haproxy/
FROM haproxytech/haproxy-ubuntu:3.3
COPY entrypoint.sh entrypoint.sh
COPY reload.sh /etc/haproxy/reload.sh
COPY restart.sh /etc/haproxy/restart.sh
RUN chmod +x /etc/haproxy/restart.sh \
  && chmod +x /etc/haproxy/reload.sh \
  && chmod +x /entrypoint.sh
CMD ["/entrypoint.sh"]
