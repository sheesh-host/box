#!/bin/bash
# Mount EBS volume for Nitro (>t3) Instances
set -eu

_mount() {
  local -r ebs_id=$1
  local -r mount_point=$2
  local -r user_id=$3
  local -r group_id=$4

  # ref: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-instance-metadata.html
  local -r imds_token=$(curl -fsX PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
  local -r instance_id=$(curl -LfsH "X-aws-ec2-metadata-token: ${imds_token}" http://169.254.169.254/latest/meta-data/instance-id)

  while [ "$(aws ec2 describe-volumes --volume-ids "${ebs_id}" | jq -r '.Volumes[].State')" != "available" ]; do
    echo "waiting for EBS Volume to be available to mount..."
    sleep 10
  done

  # recommended device names for ebs /dev/sd[f-p], stored in a bash array
  # https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/device_naming.html#available-ec2-device-names
  local -r valid_device_names=('/dev/sd'{f..p})
  local -r existing_device_names=$(aws ec2 describe-instances --instance-ids "${instance_id}" --query "Reservations[].Instances[].BlockDeviceMappings[].DeviceName" --output json | jq -c)
  # Dividing a string by another splits the first using the second as separators. ($valid / " " -> array of valid device names)
  # https://stedolan.github.io/jq/manual/#Multiplication,division,modulo:*,/,and%
  # the - operator can be used on arrays to remove all occurrences of the second array's elements from the first array
  # https://stedolan.github.io/jq/manual/#Subtraction:-
  local -r next_device_name=$(echo "${existing_device_names}" | jq -r --arg valid "${valid_device_names[*]}" '$valid / " " - . | .[0]')

  aws ec2 attach-volume --instance-id "${instance_id}" --volume-id "${ebs_id}" --device "${next_device_name}"
  while [ "$(aws ec2 describe-volumes --volume-ids "${ebs_id}" | jq -r '.Volumes[].Attachments[] | select(.State == "attached") .InstanceId')" != "${instance_id}" ]; do
    echo "waiting for EBS volume to be attached to this instance..."
    sleep 10
  done

  # Nitro instances mount EBS under /dev/nvme[0-26]n1 instead of /dev/xdx
  # Identify device name through SERIAL (volXXXXX)
  # ${ebs_id/-/} turns vol-XXXXX into volXXXXX
  # .name is nvme[0-26]n1 without `/dev/` prefix
  local dev_name
  dev_name=$(lsblk -o +SERIAL --json | jq -r ".blockdevices[] | select(.serial == \"${ebs_id/-/}\") | \"/dev/\(.name)\"")
  while [ -z "${dev_name}" ]; do
    echo "dev_name unresolved, sleeping ..."
    sleep 5
    dev_name=$(lsblk -o +SERIAL --json | jq -r ".blockdevices[] | select(.serial == \"${ebs_id/-/}\") | \"/dev/\(.name)\"")
  done
  echo "data device name=\"${dev_name}\""

  if [ "$(file -b -s "${dev_name}")" == "data" ]; then
    echo "creating filesystem"
    mkfs -t ext4 "${dev_name}"
    e2label "${dev_name}" data
  fi

  mkdir -p "${mount_point}"
  mount "${dev_name}" "${mount_point}"

  # Persist the volume in /etc/fstab so it gets mounted again
  #
  # You can use the device name, such as /dev/xvdf, in /etc/fstab, but
  # device names can change, UUID persists throughout the life of the partition.
  # NOTE: Each partition can have different mountpoint and uuid
  # following jq expression fetches all the UUID, ignores null and mountpoints, return first
  local -r dev_uuid=$(lsblk -o +UUID "${dev_name}" --json | jq -r '[..|.uuid? | values] | .[0]')

  local -r has_data_entry=$(grep "${mount_point}" /etc/fstab)
  if [ -z "${has_data_entry}" ]; then
    echo "UUID=${dev_uuid}  ${mount_point}  ext4  defaults,nofail  0  2" >>/etc/fstab
  else
    sed -ie "s:\(.*\)\(\s${mount_point}\s\s*\)\(.*\):UUID=${dev_uuid}\2\3:" /etc/fstab
  fi

  chown -R "${user_id}":"${group_id}" "${mount_point}"
}

_show_help() {
  cat <<-EOF
	Usage: ./attach-ebs.sh -i <ebs-id> -p <mount-point> -u <user-id> -g <group-id> [-h]
	Attach EBS Volume, mount and chown

		-h, -help,          --help                  Display help
		-i, -ebs-id,        --ebs-id                Set EBS Volume Id
		-p, -mount-point,   --mount-point           Set mount point for EBS Volume
		-u, -user-id,       --user-id               Set UID to chown mount point
		-g, -group-id,      --group-id              Set GID to chown mount point
	EOF
}

_main() {
  local ebs_id mount_point user_id group_id
  # ref: https://stackoverflow.com/a/52674277
  options=$(getopt -o hi:p:u:g: -l help,ebs-id:,mount-point:,user-id:,group-id: -a -n attach-ebs.sh -- "$@")
  eval set -- "$options"
  unset options
  while true; do
    case "$1" in
      '-h' | '--help')
        _show_help
        exit 0
        ;;
      '-i' | '--ebs-id')
        shift
        ebs_id=$1
        ;;
      '-p' | '--mount-point')
        shift
        mount_point=$1
        ;;
      '-u' | '--user-id')
        shift
        user_id=$1
        ;;
      '-g' | '--group-id')
        shift
        group_id=$1
        ;;
      '--')
        shift
        break
        ;;
    esac
    shift
  done

  _mount \
    "${ebs_id}" \
    "${mount_point}" \
    "${user_id}" \
    "${group_id}"
}

_main "$@"
