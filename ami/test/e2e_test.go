package test

import (
	"crypto/tls"
	"crypto/x509"
	"fmt"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/gruntwork-io/terratest/modules/aws"
	http_helper "github.com/gruntwork-io/terratest/modules/http-helper"
	loggers "github.com/gruntwork-io/terratest/modules/logger"
	"github.com/gruntwork-io/terratest/modules/packer"
	"github.com/gruntwork-io/terratest/modules/random"
	"github.com/gruntwork-io/terratest/modules/terraform"
	test_structure "github.com/gruntwork-io/terratest/modules/test-structure"
	"github.com/stretchr/testify/assert"
)

// Occasionally a Packer build fails on intermittent issues (brief network
// outage, EC2 hiccup). Retry on these known-transient errors.
var DefaultRetryablePackerErrors = map[string]string{
	"Script disconnected unexpectedly":                                                 "Occasionally, Packer seems to lose connectivity to AWS, perhaps due to a brief network outage",
	"can not open /var/lib/apt/lists/archive.ubuntu.com_ubuntu_dists_xenial_InRelease": "Occasionally, apt-get fails on ubuntu to update the cache",
}
var DefaultTimeBetweenPackerRetries = 15 * time.Second

const DefaultMaxPackerRetries = 3

var logger = loggers.Default

// End-to-end test: build the sheesh AMI with Packer, deploy it with the box
// terraform module, and assert the box serves the synced content over TLS.
//
// It is broken into terratest stages so you can skip stages locally via env
// vars (e.g. SKIP_build_ami=true), and it requires real infrastructure inputs:
//
//	SHEESH_TEST_DNS_DOMAIN   a Route53 zone in the test account (e.g. example.com)
//	SHEESH_TEST_CONTENT_REPO the content repo to serve, "org/repo"
//	SHEESH_TEST_DEPLOY_KEY   PEM private deploy key with read access to that repo
//
// Optional: SHEESH_TEST_AWS_REGION (default ap-southeast-1),
// SHEESH_TEST_CONTENT_BRANCH (default main). The test skips when the required
// inputs are absent, so it is safe to run in environments without them.
func TestTerraformPackerSheesh(t *testing.T) {
	t.Parallel()

	cfg, ok := loadTestConfig(t)
	if !ok {
		t.Skip("set SHEESH_TEST_DNS_DOMAIN, SHEESH_TEST_CONTENT_REPO (org/repo) and SHEESH_TEST_DEPLOY_KEY to run the e2e")
	}

	workingDir := "./terraform"

	// At the end of the test, delete the AMI.
	defer test_structure.RunTestStage(t, "cleanup_ami", func() {
		deleteAMI(t, cfg.awsRegion, workingDir)
	})

	// At the end of the test, undeploy the box.
	defer test_structure.RunTestStage(t, "cleanup_terraform", func() {
		undeployUsingTerraform(t, workingDir)
	})

	// Build the sheesh AMI.
	test_structure.RunTestStage(t, "build_ami", func() {
		buildAMI(t, cfg, workingDir)
	})

	// Deploy the box.
	test_structure.RunTestStage(t, "deploy_terraform", func() {
		deployUsingTerraform(t, cfg, workingDir)
	})

	// Validate the box booted and serves content over TLS.
	test_structure.RunTestStage(t, "validate", func() {
		testSSMConnection(t, cfg.awsRegion, workingDir)
		validateBoxServesContent(t, workingDir)
	})
}

type testConfig struct {
	awsRegion     string
	dnsDomain     string
	githubOrg     string
	contentRepo   string
	contentBranch string
	deployKey     string
}

func loadTestConfig(t *testing.T) (testConfig, bool) {
	dnsDomain := os.Getenv("SHEESH_TEST_DNS_DOMAIN")
	repo := os.Getenv("SHEESH_TEST_CONTENT_REPO")
	deployKey := os.Getenv("SHEESH_TEST_DEPLOY_KEY")
	if dnsDomain == "" || repo == "" || deployKey == "" {
		return testConfig{}, false
	}
	org, name, found := strings.Cut(repo, "/")
	if !found {
		t.Fatalf("SHEESH_TEST_CONTENT_REPO must be in org/repo form, got %q", repo)
	}
	return testConfig{
		awsRegion:     envOr("SHEESH_TEST_AWS_REGION", "ap-southeast-1"),
		dnsDomain:     dnsDomain,
		githubOrg:     org,
		contentRepo:   name,
		contentBranch: envOr("SHEESH_TEST_CONTENT_BRANCH", "main"),
		deployKey:     deployKey,
	}, true
}

