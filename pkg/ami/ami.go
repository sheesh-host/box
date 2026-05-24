// Package ami models the public AMI catalog (amis.json) that sheesh publishes
// and the CLI consumes when picking an AMI for a box.
//
// The same schema is produced by .github/workflows/build-ami.yml from packer's
// manifest, keeping producer and consumer in lockstep (architecture.md §4, §12).
package ami

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"time"
)

// DefaultCatalogURL is the canonical published catalog location.
const DefaultCatalogURL = "https://sheesh.host/amis.json"

// AMI is one published image in one region.
type AMI struct {
	Version string    `json:"version"`
	Region  string    `json:"region"`
	ID      string    `json:"ami_id"`
	Arch    string    `json:"arch"`
	Name    string    `json:"name,omitempty"`
	Created time.Time `json:"created"`
}

// Catalog is the top-level amis.json document.
type Catalog struct {
	SchemaVersion int   `json:"schema_version"`
	AMIs          []AMI `json:"amis"`
}

// Parse decodes a catalog from raw JSON bytes.
func Parse(data []byte) (*Catalog, error) {
	var c Catalog
	if err := json.Unmarshal(data, &c); err != nil {
		return nil, fmt.Errorf("parse ami catalog: %w", err)
	}
	return &c, nil
}

// Fetch retrieves and parses the catalog at url. A nil client uses a sensible
// default with a 30s timeout.
func Fetch(ctx context.Context, client *http.Client, url string) (*Catalog, error) {
	if client == nil {
		client = &http.Client{Timeout: 30 * time.Second}
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return nil, err
	}
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("fetch %s: unexpected status %s", url, resp.Status)
	}
	data, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}
	return Parse(data)
}

// Latest returns the most recently created AMI for the given region (arm64, the
// only arch sheesh builds today). The bool is false when none match.
func (c *Catalog) Latest(region string) (AMI, bool) {
	var best AMI
	found := false
	for _, a := range c.AMIs {
		if a.Region != region {
			continue
		}
		if !found || a.Created.After(best.Created) {
			best, found = a, true
		}
	}
	return best, found
}
