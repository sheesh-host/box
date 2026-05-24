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

// Occasionally, a Packer build may fail due to intermittent issues (e.g., brief network outage or EC2 issue). We try
// to make our tests resilient to that by specifying those known common errors here and telling our builds to retry if
// they hit those errors.
var DefaultRetryablePackerErrors = map[string]string{
	"Script disconnected unexpectedly":                                                 "Occasionally, Packer seems to lose connectivity to AWS, perhaps due to a brief network outage",
	"can not open /var/lib/apt/lists/archive.ubuntu.com_ubuntu_dists_xenial_InRelease": "Occasionally, apt-get fails on ubuntu to update the cache",
}
var DefaultTimeBetweenPackerRetries = 15 * time.Second

const DefaultMaxPackerRetries = 3

var logger = loggers.Default

// This is a complicated, end-to-end integration test. It builds the AMI from examples/packer-docker-example,
// deploys it using the Terraform code in terraform dir, and checks that the web server in the AMI
// response to requests. The test is broken into "stages" so you can skip stages by setting environment variables (e.g.,
// skip stage "build_ami" by setting the environment variable "SKIP_build_ami=true"), which speeds up iteration when
// running this test over and over again locally.
func TestTerraformPackerAtlantis(t *testing.T) {
	t.Parallel()
	// all tests will run from terraform module for atlantis dir
	workingDir := "./terraform"
	awsRegion := "ap-southeast-1"

	// At the end of the test, delete the AMI
	defer test_structure.RunTestStage(t, "cleanup_ami", func() {
		deleteAMI(t, awsRegion, workingDir)
	})

	// At the end of the test, undeploy atlantis using Terraform
	defer test_structure.RunTestStage(t, "cleanup_terraform", func() {
		undeployUsingTerraform(t, workingDir)
	})

	// Build the AMI for atlantis
	test_structure.RunTestStage(t, "build_ami", func() {
		buildAMI(t, awsRegion, workingDir)
	})

	// Deploy atlantis using Terraform
	test_structure.RunTestStage(t, "deploy_terraform", func() {
		deployUsingTerraform(t, awsRegion, workingDir)
	})

	// Validate that atlantis deployed and is responding to HTTP requests
	test_structure.RunTestStage(t, "validate", func() {
		testSSMConnection(t, awsRegion, workingDir)
		validateInstanceRunningWebServer(t, workingDir)
	})
}

// Build the AMI for Atlantis
func buildAMI(t *testing.T, awsRegion string, workingDir string) {
	packerOptions := &packer.Options{
		WorkingDir: "../../../packer",
		Template:   "atlantis-arm64/build.pkr.hcl",
		// Only build the AMI
		Only: "amazon-ebs.ubuntu",

		// Variables to pass to our Packer build using -var options
		// assuming .auto.pkrvars.hcl are loaded
		Vars: map[string]string{
			"pr": "true",
		},
		VarFiles: []string{
			"atlantis-arm64/.auto.pkrvars.hcl",
		},

		// Configure retries for intermittent errors
		RetryableErrors:    DefaultRetryablePackerErrors,
		TimeBetweenRetries: DefaultTimeBetweenPackerRetries,
		MaxRetries:         DefaultMaxPackerRetries,
	}

	// Save the Packer Options so future test stages can use them
	test_structure.SavePackerOptions(t, workingDir, packerOptions)

	// Build the AMI
	amiID := packer.BuildArtifact(t, packerOptions)

	// Save the AMI ID so future test stages can use them
	test_structure.SaveArtifactID(t, workingDir, amiID)
}

// Delete the AMI
func deleteAMI(t *testing.T, awsRegion string, workingDir string) {
	// Load the AMI ID and Packer Options saved by the earlier build_ami stage
	amiID := test_structure.LoadArtifactID(t, workingDir)

	aws.DeleteAmi(t, awsRegion, amiID)
}

