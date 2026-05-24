package config

import (
	"path/filepath"
	"slices"
	"testing"
)

func valid() *Config {
	c := New()
	c.NamePrefix = "demo"
	c.AWSRegion = "ap-southeast-1"
	c.VPCID = "vpc-123"
	c.SubnetID = "subnet-123"
	c.DNSDomain = "example.com"
	c.Hostname = "docs"
	c.GithubOrg = "sheesh-host"
	c.ContentRepo = "site"
	c.AMIID = "ami-123"
	c.ACMEEmail = "ops@example.com"
	return c
}

func TestValidateOK(t *testing.T) {
	if err := valid().Validate(); err != nil {
		t.Fatalf("expected valid config, got %v", err)
	}
}

func TestMissingFields(t *testing.T) {
	c := New()
	c.NamePrefix = "demo"
	missing := c.Missing()
	for _, want := range []string{"aws_region", "vpc_id", "ami_id", "acme_email"} {
		if !slices.Contains(missing, want) {
			t.Errorf("expected %q in missing set, got %v", want, missing)
		}
	}
	if slices.Contains(missing, "name_prefix") {
		t.Errorf("name_prefix was set but reported missing")
	}
	if err := c.Validate(); err == nil {
		t.Fatal("expected validation error for incomplete config")
	}
}

func TestInvalidAuthMode(t *testing.T) {
	c := valid()
	c.AuthMode = "saml"
	if err := c.Validate(); err == nil {
		t.Fatal("expected error for invalid auth_mode")
	}
}

func TestBackendRequiresRegion(t *testing.T) {
	c := valid()
	c.Backend.Bucket = "tfstate"
	if err := c.Validate(); err == nil {
		t.Fatal("expected error when backend.bucket set without region")
	}
	c.Backend.Region = "ap-southeast-1"
	if err := c.Validate(); err != nil {
		t.Fatalf("expected valid config with full backend, got %v", err)
	}
}

func TestSaveLoadRoundTrip(t *testing.T) {
	c := valid()
	c.ACMEStaging = true
	c.AuthMode = AuthBasic
	path := filepath.Join(t.TempDir(), DefaultFile)
	if err := c.Save(path); err != nil {
		t.Fatalf("save: %v", err)
	}
	got, err := Load(path)
	if err != nil {
		t.Fatalf("load: %v", err)
	}
	if got.NamePrefix != c.NamePrefix || got.AMIID != c.AMIID || !got.ACMEStaging || got.AuthMode != AuthBasic {
		t.Fatalf("round-trip mismatch: %+v", got)
	}
	// Defaults applied on load.
	if got.ContentBranch != DefaultContentBranch || got.InstanceType != DefaultInstanceType {
		t.Fatalf("defaults not applied on load: %+v", got)
	}
}
