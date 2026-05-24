# Changelog

## Unreleased

- Initial sheesh.host box module: single-node ASG + EIP + persistent EBS +
  Route53 record, serving git-synced static content via the [sheesh AMI](../ami).
  Forked from an internal Atlantis module and reduced to the sheesh stack
  (dropped Atlantis, datadog, tfmigrate, turborepo, and conftest concerns).
