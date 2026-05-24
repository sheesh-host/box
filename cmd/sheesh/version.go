package main

import (
	"fmt"

	"github.com/sheesh-host/box/pkg/version"
	"github.com/spf13/cobra"
)

func newVersionCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "version",
		Short: "Print version, commit, and build date",
		Args:  cobra.NoArgs,
		RunE: func(cmd *cobra.Command, _ []string) error {
			out := cmd.OutOrStdout()
			fmt.Fprintf(out, "sheesh\n")
			fmt.Fprintf(out, "Version: %s\n", version.Version)
			fmt.Fprintf(out, "Commit:  %s\n", version.Commit)
			fmt.Fprintf(out, "Built:   %s\n", version.Date)
			return nil
		},
	}
}
