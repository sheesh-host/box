package main

import (
	"context"
	"fmt"
	"io"
	"os"
	"time"

	"github.com/charmbracelet/huh"
	"github.com/sheesh-host/box/pkg/ami"
	"github.com/sheesh-host/box/pkg/backend"
	"github.com/sheesh-host/box/pkg/config"
	"github.com/sheesh-host/box/pkg/deploykey"
	"github.com/sheesh-host/box/pkg/tfvars"
	"github.com/spf13/cobra"
)

type initFlags struct {
	configPath     string
	terraformDir   string
	catalogURL     string
	nonInteractive bool
	dryRun         bool
	withDeployKey  bool
	deployKeyDir   string
}

func newInitCmd() *cobra.Command {
	f := &initFlags{}
	cfg := config.New()

	cmd := &cobra.Command{
		Use:   "init",
		Short: "Collect box inputs and render terraform variables",
		Long: `init gathers everything a sheesh box needs and writes:

  - <terraform-dir>/sheesh.auto.tfvars.json   (terraform variables)
  - <terraform-dir>/backend.tf                (only when --backend-bucket is set)
  - .sheesh.yaml                              (re-runnable config)

Provide every required value via flags to run non-interactively; otherwise the
missing values are prompted for with an interactive form.`,
		Args: cobra.NoArgs,
		RunE: func(cmd *cobra.Command, _ []string) error {
			return runInit(cmd, f, cfg)
		},
	}

	fl := cmd.Flags()
	// Required box inputs.
	fl.StringVar(&cfg.NamePrefix, "name", "", "name prefix for created resources (required)")
	fl.StringVar(&cfg.AWSRegion, "region", "", "AWS region to deploy into (required)")
	fl.StringVar(&cfg.VPCID, "vpc-id", "", "VPC to deploy into (required)")
	fl.StringVar(&cfg.SubnetID, "subnet-id", "", "subnet to deploy into (required)")
	fl.StringVar(&cfg.DNSDomain, "domain", "", "Route53 zone for the host record (required)")
	fl.StringVar(&cfg.Hostname, "hostname", "", "hostname to create in the zone (required)")
	fl.StringVar(&cfg.GithubOrg, "github-org", "", "GitHub org owning the content repo (required)")
	fl.StringVar(&cfg.ContentRepo, "content-repo", "", "content repository git-sync tracks (required)")
	fl.StringVar(&cfg.AMIID, "ami-id", "", "AMI to deploy (resolved from the catalog when omitted)")
	fl.StringVar(&cfg.ACMEEmail, "acme-email", "", "email for Let's Encrypt certificates (required)")
	// Optional box inputs.
	fl.StringVar(&cfg.ContentBranch, "content-branch", config.DefaultContentBranch, "branch git-sync tracks")
	fl.StringVar(&cfg.InstanceType, "instance-type", config.DefaultInstanceType, "EC2 instance type")
	fl.BoolVar(&cfg.ACMEStaging, "acme-staging", false, "use the Let's Encrypt staging environment")
	fl.StringVar((*string)(&cfg.AuthMode), "auth-mode", string(config.DefaultAuthMode), "content auth: none|basic|oidc")
	// Backend.
	fl.StringVar(&cfg.Backend.Bucket, "backend-bucket", "", "S3 bucket for terraform state (local state if empty)")
	fl.StringVar(&cfg.Backend.Region, "backend-region", "", "region of the S3 state bucket")
	fl.StringVar(&cfg.Backend.Key, "backend-key", "", "state key in the bucket (defaults to <name>/terraform.tfstate)")
	// Behaviour.
	fl.StringVar(&f.configPath, "config", config.DefaultFile, "path to read/write the box config")
	fl.StringVar(&f.terraformDir, "terraform-dir", "terraform", "directory to write tfvars/backend into")
	fl.StringVar(&f.catalogURL, "ami-catalog-url", ami.DefaultCatalogURL, "AMI catalog (amis.json) URL")
	fl.BoolVar(&f.nonInteractive, "non-interactive", false, "never prompt; fail if required values are missing")
	fl.BoolVar(&f.dryRun, "dry-run", false, "print what would be written without writing")
	fl.BoolVar(&f.withDeployKey, "with-deploy-key", false, "generate an ed25519 deploy key for a private content repo")
	fl.StringVar(&f.deployKeyDir, "deploy-key-dir", ".", "directory to write the generated deploy key into")

	return cmd
}

