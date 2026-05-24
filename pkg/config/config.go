// Package config defines the typed configuration for a single sheesh box and
// its load/save/validate helpers. It is deliberately free of CLI and AWS
// dependencies so both the sheesh CLI and the future sheesh-server can share it.
//
// The field set mirrors the required inputs of the terraform module
// (terraform/variables.tf): everything the operator must decide before a box
// can be deployed. Optional fields carry the module's own defaults so a config
// stays minimal.
package config

import (
	"fmt"
	"os"
	"strings"

	"gopkg.in/yaml.v3"
)

// DefaultFile is the on-disk config name written/read in the working directory.
const DefaultFile = ".sheesh.yaml"

// Defaults for optional inputs, matching terraform/variables.tf.
const (
	DefaultInstanceType  = "t4g.small"
	DefaultContentBranch = "main"
	DefaultAuthMode      = AuthNone
)

// AuthMode selects how Caddy gates the served content (architecture.md §7).
type AuthMode string

const (
	AuthNone  AuthMode = "none"
	AuthBasic AuthMode = "basic"
	AuthOIDC  AuthMode = "oidc"
)

// Backend describes an S3 terraform backend. When Bucket is empty the module
// uses local state and no backend.tf is rendered.
type Backend struct {
	Bucket string `yaml:"bucket,omitempty"`
	Key    string `yaml:"key,omitempty"`
	Region string `yaml:"region,omitempty"`
}

// Config is the full description of one sheesh box.
type Config struct {
	// Required.
	NamePrefix  string `yaml:"name_prefix"`
	AWSRegion   string `yaml:"aws_region"`
	VPCID       string `yaml:"vpc_id"`
	SubnetID    string `yaml:"subnet_id"`
	DNSDomain   string `yaml:"dns_domain"`
	Hostname    string `yaml:"hostname"`
	GithubOrg   string `yaml:"github_org"`
	ContentRepo string `yaml:"content_repo"`
	AMIID       string `yaml:"ami_id"`
	ACMEEmail   string `yaml:"acme_email"`

	// Optional (carry module defaults).
	ContentBranch string   `yaml:"content_branch,omitempty"`
	InstanceType  string   `yaml:"instance_type,omitempty"`
	ACMEStaging   bool     `yaml:"acme_staging,omitempty"`
	AuthMode      AuthMode `yaml:"auth_mode,omitempty"`

	Backend Backend `yaml:"backend,omitempty"`
}

// New returns a Config pre-populated with the optional-field defaults.
func New() *Config {
	return &Config{
		ContentBranch: DefaultContentBranch,
		InstanceType:  DefaultInstanceType,
		AuthMode:      DefaultAuthMode,
	}
}

// ApplyDefaults fills any empty optional fields with their defaults. Safe to
// call repeatedly (e.g. after merging flags onto a loaded config).
func (c *Config) ApplyDefaults() {
	if c.ContentBranch == "" {
		c.ContentBranch = DefaultContentBranch
	}
	if c.InstanceType == "" {
		c.InstanceType = DefaultInstanceType
	}
	if c.AuthMode == "" {
		c.AuthMode = DefaultAuthMode
	}
}

// requiredField pairs a human label with the value to check, for Validate.
func (c *Config) requiredFields() []struct {
	name  string
	value string
} {
	return []struct {
		name  string
		value string
	}{
		{"name_prefix", c.NamePrefix},
		{"aws_region", c.AWSRegion},
		{"vpc_id", c.VPCID},
		{"subnet_id", c.SubnetID},
		{"dns_domain", c.DNSDomain},
		{"hostname", c.Hostname},
		{"github_org", c.GithubOrg},
		{"content_repo", c.ContentRepo},
		{"ami_id", c.AMIID},
		{"acme_email", c.ACMEEmail},
	}
}

// Missing returns the names of required fields that are still empty.
func (c *Config) Missing() []string {
	var missing []string
	for _, f := range c.requiredFields() {
		if strings.TrimSpace(f.value) == "" {
			missing = append(missing, f.name)
		}
	}
	return missing
}

// Validate reports an error naming every required field that is empty, plus any
// invalid enum values.
func (c *Config) Validate() error {
	if m := c.Missing(); len(m) > 0 {
		return fmt.Errorf("missing required config: %s", strings.Join(m, ", "))
	}
	switch c.AuthMode {
	case AuthNone, AuthBasic, AuthOIDC:
	default:
		return fmt.Errorf("invalid auth_mode %q (want none|basic|oidc)", c.AuthMode)
	}
	if c.Backend.Bucket != "" && c.Backend.Region == "" {
		return fmt.Errorf("backend.region is required when backend.bucket is set")
	}
	return nil
}

// Load reads a Config from a YAML file and applies optional-field defaults.
func Load(path string) (*Config, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	c := &Config{}
	if err := yaml.Unmarshal(data, c); err != nil {
		return nil, fmt.Errorf("parse %s: %w", path, err)
	}
	c.ApplyDefaults()
	return c, nil
}

// Save writes the Config to a YAML file with 0o644 permissions.
func (c *Config) Save(path string) error {
	data, err := yaml.Marshal(c)
	if err != nil {
		return err
	}
	return os.WriteFile(path, data, 0o644)
}
