// Package backend renders and detects the terraform state backend for a box.
//
// sheesh init renders an S3 backend block when the operator supplies a bucket;
// otherwise terraform falls back to local state and no backend.tf is written.
// Provisioning the bucket itself requires live AWS credentials and is left as a
// documented stub (EnsureBucket) until an AWS account is wired in.
package backend

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"text/template"

	"github.com/sheesh-host/box/pkg/config"
)

// FileName is the rendered backend configuration file.
const FileName = "backend.tf"

// ErrNotImplemented is returned by EnsureBucket until AWS wiring lands.
var ErrNotImplemented = errors.New("live S3 backend bucket creation not implemented yet (provide an existing bucket via --backend-bucket)")

var backendTmpl = template.Must(template.New("backend").Parse(`# Managed by ` + "`sheesh init`" + `. S3 backend for terraform state.
terraform {
  backend "s3" {
    bucket = "{{ .Bucket }}"
    key    = "{{ .Key }}"
    region = "{{ .Region }}"
  }
}
`))

// DefaultKey derives a state key from the box name when none is supplied.
func DefaultKey(namePrefix string) string {
	return fmt.Sprintf("%s/terraform.tfstate", namePrefix)
}

// Render returns the backend.tf content for c, or empty string + false when c
// has no S3 backend configured (local state).
func Render(c *config.Config) (string, bool, error) {
	if c.Backend.Bucket == "" {
		return "", false, nil
	}
	b := c.Backend
	if b.Key == "" {
		b.Key = DefaultKey(c.NamePrefix)
	}
	var sb strings.Builder
	if err := backendTmpl.Execute(&sb, b); err != nil {
		return "", false, err
	}
	return sb.String(), true, nil
}

// Detect reports whether any *.tf file in dir already declares a backend block,
// so init can avoid clobbering an operator-managed backend.
func Detect(dir string) (bool, error) {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return false, err
	}
	for _, e := range entries {
		if e.IsDir() || !strings.HasSuffix(e.Name(), ".tf") {
			continue
		}
		data, err := os.ReadFile(filepath.Join(dir, e.Name()))
		if err != nil {
			return false, err
		}
		if strings.Contains(string(data), "backend \"") {
			return true, nil
		}
	}
	return false, nil
}

// Write renders c's backend into dir/backend.tf. It returns ("", nil) when c
// uses local state (nothing to write).
func Write(c *config.Config, dir string) (string, error) {
	content, ok, err := Render(c)
	if err != nil || !ok {
		return "", err
	}
	path := filepath.Join(dir, FileName)
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		return "", err
	}
	return path, nil
}

// EnsureBucket would create the S3 state bucket if it does not exist. It is a
// stub pending AWS SDK wiring; see ErrNotImplemented.
func EnsureBucket(_ config.Backend) error {
	return ErrNotImplemented
}
