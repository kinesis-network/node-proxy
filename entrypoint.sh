#!/bin/bash
set -e
CONFIG_ROOT=/etc/haproxy/mount
CERTS_ROOT=/etc/haproxy/certs

# Create user if not already created
if ! id "${SFTP_USER}" &>/dev/null; then
  useradd -m -d /home/"${SFTP_USER}" -s /bin/bash "${SFTP_USER}"
fi
echo "${SFTP_USER}:${SFTP_AUTH}" | chpasswd
[ -d "${CERTS_ROOT}/uploads/haproxy" ] || mkdir -p "${CERTS_ROOT}/uploads/haproxy"
chown -R ${SFTP_USER}:${SFTP_USER} ${CERTS_ROOT}/uploads
# For OpenSSH to chroot, dir must be owned by root:root
chown root:root ${CERTS_ROOT}
chmod 755 ${CERTS_ROOT}
echo Starting sshd
/usr/sbin/sshd -D&

RUN_API="dataplaneapi -f ${CONFIG_ROOT}/dataplaneapi.yml"
echo ${RUN_API}
${RUN_API} &

RUN_HAP="exec haproxy -W -db -f ${CONFIG_ROOT}/haproxy.cfg -p /run/haproxy.pid"
echo ${RUN_HAP}
${RUN_HAP}
