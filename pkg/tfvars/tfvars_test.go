package tfvars

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"

	"github.com/sheesh-host/box/pkg/config"
)

func sample() *config.Config {
	c := config.New()
	c.NamePrefix = "demo"
	c.AWSRegion = "ap-southeast-1"
	c.VPCID = "vpc-1"
	c.SubnetID = "subnet-1"
	c.DNSDomain = "example.com"
	c.Hostname = "docs"
	c.GithubOrg = "sheesh-host"
	c.ContentRepo = "site"
	c.AMIID = "ami-1"
	c.ACMEEmail = "ops@example.com"
	c.ACMEStaging = true
	return c
}

func TestMarshalContainsExpectedVars(t *testing.T) {
	data, err := Marshal(sample())
	if err != nil {
		t.Fatal(err)
	}
	var got map[string]any
	if err := json.Unmarshal(data, &got); err != nil {
		t.Fatalf("output is not valid JSON: %v", err)
	}
	for _, k := range []string{
		"name_prefix", "ami_id", "vpc_id", "subnet_id", "dns_domain",
		"hostname", "github_org", "content_repo", "content_branch",
		"acme_email", "acme_staging", "instance_type",
	} {
		if _, ok := got[k]; !ok {
			t.Errorf("missing tfvar %q", k)
		}
	}
	if got["acme_staging"] != true {
		t.Errorf("acme_staging not propagated: %v", got["acme_staging"])
	}
	if got["instance_type"] != config.DefaultInstanceType {
		t.Errorf("instance_type default not applied: %v", got["instance_type"])
	}
	// aws_region is provider config, not a tfvar.
	if _, ok := got["aws_region"]; ok {
		t.Errorf("aws_region should not be emitted as a tfvar")
	}
}

func TestWrite(t *testing.T) {
	dir := t.TempDir()
	path, err := Write(sample(), dir)
	if err != nil {
		t.Fatal(err)
	}
	if path != filepath.Join(dir, FileName) {
		t.Errorf("unexpected path %q", path)
	}
	if _, err := os.Stat(path); err != nil {
		t.Fatalf("file not written: %v", err)
	}
}
