# Installation

```
export ROOTDIR=${PWD}/examples
docker rm -f $(docker ps -qaf ancestor=kinesisorg/node-proxy)
docker rmi kinesisorg/node-proxy; docker build -t kinesisorg/node-proxy .

# AppProxy
docker run -d \
  --network=host \
  --restart=always \
  --pull=always \
  -e ACME_SOCKET=/tmp/acme-sidecar.sock \
  -e REDIS_ADDRS=redis1.apps.kinesiscloud.com:1234,redis2.apps.kinesiscloud.com:1234 \
  -e REDIS_MASTER_NAME=kinesis-load-balancer \
  -e REDIS_PASSWORD=password \
  -e CACERT_BASE64=xxxx \
  -v ${ROOTDIR}/certs:/etc/haproxy/certs \
  -v ${ROOTDIR}/mount:/etc/haproxy/mount \
  -v ${ROOTDIR}/logs:/var/log/haproxy \
  kinesisorg/node-proxy

# NodeProxy
docker run -d \
  --restart always \
  --pull=always \
  -p 50000-50003:50000-50003/tcp \
  -p 443:443/tcp \
  -v ${ROOTDIR}/certs:/etc/haproxy/certs \
  -v ${ROOTDIR}/mount:/etc/haproxy/mount \
  -v ${ROOTDIR}/logs:/var/log/haproxy \
  kinesisorg/node-proxy

docker logs -f $(docker ps -qaf ancestor=kinesisorg/node-proxy)
```
