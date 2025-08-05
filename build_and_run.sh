#!/bin/bash
MOUNTDIR=${PWD}/mount
HTTP_PORT=5555
HTTPS_PORT=55555
HTTPS_HOST=admin1.nodes.kinesiscloud.com
NMAGENT_AUTH=password

docker rm -f $(docker ps -aqf ancestor=kinesisorg/node-proxy)
docker rmi kinesisorg/node-proxy

[ -d ${MOUNTDIR} ] || mkdir ${MOUNTDIR}
[ -d ${MOUNTDIR}/certs ] || mkdir ${MOUNTDIR}/certs

cp ${PWD}/selfsign.pem ${MOUNTDIR}/certs/server.pem

sudo rm ${MOUNTDIR}/dataplaneapi.yml
cp dataplaneapi.yml.template ${MOUNTDIR}/dataplaneapi.yml
sed -i "s/__HTTP_PORT__/${HTTP_PORT}/g" ${MOUNTDIR}/dataplaneapi.yml

cp haproxy.cfg.template ${MOUNTDIR}/haproxy.cfg
sed -i "s/__NMAGENT_AUTH__/${NMAGENT_AUTH}/g" ${MOUNTDIR}/haproxy.cfg
sed -i "s/__HTTP_PORT__/${HTTP_PORT}/g" ${MOUNTDIR}/haproxy.cfg
sed -i "s/__HTTPS_PORT__/${HTTPS_PORT}/g" ${MOUNTDIR}/haproxy.cfg
sed -i "s/__HTTPS_HOST__/${HTTPS_HOST}/g" ${MOUNTDIR}/haproxy.cfg

docker build -t kinesisorg/node-proxy .
CONTID=$(docker run -d \
  -p 22222:22/tcp \
  -p 55555:55555/tcp \
  -p 5555:5555/tcp \
  -e SFTP_AUTH=password \
  -v ${PWD}/mount/certs:/etc/haproxy/certs \
  -v ${PWD}/mount:/etc/haproxy/mount \
  kinesisorg/node-proxy)
echo Started ${CONTID}

HTTP_URL="http://localhost:${HTTP_PORT}/v3/info"
until curl -fsu "nmagent:${NMAGENT_AUTH}" ${HTTP_URL} >/dev/null; do
  sleep 1
done

curl -ksu "nmagent:${NMAGENT_AUTH}" \
  -H "Host: ${HTTPS_HOST}" \
  https://localhost:${HTTPS_PORT}/v3/info