// Deploy the terraform-packer-example using Terraform
func deployUsingTerraform(t *testing.T, awsRegion string, workingDir string) {
	// A unique ID we can use to namespace resources so we don't clash with anything already in the AWS account or
	// tests running in parallel
	uniqueID := strings.ToLower(random.UniqueId())

	// Give this EC2 Instance and other resources in the Terraform code a name with a unique ID so it doesn't clash
	// with anything else in the AWS account.
	namePrefix := fmt.Sprintf("e2e-%s", uniqueID)

	// Load the AMI ID saved by the earlier build_ami stage
	amiID := test_structure.LoadArtifactID(t, workingDir)

	dnsDomain := "devops.handshakes.com.sg"
	atlantisHostname := fmt.Sprintf("atlantis-%s", namePrefix)
	test_structure.SaveString(t, workingDir, "dnsDomain", dnsDomain)
	test_structure.SaveString(t, workingDir, "atlantisHostname", atlantisHostname)

	// Construct the terraform options with default retryable errors to handle the most common retryable errors in
	// terraform testing.
	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		// The path to where our Terraform code is located
		TerraformDir: workingDir,

		// Variables to pass to our Terraform code using -var options
		Vars: map[string]interface{}{
			"ami_id":            amiID,
			"name_prefix":       namePrefix,
			"hostname_atlantis": atlantisHostname,
			"aws_region":        awsRegion,
			"dns_domain":        dnsDomain,
		},
	})

	// Save the Terraform Options struct, instance name, and instance text so future test stages can use it
	test_structure.SaveTerraformOptions(t, workingDir, terraformOptions)

	// This will run `terraform init` and `terraform apply` and fail the test if there are any errors
	terraform.InitAndApply(t, terraformOptions)
}

// Undeploy the terraform-packer-example using Terraform
func undeployUsingTerraform(t *testing.T, workingDir string) {
	// Load the Terraform Options saved by the earlier deploy_terraform stage
	terraformOptions := test_structure.LoadTerraformOptions(t, workingDir)

	terraform.Destroy(t, terraformOptions)
}

// Connect through SSM and run validation commands
func testSSMConnection(t *testing.T, awsRegion string, workingDir string) {
	// Load the Terraform Options saved by the earlier deploy_terraform stage
	terraformOptions := test_structure.LoadTerraformOptions(t, workingDir)
	asgName := terraform.OutputRequired(t, terraformOptions, "asg_name")

	// It can take a minute or so for the ASG to scale up, so retry a few times
	maxRetries := 30
	timeBetweenRetries := 5 * time.Second

	aws.WaitForCapacity(
		t,
		asgName,
		awsRegion,
		maxRetries,
		timeBetweenRetries,
	)
	instanceID := aws.GetInstanceIdsForAsg(t, asgName, awsRegion)[0]

	timeout := 10 * time.Minute
	aws.WaitForSsmInstance(t, awsRegion, instanceID, timeout)
	checkLogs(t, awsRegion, instanceID, timeout, []ssmCommand{
		{command: "sudo cloud-init status --wait", printf: "cloud-init status:\n\n%s\n"},
		{command: "sudo cat /var/log/user-data.log", printf: "user-data log:\n\n%s\n"},
		{command: "sudo journalctl -u confd", printf: "confd log:\n\n%s\n"},
		{command: "sudo journalctl -u atlantis", printf: "atlantis log:\n\n%s\n"},
		{command: "sudo journalctl -u caddy", printf: "caddy log:\n\n%s\n"},
		{command: "sudo journalctl -u turbo-remote-cache", printf: "turbo-remote-cache log:\n\n%s\n"},
		{command: "ls -l /var/lib/sheesh/git", printf: "contents of git-sync data directory:\n\n%s\n"},
	})
}

// Validate the web server has been deployed and is working
func validateInstanceRunningWebServer(t *testing.T, workingDir string) {

	// It can take a minute or so for the Instance to boot up, so retry a few times
	maxRetries := 30
	timeBetweenRetries := 5 * time.Second

	dnsDomain := test_structure.LoadString(t, workingDir, "dnsDomain")
	atlantisHostname := test_structure.LoadString(t, workingDir, "atlantisHostname")
	instanceText := `{
  "status": "ok"
}`
	getOptions := http_helper.HttpGetOptions{
		Url:       fmt.Sprintf("https://%s.%s/healthz", atlantisHostname, dnsDomain),
		TlsConfig: getTLSConfig(t),
		Timeout:   10,
	}

	// Verify that we get back a 200 OK with the expected instanceText
	http_helper.HttpGetWithRetryWithOptions(t, getOptions, 200, instanceText, maxRetries, timeBetweenRetries)
}

// getTLSConfig returns custom TLS Config
// -> Let's Encrypt staging root CAs appended to the host system trusted CA Certs
func getTLSConfig(t *testing.T) (tlsConfig *tls.Config) {
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

	tlsConfig = &tls.Config{
		// InsecureSkipVerify: true,
		RootCAs: rootCAs,
	}
	return
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