func runInit(cmd *cobra.Command, f *initFlags, cfg *config.Config) error {
	out := cmd.OutOrStdout()
	cfg.ApplyDefaults()

	// Resolve an AMI from the catalog when none was given and a region is known.
	if cfg.AMIID == "" && cfg.AWSRegion != "" {
		if id, err := resolveAMI(f.catalogURL, cfg.AWSRegion); err != nil {
			fmt.Fprintf(cmd.ErrOrStderr(), "note: could not resolve AMI from %s (%v); set --ami-id\n", f.catalogURL, err)
		} else if id != "" {
			cfg.AMIID = id
			fmt.Fprintf(out, "resolved latest AMI for %s: %s\n", cfg.AWSRegion, id)
		}
	}

	// Prompt for whatever is still missing, unless asked not to.
	if missing := cfg.Missing(); len(missing) > 0 {
		if f.nonInteractive {
			return fmt.Errorf("missing required values: %v (run interactively or pass the flags)", missing)
		}
		if err := promptMissing(cfg, missing); err != nil {
			return err
		}
	}

	cfg.ApplyDefaults()
	if err := cfg.Validate(); err != nil {
		return err
	}

	// Generate a deploy key on request.
	if f.withDeployKey {
		if err := writeDeployKey(out, cfg, f.deployKeyDir, f.dryRun); err != nil {
			return err
		}
	}

	tfBytes, err := tfvars.Marshal(cfg)
	if err != nil {
		return err
	}
	backendContent, hasBackend, err := backend.Render(cfg)
	if err != nil {
		return err
	}

	if f.dryRun {
		fmt.Fprintf(out, "\n--- %s ---\n%s", tfvars.FileName, tfBytes)
		if hasBackend {
			fmt.Fprintf(out, "\n--- %s ---\n%s", backend.FileName, backendContent)
		}
		fmt.Fprintln(out, "\n(dry run: nothing written)")
		return nil
	}

	if err := os.MkdirAll(f.terraformDir, 0o755); err != nil {
		return err
	}
	tfPath, err := tfvars.Write(cfg, f.terraformDir)
	if err != nil {
		return err
	}
	fmt.Fprintf(out, "wrote %s\n", tfPath)

	if hasBackend {
		if exists, _ := backend.Detect(f.terraformDir); exists {
			fmt.Fprintf(out, "note: a backend block already exists in %s; skipping backend.tf\n", f.terraformDir)
		} else if bp, err := backend.Write(cfg, f.terraformDir); err != nil {
			return err
		} else if bp != "" {
			fmt.Fprintf(out, "wrote %s\n", bp)
		}
	}

	if err := cfg.Save(f.configPath); err != nil {
		return err
	}
	fmt.Fprintf(out, "wrote %s\n", f.configPath)

	fmt.Fprintf(out, "\nNext: review the files, then deploy with\n  cd %s && terraform init && terraform apply\n", f.terraformDir)
	return nil
}

// resolveAMI fetches the catalog and returns the latest AMI id for region, or
// "" when the catalog has none for that region.
func resolveAMI(catalogURL, region string) (string, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	cat, err := ami.Fetch(ctx, nil, catalogURL)
	if err != nil {
		return "", err
	}
	if a, ok := cat.Latest(region); ok {
		return a.ID, nil
	}
	return "", nil
}

// promptMissing collects the missing required values via an interactive form.
func promptMissing(cfg *config.Config, missing []string) error {
	// Pointer for each promptable required field, keyed by tfvar name.
	targets := map[string]*string{
		"name_prefix":  &cfg.NamePrefix,
		"aws_region":   &cfg.AWSRegion,
		"vpc_id":       &cfg.VPCID,
		"subnet_id":    &cfg.SubnetID,
		"dns_domain":   &cfg.DNSDomain,
		"hostname":     &cfg.Hostname,
		"github_org":   &cfg.GithubOrg,
		"content_repo": &cfg.ContentRepo,
		"ami_id":       &cfg.AMIID,
		"acme_email":   &cfg.ACMEEmail,
	}
	prompts := map[string]string{
		"name_prefix":  "Name prefix for resources",
		"aws_region":   "AWS region",
		"vpc_id":       "VPC ID",
		"subnet_id":    "Subnet ID",
		"dns_domain":   "DNS zone (e.g. example.com)",
		"hostname":     "Hostname in the zone",
		"github_org":   "GitHub org",
		"content_repo": "Content repository name",
		"ami_id":       "AMI ID",
		"acme_email":   "Let's Encrypt email",
	}

	var fields []huh.Field
	for _, name := range missing {
		ptr, ok := targets[name]
		if !ok {
			continue
		}
		fields = append(fields, huh.NewInput().
			Title(prompts[name]).
			Value(ptr).
			Validate(func(s string) error {
				if s == "" {
					return fmt.Errorf("required")
				}
				return nil
			}))
	}
	if len(fields) == 0 {
		return nil
	}
	return huh.NewForm(huh.NewGroup(fields...)).Run()
}

// writeDeployKey generates an ed25519 deploy key and writes the private half to
// disk while printing the public half for the operator to register on GitHub.
func writeDeployKey(out io.Writer, cfg *config.Config, dir string, dryRun bool) error {
	kp, err := deploykey.Generate(fmt.Sprintf("%s@%s", cfg.NamePrefix, cfg.DNSDomain))
	if err != nil {
		return err
	}
	fmt.Fprintf(out, "\nAdd this read-only deploy key to %s/%s:\n%s\n", cfg.GithubOrg, cfg.ContentRepo, kp.PublicAuthorizedKey)
	if dryRun {
		fmt.Fprintln(out, "(dry run: private key not written)")
		return nil
	}
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return err
	}
	priv := dir + "/sheesh_deploy_ed25519"
	if err := os.WriteFile(priv, kp.PrivatePEM, 0o600); err != nil {
		return err
	}
	fmt.Fprintf(out, "wrote private deploy key %s (store it in SSM SecureString for the box)\n", priv)
	return nil
}