func envOr(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

// buildAMI builds the sheesh AMI in the default VPC.
func buildAMI(t *testing.T, cfg testConfig, workingDir string) {
	vpc := aws.GetDefaultVpc(t, cfg.awsRegion)
	if len(vpc.Subnets) == 0 {
		t.Fatalf("default VPC %s has no subnets to build the AMI in", vpc.Id)
	}

	packerOptions := &packer.Options{
		// Relative to this test file (ami/test) -> the ami/ packer dir.
		WorkingDir: "..",
		Template:   "build.pkr.hcl",
		Only:       "amazon-ebs.ubuntu",

		Vars: map[string]string{
			"pr":        "true",
			"vpc_id":    vpc.Id,
			"subnet_id": vpc.Subnets[0].Id,
		},

		RetryableErrors:    DefaultRetryablePackerErrors,
		TimeBetweenRetries: DefaultTimeBetweenPackerRetries,
		MaxRetries:         DefaultMaxPackerRetries,
	}

	test_structure.SavePackerOptions(t, workingDir, packerOptions)
	amiID := packer.BuildArtifact(t, packerOptions)
	test_structure.SaveArtifactID(t, workingDir, amiID)
}

func deleteAMI(t *testing.T, awsRegion string, workingDir string) {
	amiID := test_structure.LoadArtifactID(t, workingDir)
	aws.DeleteAmi(t, awsRegion, amiID)
}

func deployUsingTerraform(t *testing.T, cfg testConfig, workingDir string) {
	// Namespace resources so parallel runs don't clash.
	uniqueID := strings.ToLower(random.UniqueId())
	namePrefix := fmt.Sprintf("e2e-%s", uniqueID)

	amiID := test_structure.LoadArtifactID(t, workingDir)

	hostname := fmt.Sprintf("sheesh-%s", namePrefix)
	test_structure.SaveString(t, workingDir, "dnsDomain", cfg.dnsDomain)
	test_structure.SaveString(t, workingDir, "hostname", hostname)

	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: workingDir,
		Vars: map[string]interface{}{
			"ami_id":         amiID,
			"name_prefix":    namePrefix,
			"hostname":       hostname,
			"aws_region":     cfg.awsRegion,
			"dns_domain":     cfg.dnsDomain,
			"github_org":     cfg.githubOrg,
			"content_repo":   cfg.contentRepo,
			"content_branch": cfg.contentBranch,
			"deploy_key":     cfg.deployKey,
		},
	})

	test_structure.SaveTerraformOptions(t, workingDir, terraformOptions)
	terraform.InitAndApply(t, terraformOptions)
}

func undeployUsingTerraform(t *testing.T, workingDir string) {
	terraformOptions := test_structure.LoadTerraformOptions(t, workingDir)
	terraform.Destroy(t, terraformOptions)
}

// testSSMConnection waits for the box, then dumps boot + service logs via SSM.
func testSSMConnection(t *testing.T, awsRegion string, workingDir string) {
	terraformOptions := test_structure.LoadTerraformOptions(t, workingDir)
	asgName := terraform.OutputRequired(t, terraformOptions, "asg_name")

	maxRetries := 30
	timeBetweenRetries := 5 * time.Second

	aws.WaitForCapacity(t, asgName, awsRegion, maxRetries, timeBetweenRetries)
	instanceID := aws.GetInstanceIdsForAsg(t, asgName, awsRegion)[0]

	timeout := 10 * time.Minute
	aws.WaitForSsmInstance(t, awsRegion, instanceID, timeout)
	checkLogs(t, awsRegion, instanceID, timeout, []ssmCommand{
		{command: "sudo cloud-init status --wait", printf: "cloud-init status:\n\n%s\n"},
		{command: "sudo cat /var/log/user-data.log", printf: "user-data log:\n\n%s\n"},
		{command: "sudo journalctl -u confd", printf: "confd log:\n\n%s\n"},
		{command: "sudo journalctl -u caddy", printf: "caddy log:\n\n%s\n"},
		{command: "sudo journalctl -u content", printf: "content git-sync log:\n\n%s\n"},
		{command: "ls -l /var/lib/sheesh/git", printf: "contents of git-sync data directory:\n\n%s\n"},
	})
}

// validateBoxServesContent asserts the box answers an HTTPS request with 200.
func validateBoxServesContent(t *testing.T, workingDir string) {
	maxRetries := 30
	timeBetweenRetries := 5 * time.Second

	dnsDomain := test_structure.LoadString(t, workingDir, "dnsDomain")
	hostname := test_structure.LoadString(t, workingDir, "hostname")
	url := fmt.Sprintf("https://%s.%s/", hostname, dnsDomain)

	// Content is arbitrary static HTML, so only assert the box is serving (200).
	http_helper.HttpGetWithRetryWithCustomValidation(
		t,
		url,
		getTLSConfig(t),
		maxRetries,
		timeBetweenRetries,
		func(statusCode int, _ string) bool {
			return statusCode == 200
		},
	)
}

// getTLSConfig trusts the Let's Encrypt staging roots (the box uses
// acme_staging=true) in addition to the system roots.
func getTLSConfig(t *testing.T) *tls.Config {
	// ref: https://forfuncsake.github.io/post/2017/08/trust-extra-ca-cert-in-go-app/
	rootCAs, _ := x509.SystemCertPool()
	if rootCAs == nil {
		rootCAs = x509.NewCertPool()
	}

	// https://github.com/letsencrypt/website/tree/master/static/certs/staging
	for _, c := range []string{
		"test-fixtures/letsencrypt-stg-root-x1.pem",
		"test-fixtures/letsencrypt-stg-root-x2.pem",
	} {
		certs, _ := os.ReadFile(c)
		if ok := rootCAs.AppendCertsFromPEM(certs); !ok {
			logger.Logf(t, "%q cert failed to append\n", c)
		}
	}

	return &tls.Config{RootCAs: rootCAs}
}

type ssmCommand struct {
	printf  string
	command string
}

func checkLogs(t *testing.T, awsRegion string, instanceID string, timeout time.Duration, commands []ssmCommand) {
	for _, c := range commands {
		result := aws.CheckSsmCommand(t, awsRegion, instanceID, c.command, timeout)
		assert.Equal(t, int64(0), result.ExitCode)
		logger.Logf(t, c.printf, result.Stdout)
	}
}
