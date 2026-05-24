#!/bin/bash

_add_svc_user() {
  local -r name=$1
  addgroup "${name}"
  adduser --system --ingroup "${name}" --home "/home/${name}/" "${name}"
  mkdir -p "/home/${name}/"
  adduser "${name}" root
  chown "${name}:root" "/home/${name}/"
  chmod g=u "/home/${name}/"
  chmod g=u /etc/passwd
}

_get_secrets() {
  local -r name=$1
  secrets=$(aws secretsmanager get-secret-value --secret-id "${name}" --query "SecretString" --output text)
  echo "${secrets}"
}

_install_awscli() {
  if command -v aws &>/dev/null; then
    echo "aws already installed, bailing... "
    return
  fi
  curl "https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip" -o "awscliv2.zip"
  # TODO: verify awscli v2 signature
  # ref: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html#install-linux-verify
  unzip awscliv2.zip
  ./aws/install
  # clean up
  rm -rf aws awscliv2.zip
}

_install_github_release() {
  local -r repo=$1
  local -r version=$2
  local -r binary=$3
  local -r asset_name=$4
  local -r tgz=${5:-false}

  # TODO: validate checksums if possible?
  if [[ "${tgz}" == "true" ]]; then
    curl -Lo "${binary}.tgz" "https://github.com/${repo}/releases/download/${version}/${asset_name}"
    tar -xzf "${binary}.tgz" && rm -rf "${binary}.tgz"
  else
    curl -Lo "${binary}" "https://github.com/${repo}/releases/download/${version}/${asset_name}"
  fi
  chmod +x "${binary}"
  mv "${binary}" /usr/local/bin/"${binary}"
}
