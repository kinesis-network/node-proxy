# Installation

```
export ROOTDIR=${PWD}/examples/load-balancer/mount
docker rm -f $(docker ps -qaf ancestor=kinesisorg/node-proxy)
docker run -d \
  --network=host \
  --restart=always \
  -e SFTP_AUTH=password \
  -e ACME_SOCKET=/tmp/acme-sidecar.sock \
  -e REDIS_ADDRS=redis1.apps.kinesiscloud.com:1234,redis2.apps.kinesiscloud.com:1234 \
  -e REDIS_MASTER_NAME=kinesis-load-balancer \
  -e REDIS_PASSWORD=password \
  -e CACERT_BASE64=xxxx \
  -v ${ROOTDIR}/certs:/etc/haproxy/certs \
  -v ${ROOTDIR}:/etc/haproxy/mount \
  -v ${ROOTDIR}:/var/log/haproxy \
  kinesisorg/node-proxy
docker logs -f $(docker ps -qaf ancestor=kinesisorg/node-proxy)
```
