#!/bin/bash

set -euox pipefail

source /opt/sheesh/shared/scripts/functions.sh

_init() {
  local -r data_dir=$1
  cd /home/caddy || exit
  # ensure caddy data-dir exists on mounted EBS volume
  mkdir -p "${data_dir}"
  chown caddy:root -R "${data_dir}"

  ln -s /home/caddy/caddy-watcher.{path,service} /etc/systemd/system/
  ln -s /home/caddy/caddy.service /etc/systemd/system/caddy.service
  systemctl daemon-reload
  systemctl enable caddy-watcher.{path,service}
  systemctl start caddy-watcher.path
}

_show_help() {
  cat <<-EOF
	Usage: ./init [-hd]
	Initialize caddy

		-h, -help,          --help         Display help
		-d, -data-dir,      --data-dir     Data dir (Default: /var/lib/sheesh/proxy)
	EOF
}

_main() {
  local data_dir=/var/lib/sheesh/proxy
  # ref: https://stackoverflow.com/a/52674277
  options=$(getopt -o hd: -l help,data-dir: -a -- "$@")
  eval set -- "$options"
  unset options
  while true; do
    case $1 in
      '-h' | '--help')
        _show_help
        exit 0
        ;;
      '-d' | '--data-dir')
        shift
        data_dir=$1
        ;;
      '--')
        shift
        break
        ;;
    esac
    shift
  done

  _init "${data_dir}"
}

_main "$@"
