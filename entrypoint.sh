#!/bin/bash
set -e
CONFIG_ROOT=/etc/haproxy/mount
CERTS_ROOT=/etc/haproxy/certs
SFTP_PORT=${SFTP_PORT:-22}

# --- Initialization Logic ---

if [[ -z "${SFTP_USER}" ]]; then
  echo "[*] Skip to set up SFTP"
else
  echo "[*] Setting up SFTP"
  # Populate config
  sed "s/@SFTP_USER@/${SFTP_USER}/" \
    /etc/ssh/sshd_config.template >/etc/ssh/sshd_config
  # Create user if not already created
  if ! id "${SFTP_USER}" &>/dev/null; then
    useradd -m -d /home/"${SFTP_USER}" -s /bin/bash "${SFTP_USER}"
  fi
  echo "${SFTP_USER}:${SFTP_AUTH}" | chpasswd
  mkdir -p "${CERTS_ROOT}/uploads/haproxy"
  chown -R "${SFTP_USER}:${SFTP_USER}" "${CERTS_ROOT}/uploads"
  # For OpenSSH to chroot, dir must be owned by root:root
  chown root:root "${CERTS_ROOT}"
  chmod 755 "${CERTS_ROOT}"
fi

# --- Process Management Functions ---

start_sshd() {
  if [[ ! -z "${SFTP_USER}" ]]; then
    echo "[*] Starting sshd on ${SFTP_PORT}/tcp"
    /usr/sbin/sshd -p "${SFTP_PORT}" -D &
  fi
}

start_acme() {
  if [[ ! -z "${REDIS_MASTER_NAME}" ]]; then
    echo "[*] Starting acme-handler"
    acme-handler -D &
  fi
}

start_dataplane() {
  RUN_API="dataplaneapi -f ${CONFIG_ROOT}/dataplaneapi.yml"
  echo "[*] ${RUN_API}"
  ${RUN_API} &
}

# --- Main Monitor Loop ---

# Initial Start
start_sshd
start_acme
start_dataplane

# HAProxy runs in the foreground as the "Master" process
RUN_HAP="exec haproxy -W -db -f ${CONFIG_ROOT}/haproxy.cfg -p /run/haproxy.pid"
echo "[*] ${RUN_HAP}"
${RUN_HAP} &
HAP_PID=$!

# Monitor Loop: Runs as long as HAProxy is alive
while kill -0 $HAP_PID 2>/dev/null; do

  # Check sshd (if enabled)
  if [[ ! -z "${SFTP_USER}" ]] && ! pgrep -x "sshd" > /dev/null; then
    echo "[!] sshd died! Restarting..."
    start_sshd
  fi

  # Check acme-handler (if enabled)
  if [[ ! -z "${REDIS_MASTER_NAME}" ]] && ! pgrep -f "acme-handler" > /dev/null; then
    echo "[!] acme-handler died! Restarting..."
    start_acme
  fi

  # Check dataplaneapi
  if ! pgrep -f "dataplaneapi" > /dev/null; then
    echo "[!] dataplaneapi died! Restarting..."
    start_dataplane
  fi

  sleep 5
done

echo "[*] HAProxy has exited. Stopping container."
exit $?
