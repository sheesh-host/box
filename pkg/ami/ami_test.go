package ami

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"
)

const sampleCatalog = `{
  "schema_version": 1,
  "amis": [
    {"version":"v0.1.0","region":"ap-southeast-1","ami_id":"ami-old","arch":"arm64","created":"2026-01-01T00:00:00Z"},
    {"version":"v0.2.0","region":"ap-southeast-1","ami_id":"ami-new","arch":"arm64","created":"2026-05-01T00:00:00Z"},
    {"version":"v0.2.0","region":"us-east-1","ami_id":"ami-use1","arch":"arm64","created":"2026-05-01T00:00:00Z"}
  ]
}`

func TestParseAndLatest(t *testing.T) {
	c, err := Parse([]byte(sampleCatalog))
	if err != nil {
		t.Fatal(err)
	}
	got, ok := c.Latest("ap-southeast-1")
	if !ok {
		t.Fatal("expected an AMI for ap-southeast-1")
	}
	if got.ID != "ami-new" {
		t.Errorf("expected newest ami-new, got %s", got.ID)
	}
	if _, ok := c.Latest("eu-west-1"); ok {
		t.Error("expected no AMI for eu-west-1")
	}
}

func TestFetch(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(sampleCatalog))
	}))
	defer srv.Close()

	c, err := Fetch(context.Background(), srv.Client(), srv.URL)
	if err != nil {
		t.Fatal(err)
	}
	if len(c.AMIs) != 3 {
		t.Fatalf("expected 3 AMIs, got %d", len(c.AMIs))
	}
}

func TestFetchNon200(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		http.Error(w, "nope", http.StatusNotFound)
	}))
	defer srv.Close()
	if _, err := Fetch(context.Background(), srv.Client(), srv.URL); err == nil {
		t.Fatal("expected error on 404")
	}
}
