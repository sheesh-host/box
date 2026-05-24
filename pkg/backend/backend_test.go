package backend

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/sheesh-host/box/pkg/config"
)

func TestRenderLocalState(t *testing.T) {
	c := config.New()
	c.NamePrefix = "demo"
	_, ok, err := Render(c)
	if err != nil {
		t.Fatal(err)
	}
	if ok {
		t.Fatal("expected no backend rendered for local state")
	}
}

func TestRenderS3AndDefaultKey(t *testing.T) {
	c := config.New()
	c.NamePrefix = "demo"
	c.Backend.Bucket = "tfstate"
	c.Backend.Region = "ap-southeast-1"
	content, ok, err := Render(c)
	if err != nil || !ok {
		t.Fatalf("expected backend rendered, ok=%v err=%v", ok, err)
	}
	if !strings.Contains(content, `bucket = "tfstate"`) {
		t.Errorf("bucket missing from rendered backend:\n%s", content)
	}
	if !strings.Contains(content, DefaultKey("demo")) {
		t.Errorf("default key missing from rendered backend:\n%s", content)
	}
}

func TestDetect(t *testing.T) {
	dir := t.TempDir()
	if got, _ := Detect(dir); got {
		t.Fatal("empty dir should not detect a backend")
	}
	if err := os.WriteFile(filepath.Join(dir, "versions.tf"), []byte("terraform {\n  backend \"s3\" {}\n}\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	got, err := Detect(dir)
	if err != nil {
		t.Fatal(err)
	}
	if !got {
		t.Fatal("expected backend detected")
	}
}

func TestWriteS3(t *testing.T) {
	dir := t.TempDir()
	c := config.New()
	c.NamePrefix = "demo"
	c.Backend.Bucket = "tfstate"
	c.Backend.Region = "ap-southeast-1"
	path, err := Write(c, dir)
	if err != nil {
		t.Fatal(err)
	}
	if path != filepath.Join(dir, FileName) {
		t.Errorf("unexpected path %q", path)
	}
	if _, err := os.Stat(path); err != nil {
		t.Fatalf("backend.tf not written: %v", err)
	}
}

func TestEnsureBucketStub(t *testing.T) {
	if err := EnsureBucket(config.Backend{Bucket: "x"}); err != ErrNotImplemented {
		t.Fatalf("expected ErrNotImplemented, got %v", err)
	}
}
