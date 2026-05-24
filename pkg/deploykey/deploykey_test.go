package deploykey

import (
	"bytes"
	"strings"
	"testing"

	"golang.org/x/crypto/ssh"
)

func TestGenerateRoundTrip(t *testing.T) {
	kp, err := Generate("ops@example.com")
	if err != nil {
		t.Fatal(err)
	}

	// Private key parses back as a valid signer.
	signer, err := ssh.ParsePrivateKey(kp.PrivatePEM)
	if err != nil {
		t.Fatalf("private key does not parse: %v", err)
	}

	// Public authorized_keys line parses and matches the private key's public.
	pub, comment, _, _, err := ssh.ParseAuthorizedKey(kp.PublicAuthorizedKey)
	if err != nil {
		t.Fatalf("public key does not parse: %v", err)
	}
	if comment != "ops@example.com" {
		t.Errorf("comment mismatch: %q", comment)
	}
	if pub.Type() != "ssh-ed25519" {
		t.Errorf("expected ssh-ed25519, got %s", pub.Type())
	}
	if !bytes.Equal(pub.Marshal(), signer.PublicKey().Marshal()) {
		t.Error("public half does not match private half")
	}
	if !strings.HasPrefix(string(kp.PublicAuthorizedKey), "ssh-ed25519 ") {
		t.Errorf("unexpected authorized_keys prefix: %q", kp.PublicAuthorizedKey)
	}
}

func TestGenerateUnique(t *testing.T) {
	a, _ := Generate("")
	b, _ := Generate("")
	if bytes.Equal(a.PrivatePEM, b.PrivatePEM) {
		t.Error("two generated keys should differ")
	}
}
