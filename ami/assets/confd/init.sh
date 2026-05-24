#!/bin/bash

set -euox pipefail

source /opt/sheesh/shared/scripts/functions.sh

_init() {
  local -r prefix=$1
  cd /home/confd || exit

  export NAME_PREFIX="${prefix}"
  # shellcheck disable=SC2016
  envsubst '$NAME_PREFIX' <"/home/confd/confd.toml.tpl" >"/etc/confd/confd.toml"

  ln -s /home/confd/confd.service /etc/systemd/system/confd.service
  systemctl daemon-reload
  systemctl enable --now confd.service
}

_show_help() {
  cat <<-EOF
	Usage: ./init [-h]
	Initialize confd

		-h, -help,          --help                  Display help
		-p, -prefix,        --prefix                The string to prefix to keys. ("/")
	EOF
}

_main() {
  local prefix
  # ref: https://stackoverflow.com/a/52674277
  options=$(getopt -o hp: -l help,prefix: -a -n init.sh -- "$@")
  eval set -- "$options"
  unset options
  while true; do
    case "$1" in
      '-h' | '--help')
        _show_help
        exit 0
        ;;
      '-p' | '--prefix')
        shift
        prefix=$1
        ;;
      '--')
        shift
        break
        ;;
    esac
    shift
  done

  _init "${prefix}"
}

_main "$@"
