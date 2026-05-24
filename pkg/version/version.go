// Package version exposes build metadata shared by every binary in this module
// (the sheesh CLI today, the future sheesh-server). The values are stamped at
// build time via -ldflags by goreleaser; see .goreleaser.yaml and cmd/sheesh.
package version

import "fmt"

// Stamped via -ldflags "-X github.com/sheesh-host/box/pkg/version.Version=...".
// Defaults make `go run`/`go test` builds report themselves as dev builds.
var (
	Version = "dev"
	Commit  = "unknown"
	Date    = "unknown"
)

// String renders a single-line human-readable build identifier.
func String() string {
	return fmt.Sprintf("%s (commit %s, built %s)", Version, Commit, Date)
}
