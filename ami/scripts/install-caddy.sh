#!/bin/bash -x
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

ARCH="arm64"

source /opt/sheesh/shared/scripts/functions.sh

_main() {
  # https://caddyserver.com/docs/running#manual-installation
  _add_svc_user "caddy"
  cd /home/caddy

  # TODO: Add support for checksum checks
  # https://github.com/caddyserver/caddy/releases/download/v2.5.2/caddy_2.5.2_checksums.txt
  # NOTE: CADDY_VERSION is expected without "v" prefix
  _install_github_release \
    "caddyserver/caddy" \
    "v${CADDY_VERSION}" \
    "caddy" \
    "caddy_${CADDY_VERSION}_linux_${ARCH}.tar.gz" \
    true

  mv /tmp/build-assets/caddy/init.sh /home/caddy/init.sh
  mv /tmp/build-assets/caddy/caddy-watcher.{path,service} /home/caddy/
  mv /tmp/build-assets/caddy/caddy.service /home/caddy/caddy.service
  systemd-analyze verify /home/caddy/caddy-watcher.*
  systemd-analyze verify /home/caddy/caddy.*

  mv /tmp/build-assets/caddy/confd/conf.d/* /etc/confd/conf.d/
  mv /tmp/build-assets/caddy/confd/templates/* /etc/confd/templates/
  chown -R caddy:root /home/caddy/
}

_main "$@"
