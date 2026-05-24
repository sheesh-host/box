// Command sheesh is the bootstrap CLI for a sheesh.host box: it collects the
// inputs a box needs and renders the terraform variables (and optional S3
// backend) used to deploy it. Running terraform stays manual for now.
//
// Reusable logic lives under pkg/* so a future cmd/sheesh-server can share it;
// this package is intentionally thin command wiring.
package main

import (
	"fmt"
	"os"

	"github.com/sheesh-host/box/pkg/version"
	"github.com/spf13/cobra"
)

// Stamped at build time via -ldflags (see .goreleaser.yaml). Mirrored into the
// version package so libraries can report the same build.
var (
	buildVersion = "dev"
	buildCommit  = "unknown"
	buildDate    = "unknown"
)

func newRootCmd() *cobra.Command {
	root := &cobra.Command{
		Use:   "sheesh",
		Short: "Bootstrap a self-hostable, git-backed static-publishing box",
		Long: `sheesh bootstraps a sheesh.host box.

  sheesh init      Collect box inputs (interactively or from flags) and render
                   the terraform variables + optional S3 backend for deployment.

Deploying is still a manual ` + "`terraform apply`" + ` in the terraform/ directory.`,
		SilenceUsage:  true,
		SilenceErrors: true,
		Version:       version.String(),
	}
	root.SetVersionTemplate("sheesh {{.Version}}\n")
	root.CompletionOptions.DisableDefaultCmd = true

	root.AddCommand(newInitCmd())
	root.AddCommand(newVersionCmd())
	return root
}

func main() {
	version.Version = buildVersion
	version.Commit = buildCommit
	version.Date = buildDate

	if err := newRootCmd().Execute(); err != nil {
		fmt.Fprintln(os.Stderr, "error:", err)
		os.Exit(1)
	}
}
