# Shared utilities across Packer AMIs

Currently it is up to each packer build script to copy these over into the final AMI.

for example:

```hcl
build {
  sources = [ ... ]

  # https://www.packer.io/docs/debugging#issues-installing-ubuntu-packages
  provisioner "shell" {
    inline = ["cloud-init status --wait"]
  }

  provisioner "shell" {
    inline = [
      "sudo mkdir -p /opt/sheesh/shared",
      "sudo chown ubuntu:ubuntu /opt/sheesh/shared"
    ]
  }

  provisioner "file" {
    source      = "shared/"
    destination = "/opt/sheesh/shared"
  }

  # ...
}
```

Scripts can then be used as follows:

Function library:

```sh
source /opt/sheesh/shared/scripts/functions.sh

_main() {
  func_add_svc_user "my_svc"
  cd /home/my_svc

  # ...
}

_main "$@"
```

Cloud-init:

```sh
/opt/sheesh/shared/scripts/attach-ebs.sh \
    -i ${aws_ebs_volume.data.id} \
    -p /var/lib/my-data \
    -u my-svc \
    -g root
```
