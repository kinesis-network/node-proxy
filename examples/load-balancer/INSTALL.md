# Installation

```
docker run -d \
  --network=host \
  -e SFTP_USER= \
  -v /home/ubuntu/node-proxy/mount/certs:/etc/haproxy/certs \
  -v /home/ubuntu/node-proxy/mount:/etc/haproxy/mount \
  kinesisorg/node-proxy
```
