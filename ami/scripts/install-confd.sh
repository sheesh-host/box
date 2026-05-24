#!/bin/bash -x
# Installs confd, the config-template daemon that renders service config from
# AWS SSM Parameter Store on the box.

set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

ARCH="arm64"

source /opt/sheesh/shared/scripts/functions.sh

_main() {
  _add_svc_user "confd"
  cd /home/confd

  # https://github.com/abtreece/confd/releases
  _install_github_release \
    "abtreece/confd" \
    "${CONFD_VERSION}" \
    "confd" \
    "confd-${CONFD_VERSION}-linux-${ARCH}.tar.gz" \
    true

  mkdir -p /etc/confd/{conf.d,templates}

  # mv confd.service, confd.toml.tpl, init.sh to ~confd
  mv /tmp/build-assets/confd/* /home/confd/
  chown -R confd:root /home/confd/
}

_main "$@"
