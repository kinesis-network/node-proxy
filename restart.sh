#!/bin/sh
exec haproxy \
  -f /etc/haproxy/mount/haproxy.cfg \
  -p /run/haproxy.pid
