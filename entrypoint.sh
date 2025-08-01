#!/bin/bash
CONFIG_ROOT=/etc/haproxy/mount

RUN_API="dataplaneapi -f ${CONFIG_ROOT}/dataplaneapi.yml"
echo ${RUN_API}
${RUN_API} &

RUN_HAP="exec haproxy -W -db -f ${CONFIG_ROOT}/haproxy.cfg -p /run/haproxy.pid"
echo ${RUN_HAP}
${RUN_HAP}
