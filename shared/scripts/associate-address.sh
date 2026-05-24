#!/bin/bash
# Associate EIP to instance-id
set -eu

_associate() {
  local -r allocation_id=$1

  # ref: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-instance-metadata.html
  local -r imds_token=$(curl -fsX PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
  local -r instance_id=$(curl -LfsH "X-aws-ec2-metadata-token: ${imds_token}" http://169.254.169.254/latest/meta-data/instance-id)

  aws ec2 associate-address --instance-id "${instance_id}" --allocation-id "${allocation_id}"
  while [ "$(aws ec2 describe-addresses --allocation-ids "${allocation_id}" --query "Addresses[].InstanceId" --output text)" != "${instance_id}" ]; do
    echo "waiting for EIP to be associated to this instance..."
    sleep 10
  done
}

_show_help() {
  cat <<-EOF
	Usage: ./associate-address.sh -a <allocation-id> [-h]
	Attach EIP

		-h, -help,          --help                  Display help
		-i, -allocation-id, --allocation-id         Set Allocation Id
	EOF
}

_main() {
  local allocation_id
  # ref: https://stackoverflow.com/a/52674277
  options=$(getopt -o ha: -l help,allocation-id: -a -n associate-address.sh -- "$@")
  eval set -- "$options"
  unset options
  while true; do
    case "$1" in
      '-h' | '--help')
        _show_help
        exit 0
        ;;
      '-a' | '--allocation-id')
        shift
        allocation_id=$1
        ;;
      '--')
        shift
        break
        ;;
    esac
    shift
  done

  _associate \
    "${allocation_id}"
}

_main "$@"
