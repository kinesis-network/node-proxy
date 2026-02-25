#!/bin/bash
set -e
CONFIG_ROOT=/etc/haproxy/mount
CERTS_ROOT=/etc/haproxy/certs
SFTP_PORT=${SFTP_PORT:-22}

if [[ -z "${SFTP_USER}" ]]; then
  echo "[*] Skip to set up SFTP"
else
  echo "[*] Setting up SFTP"
  # Populate config
  sed 's/@SFTP_USER@/'${SFTP_USER}'/' \
    /etc/ssh/sshd_config.template >/etc/ssh/sshd_config
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
  echo "[*] Starting sshd on ${SFTP_PORT}/tcp"
  /usr/sbin/sshd -p ${SFTP_PORT} -D&
fi

if [[ ! -z "${REDIS_MASTER_NAME}" ]]; then
  echo "[*] Starting acme-handler"
  acme-handler -D&
fi

RUN_API="dataplaneapi -f ${CONFIG_ROOT}/dataplaneapi.yml"
echo "[*] ${RUN_API}"
${RUN_API} &

RUN_HAP="exec haproxy -W -db -f ${CONFIG_ROOT}/haproxy.cfg -p /run/haproxy.pid"
echo "[*] ${RUN_HAP}"
${RUN_HAP}
