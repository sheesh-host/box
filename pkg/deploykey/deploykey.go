// Package deploykey generates ed25519 SSH deploy keys for private content repos.
//
// sheesh init uses this to mint a read-only key it can add to the content repo
// (public half) and store in SSM for the box's git-sync (private half). The
// output formats are exactly what GitHub deploy keys and OpenSSH expect.
package deploykey

import (
	"crypto/ed25519"
	"crypto/rand"
	"encoding/pem"
	"fmt"
	"strings"

	"golang.org/x/crypto/ssh"
)

// KeyPair holds both halves of a generated deploy key in their on-the-wire
// formats.
type KeyPair struct {
	// PrivatePEM is the OpenSSH-format private key (id_ed25519).
	PrivatePEM []byte
	// PublicAuthorizedKey is the single-line authorized_keys form
	// ("ssh-ed25519 AAAA... comment"), suitable as a GitHub deploy key.
	PublicAuthorizedKey []byte
}

// Generate creates a fresh ed25519 deploy key. The comment is appended to the
// public key line (conventionally an email or box identifier).
func Generate(comment string) (*KeyPair, error) {
	pub, priv, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		return nil, fmt.Errorf("generate ed25519 key: %w", err)
	}

	block, err := ssh.MarshalPrivateKey(priv, comment)
	if err != nil {
		return nil, fmt.Errorf("marshal private key: %w", err)
	}

	sshPub, err := ssh.NewPublicKey(pub)
	if err != nil {
		return nil, fmt.Errorf("marshal public key: %w", err)
	}
	authorized := strings.TrimRight(string(ssh.MarshalAuthorizedKey(sshPub)), "\n")
	if comment != "" {
		authorized += " " + comment
	}

	return &KeyPair{
		PrivatePEM:          pem.EncodeToMemory(block),
		PublicAuthorizedKey: []byte(authorized + "\n"),
	}, nil
}
