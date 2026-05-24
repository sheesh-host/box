#!/bin/bash -e

# Send the log output from this script to user-data.log, syslog, and the console
# From: https://alestic.com/2010/12/ec2-user-data-output/
exec > >(tee /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1

source /opt/sheesh/shared/scripts/functions.sh

/opt/sheesh/shared/scripts/attach-ebs.sh \
  -i ${ebs_volume_id} \
  -p ${volume_mount} \
  -u root \
  -g root
/opt/sheesh/shared/scripts/associate-address.sh \
  -a ${allocation_id}
/home/caddy/init.sh \
  -d ${volume_mount}/proxy
/home/git-sync/init.sh \
  -d ${volume_mount}/git
/home/confd/init.sh -p ${name_prefix}
