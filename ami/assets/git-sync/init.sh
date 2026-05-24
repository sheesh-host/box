#!/bin/bash

set -euox pipefail

source /opt/sheesh/shared/scripts/functions.sh

_init() {
  local -r data_dir=$1
  cd /home/git-sync || exit
  # ensure git-sync data-dir exists on mounted EBS volume
  mkdir -p "${data_dir}"
  chown git-sync:root -R "${data_dir}"

  # enable content git-sync
  ln -s /home/git-sync/content-watcher.{path,service} /etc/systemd/system/
  ln -s /home/git-sync/content.service /etc/systemd/system/content.service
  systemctl daemon-reload
  systemctl enable content-watcher.{path,service}
  systemctl start content-watcher.path
}

_show_help() {
  cat <<-EOF
	Usage: ./init [-hd]
	Initialize content git-sync

		-h, -help,          --help         Display help
		-d, -data-dir,      --data-dir     Data dir (Default: /var/lib/sheesh/git)
	EOF
}

_main() {
  local data_dir=/var/lib/sheesh/git
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
