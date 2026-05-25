#!/bin/sh
# Send SIGUSR2 to the master process to trigger a clean master-worker reload
kill -12 $(cat /run/haproxy.pid)
