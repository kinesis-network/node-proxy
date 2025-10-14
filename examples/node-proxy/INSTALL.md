# Installation

```
docker run -d \
  --restart always \
  -p 50000-50003:50000-50003/tcp \
  -p 55555:55555/tcp \
  -p 22222:22/tcp \
  -e SFTP_AUTH=password \
  -v /home/ubuntu/node-proxy:/etc/haproxy/mount \
  -v /home/ubuntu/node-proxy/certs:/etc/haproxy/certs \
  kinesisorg/node-proxy
```
