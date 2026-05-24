#!/bin/bash -x

set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
export ARCH=arm64
export OS=linux

source /opt/sheesh/shared/scripts/functions.sh

_install_golang() {
  local -r version=$1
  local -r os="$(uname -s)"
  local -r arch="$(uname -m)"

  case $os in
    "Linux")
      case $arch in
        "x86_64")
          ARCH=amd64
          ;;
        "aarch64")
          ARCH=arm64
          ;;
        "armv6" | "armv7l")
          ARCH=armv6l
          ;;
        "armv8")
          ARCH=arm64
          ;;
        .*386.*)
          ARCH=386
          ;;
      esac
      platform="linux-$ARCH"
      ;;
    *)
      echo "Install Golang: unsupported platform"
      exit 1
      ;;
  esac
  local -r pkg="go$version.$platform.tar.gz"
  local -r url="https://go.dev/dl/${pkg}"
  echo "Downloading golang from ${url}"
  curl -Lo golang.tgz "${url}"
  tar -C /usr/local -xzf golang.tgz && rm -rf golang.tgz
  export PATH=$PATH:/usr/local/go/bin
}

_build_git_sync() {
  local -r ref=$1
  git clone https://github.com/kubernetes/git-sync.git src
  pushd src
  {
    git reset --hard "${ref}"

    # copy from /build/build.sh
    # got error when calling build.sh directly
    export CGO_ENABLED=0
    export GOARCH="${ARCH}"
    export GOOS="${OS}"
    # Not debugging - trim paths, disable symbols and DWARF.
    goasmflags="all=-trimpath=$(pwd)"
    gogcflags="all=-trimpath=$(pwd)"
    goldflags="-s -w"

    always_ldflags="-X $(go list -m)/pkg/version.VERSION=${GIT_SYNC_VERSION}"
    go install -v \
      -installsuffix "static" \
      -gcflags="${gogcflags}" \
      -asmflags="${goasmflags}" \
      -ldflags="${always_ldflags} ${goldflags}" \
      ./...

    mv ~/go/bin/git-sync /usr/local/bin/
  }
  popd
  rm -rf src
}

_main() {
  _add_svc_user "git-sync"
  cd /home/git-sync

  apt-get update -y
  # https://github.com/kubernetes/git-sync/blob/v4.0.0/Dockerfile.in#L56-L71
  # -p (packages) ca-certificates coreutils socat openssh-client
  apt-get install -y jq build-essential socat
  _install_golang 1.22.7

  # TODO: clean up golang and build-essentials
  _build_git_sync "${GIT_SYNC_VERSION}"
  mkdir -p .ssh

  # prep git-sync service for the content repo
  mv /tmp/build-assets/git-sync/content/confd/conf.d/* /etc/confd/conf.d/
  mv /tmp/build-assets/git-sync/content/confd/templates/* /etc/confd/templates/

  mv /tmp/build-assets/git-sync/content/content-watcher.{path,service} ./
  mv /tmp/build-assets/git-sync/content/content.service ./content.service
  systemd-analyze verify /home/git-sync/content-watcher.*
  systemd-analyze verify /home/git-sync/content.*

  mv /tmp/build-assets/git-sync/known_hosts ./.ssh/known_hosts
  mv /tmp/build-assets/git-sync/init.sh ./init.sh
  chown -R git-sync:root /home/git-sync/
}

_main "$@"
