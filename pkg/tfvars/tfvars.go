// Package tfvars renders a config.Config into a terraform variables file.
//
// It emits the JSON tfvars form (terraform.auto.tfvars.json) rather than HCL:
// JSON is part of terraform's native variable-loading rules, and the standard
// library can produce it safely without an HCL writer dependency. The variable
// names map 1:1 onto terraform/variables.tf.
package tfvars

import (
	"encoding/json"
	"os"
	"path/filepath"

	"github.com/sheesh-host/box/pkg/config"
)

// FileName is the conventional auto-loaded tfvars file terraform reads.
const FileName = "sheesh.auto.tfvars.json"

// Vars converts a Config into the variable map terraform consumes. Only module
// inputs are emitted; AWS region is supplied via the provider, not a tfvar.
func Vars(c *config.Config) map[string]any {
	return map[string]any{
		"name_prefix":    c.NamePrefix,
		"ami_id":         c.AMIID,
		"vpc_id":         c.VPCID,
		"subnet_id":      c.SubnetID,
		"dns_domain":     c.DNSDomain,
		"hostname":       c.Hostname,
		"github_org":     c.GithubOrg,
		"content_repo":   c.ContentRepo,
		"content_branch": c.ContentBranch,
		"acme_email":     c.ACMEEmail,
		"acme_staging":   c.ACMEStaging,
		"instance_type":  c.InstanceType,
	}
}

// Marshal returns the indented JSON tfvars bytes for c.
func Marshal(c *config.Config) ([]byte, error) {
	data, err := json.MarshalIndent(Vars(c), "", "  ")
	if err != nil {
		return nil, err
	}
	return append(data, '\n'), nil
}

// Write renders c into dir/sheesh.auto.tfvars.json and returns the path written.
func Write(c *config.Config, dir string) (string, error) {
	data, err := Marshal(c)
	if err != nil {
		return "", err
	}
	path := filepath.Join(dir, FileName)
	if err := os.WriteFile(path, data, 0o644); err != nil {
		return "", err
	}
	return path, nil
}
