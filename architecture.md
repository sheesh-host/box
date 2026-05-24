# sheesh.host — Architecture

> Self-hostable, CLI-first, git-backed gated publishing for static artifacts.
> Your artifacts, your history, your AWS, your auth, your fork.

**License:** Apache 2.0
**Org:** `sheesh-host/sheesh`
**Status:** Design — pre-v0

---

## 1. What this is

sheesh is a self-hostable service for publishing static HTML/Markdown artifacts to a
permanent, optionally auth-gated URL. The primary deploy target is a single small EC2
box running Caddy and git-sync, provisioned by a single Terraform module from a public
Packer-built AMI.

The defining design choice is **git as the source of truth and the audit log**. Artifacts
live in a git repository; the serving box is a stateless projection of that repository.
This gives tamper-evident change history, line-level attribution, rollback, and disaster
recovery as structural properties rather than as features that have to be built and
trusted.

### What it is not

- Not a build platform. Bring built artifacts; sheesh does not run framework build steps.
- Not a global edge CDN. v0 is single-region, single-node. CloudFront is an opt-in later.
- Not multi-tenant SaaS. Each user runs their own box. (A managed control plane is a
  possible year-2 direction, not a v0 goal.)

---

## 2. Positioning

### The gap

Four buckets of existing tools, none of which own the target combination:

| Bucket | Examples | Why they don't fit |
|---|---|---|
| Drag-and-drop HTML hosts | Tiiny.host, Static.app, Static.run | Closed-source, web-UI-first, no self-host, no real auth |
| CLI-native PaaS | Surge, Netlify, Vercel, CF Pages, Wasmer | SaaS lock-in, no first-party self-host |
| Git-driven static hosts | GitHub Pages, CF Pages, Vercel | Not self-hostable; auth requires expensive tiers |
| Pastebin-for-HTML | clbin, paste.rs | Single-file, text/plain, no directories, no auth |

The target combination: **self-hostable, CLI-first, supports asset directories, optional
SSO/basic auth, deployable as one Terraform module.** Nobody owns it cleanly.

### vs GitHub Pages (private repo + access control)

Closest existing UX (git push → deployed static site). Differences:

| | GH Pages (private) | sheesh |
|---|---|---|
| Cost for auth tier | GH Enterprise Cloud (~$21/user/mo) | ~$5/mo AWS, flat |
| Auth | GH org membership only | Basic, OIDC (any IdP), or none |
| Data location | GitHub | Your AWS account, your region |
| Custom domain + auth | Enterprise only | Included |

Killer differentiator: **price for the auth tier**, plus SSO against whatever IdP the team
already uses (Google Workspace, Okta, Azure AD) rather than being tied to GH org membership.

### vs Cloudflare Pages / Vercel / Netlify

Different category — "self-hosted hosting," not PaaS. sheesh does not compete on edge
performance, build pipelines, or free tier. It competes on ownership: compliance / data
residency, privacy, IaC-purist preference, and forkability.

### vs display.dev

display.dev (launched ~April 2026) occupies the SaaS version of this exact space:
`dsp publish file.html` → permanent URL → SSO-gated viewing → inline comments → agent reads
comments via MCP → re-publish at same URL. Pricing: Free / Solo $15 / Pro $49 (incl. SSO) /
Enterprise from $499.

sheesh does not try to out-execute them on the SaaS axis. The wedge display.dev structurally
cannot serve:

- Teams that can't use SaaS for compliance / data residency / regulatory reasons
- Security postures that reject another vendor holding internal artifacts
- IaC-purist devs who prefer $5/mo to AWS over $49/mo to a startup
- Anyone who wants to fork and extend

**Position:** _git-native gated publishing — like display.dev, but in your AWS, with git as
the audit log._ The audit story is structurally better on sheesh's side because git solved
change-history-with-attribution long ago; compliance teams already trust git history and
don't have to trust a vendor retention policy.

---

## 3. Design principles

1. **One `terraform apply` = a working, TLS-terminated, auth-gated URL.** No clickops beyond
   a one-time GH App install (and only when the publish API is in use).
2. **Git is the source of truth and the audit log.** The box is a disposable projection.
3. **Upload path is decoupled from the serve path.** Git repo (or publish API) is the write
   surface; the box is the read surface. Either side can be swapped without breaking the other.
4. **Stateless-ish nodes.** Content and certs persist on EBS; everything else is ephemeral and
   ASG-replaceable. Box death is a non-event.
5. **Auth is a layer, not a feature.** Public by default; basic auth and OIDC are opt-in config
   blocks.
6. **File-type allowlist enforced at write/sync time, not request time.** Clearer failure mode.
7. **CLI is a thin wrapper.** Mostly orchestrates git, GH, AWS, and Terraform. Heavy lifting
   stays in proven tools.
8. **A no-AWS "try it" path exists** (docker-compose) so the loop is visible in 60 seconds
   before committing to the cloud path.

---

## 4. v0 architecture (git-sync path)

```
GitHub repo  ──(git-sync polls main, ~30s)──▶   ┌──────────────────────────┐
   ▲                                            │  EC2 t4g.nano (ARM) in   │
   │                                            │  ASG min=max=desired=1   │
   │ git push / merge to main                   │                          │
   │                                            │  git-sync (systemd)      │
   └── user / CI                                │    └─ pulls repo, atomic │
                                                │       symlink flip       │
                                                │                          │
                                                │  Caddy (systemd)         │
                                                │    └─ root = symlink     │
                                                │    └─ ACME TLS           │
                                                │    └─ optional auth      │
                                                │                          │
                                                │  EBS gp3 (10GB):         │
                                                │    /var/lib/caddy (certs)│
                                                │    /var/www  (content)   │
                                                └────────────┬─────────────┘
                                                             │
                                                      EIP ◀──┘ (stable, survives
                                                       │        instance replace)
                                                  Route53 A record
                                                       │
                                                    Visitors
```

### Components

**Packer AMI** — Ubuntu 24.04 ARM64 + Caddy + git-sync v4 binary + a boot-time renderer.
First boot reads instance tags / user-data / SSM for `REPO_URL`, `DOMAIN`, `ACME_EMAIL`,
`AUTH_MODE`, renders the Caddyfile and the git-sync unit, starts both. AMI is public,
versioned, region-replicated via GH Actions.

**git-sync (systemd)** — Standalone Go binary (the Kubernetes-ecosystem tool, runs fine
outside k8s). Polls `main`, maintains an atomically-updated symlink to the current worktree.
Caddy's `root` points at the symlink, so deploys are atomic with no half-written states.
`--exechook-command` runs the file-type allowlist check; sync is rejected if disallowed
extensions appear.

**Caddy (systemd)** — Serves `/var/www/current`. ACME for TLS. Auth modes:
- `none` — public
- `basic` — Caddy native `basic_auth`, htpasswd hashes from SSM
- `oidc` — oauth2-proxy + Caddy `forward_auth` (see §7)

**TF module** — default VPC or provided; SG (80/443 in); IAM role for SSM; ASG of 1 with a
launch template referencing the public AMI; EIP attach on launch; EBS attach-by-tag on launch;
Route53 A record. No ALB, no NAT, no EBS deletion on instance termination. ~$5/mo on t4g.nano.

**CLI (`sheesh init`)** — Collapses ~10 manual steps into one idempotent command:
checks AWS + gh auth, creates the content repo, generates an ed25519 deploy key, adds it
read-only to the repo, writes the private key to SSM SecureString, commits an initial
`index.html`, renders `main.tf` + tfvars. `--apply` runs Terraform.

**Content repo (one per site)** — `index.html`, assets, optional `.sheeshrc.yaml` (file
allowlist overrides, headers).

### Why no webhook in v0

A 30s poll on a $5/mo box is functionally indistinguishable from a webhook for the human
"push, refresh browser" loop. Webhooks need a public endpoint, HMAC verification, retry
handling, and a listener — not worth it for v0. Poll interval is tunable down to ~5s.
Near-instant deploys arrive with the publish API in v0.2 (webhook → /sync).

---

## 5. Stateless box / persistence model

ASG-of-1 + EIP + persistent EBS is a "pets-as-cattle-lite" pattern: self-healing on box
death without multi-node complexity.

On instance replace: ASG launches a new box → boot script finds the EBS volume by tag and
attaches it → reattaches the EIP → Caddy starts with all certs already present → git-sync
resumes from its last commit.

**Why EBS is required (revised from the no-EBS sketch):** Caddy needs a persistent certs
directory. Without it, every ASG replacement re-issues certs against Let's Encrypt rate
limits (5 duplicate certs/week, 50 certs/registered domain/week — easy to hit while testing).
EBS at 10GB gp3 is ~$0.80/mo and solves certs + content persistence together.

Alternative considered: DNS-01 challenge with a long-lived cert in SSM/Secrets Manager,
fully ephemeral box. Heavier to wire; revisit if the EBS attach-by-tag dance proves annoying.

---

## 6. Scale story

A single t4g.nano serves static files from local disk at tens of thousands of req/s. An
internal company share never needs to leave this tier. When a node is outgrown, the same TF
module with `instance_count > 1` + an ALB variant gets there without re-architecting — the
nodes are already stateless projections of git. CloudFront in front (v0.4+) adds caching and
global edge without changing the origin model.

---

## 7. Auth

| Mode | Mechanism | Secrets |
|---|---|---|
| `none` | Public | — |
| `basic` | Caddy native `basic_auth` | bcrypt htpasswd in SSM SecureString |
| `oidc` | oauth2-proxy + Caddy `forward_auth` | client secret in SSM SecureString |

**OIDC choice:** oauth2-proxy + Caddy `forward_auth`, NOT caddy-security. caddy-security had
10 CVEs found by Trail of Bits in 2023; the oauth2-proxy pattern is far more battle-tested.
Supports Google, GitHub, Microsoft, and generic OIDC providers.

Auth config schema is shared across the self-host (Caddy) and any future managed/CloudFront
path (Lambda@Edge), so migration stays possible.

---

## 8. Publish API (v0.2)

Adds `sheesh publish ./file.html` to match the mental model forming around `dsp publish`,
without abandoning git as source of truth.

```
agent / cli
    │ POST /api/publish?slug=foo
    │ Authorization: Bearer <user_token>
    │ (multipart file.html, or markdown body)
    ▼
┌──────────────────────────┐
│ Go webserver on the box  │
│  1. validate bearer      │
│  2. validate file types  │
│  3. validate path safety │
│  4. GH App JWT → commit  │
│     to repo via contents │
│     API (authored as the │
│     real user)           │
│  5. return commit SHA +  │
│     permalink            │
└───────────┬──────────────┘
            │ commit on main
            ▼
       GitHub repo
            │ git-sync poll, OR
            │ GH webhook → /sync (near-instant)
            ▼
      /var/www on the box
```

**Why commit-through-GH-App instead of direct disk write:**

- Audit log writes itself (commit = author + timestamp + diff).
- Git-driven users and CLI/agent users converge on the same artifact, same history, same
  rollback (`git revert`).
- Commits authored as the real user (via Sign-in-with-GitHub on the API side), not a generic
  bot — matters for the comment-loop attribution story.
- Disaster recovery unchanged: nothing is box-local.

GH App needs `contents:write` on the target repo, installed once per repo/org during
`sheesh init`. The box mints installation tokens from the App private key (SSM SecureString).

**Latency:** ~30s commit→serve via poll. Mitigations, in order of preference:
1. GH webhook → `/sync` on the same Go webserver (manual `git fetch && reset`, races git-sync).
2. Optimistic local write to `/var/www/<slug>/v<N+1>/`, async commit, quarantine version if
   commit fails. Adds reconciliation complexity — only if 5–10s still feels too slow.

**Versioning on disk:** `/var/www/<slug>/v<N>/` with `current` symlink → latest. Cheap
rollback, cheap pinned versions. Backs `sheesh rollback` / `sheesh versions`.

---

## 9. Inline comments (v0.3) — the real differentiator

display.dev stores comments in their DB as a side-channel, exposed via their MCP server —
portable only as a feature they must build. Specledger.io stores comments in git as part of
a spec-driven workflow — portable and first-class, but tied to structured markdown.

**sheesh synthesis: comments as files in the same repo as the artifact.**

```
comments/<artifact_path>/<comment_id>.md
  ── frontmatter: position anchor (XPath / CSS selector / md line),
                  author, timestamp, parent_thread, resolved
  ── body: the comment text
```

The Go webserver accepts comment submissions and commits them as files. A small JS bundle in
the served page reads the comments directory and renders inline comments over the artifact,
anchored via stable selectors — the HTML artifact itself stays untouched (no markup
pollution).

Properties:

- Comments are versioned, signed, auditable, portable — same git story as the artifact.
- Comments survive a fork: fork the repo, get artifact + comment history.
- Agents read comments by reading the repo; resolve threads by moving/deleting comment files.
  **Zero special plumbing required.**
- For the spec-driven case this is the Specledger experience; for arbitrary HTML it's an
  inline comment layer over whatever the agent produced.
- display.dev cannot match this without rebuilding their backend.

The MCP server becomes thin: `list_comments`, `resolve_comment`, `reply` — each a git commit
underneath. Agents can also bypass MCP entirely and operate on the files via the GH API.

This is the milestone where the story shifts from _different from display.dev_ to _better_:
**git-native gated publishing with git-native inline comments.**

---

## 10. Security

### Threat model summary

| Threat | Severity | Disposition |
|---|---|---|
| Zip Slip (archive path traversal) | Real | Mitigated — see below |
| RCE in publish handler from upload | Low | No execution of user content; stdlib zip, no shell-out |
| GH App / IAM blast radius | Low | Tightly scoped tokens + IAM conditions |
| Served-content XSS | By design | Isolate per subdomain; do not sanitize user HTML |
| Malware / phishing hosting | Operational | Safe Browsing scan, takedown process, rate limits |

### Zip Slip (the #1 risk for this class of service)

A malicious archive carries entries like `../../../etc/passwd`. AWS CDK itself shipped a Zip
Slip CVE (SNYK-JS-AWSCDK-2413656) — this is the cautionary tale for the space. For sheesh,
the worst case is a `../` entry landing in another slug's path (cross-tenant corruption) or
outside the intended dir on the box.

Mitigations (apply to any archive ingest):
- Never `zipfile.extractall()` / `tar.extractall()`. Iterate entries.
- Per entry: `normpath(join(dest, name))` must start with `realpath(dest) + sep`, else reject
  the **entire** upload (not skip the entry — partial-upload attacks).
- Reject absolute paths, symlinks, hardlinks, device files.
- Entry names must match `^[a-zA-Z0-9._/-]+$`.
- Cap entry count (~1000) and decompressed total (~100MB).
- Zip-bomb guard: abort if decompressed/compressed ratio exceeds ~100×.

### Publish-handler IAM / GH scope

- GH App token scoped to `contents:write` on exactly the target repo.
- If S3 is ever introduced: Lambda/box role limited to `s3:PutObject` on the user's prefix
  via IAM condition keys; no cross-prefix read/delete; no bucket-root list.

### Served content

Hosting arbitrary HTML means user JS runs in the visitor's browser — that's the point; do not
sanitize. Instead:
- Serve each site on its own subdomain so cookies/storage are isolated (the killer reason for
  subdomain-per-slug if multi-site lands).
- Send `X-Frame-Options: SAMEORIGIN` and a strict default CSP (user-overridable per site).
- Block `.php .cgi .exe .dll .so .jar .war .pyc .sh .bash` regardless (can't execute on the
  static path anyway — defense in depth + stays out of "we hosted malware" headlines).

### Operational abuse

Phishing/malware hosting bites every host eventually. Before any public/SaaS exposure:
`Content-Disposition` for unknown types, Google Safe Browsing scan (async, post-write),
documented takedown + `abuse@sheesh.host`, rate-limited account/site creation.

---

## 11. Roadmap

| Milestone | Scope | Story |
|---|---|---|
| **v0** | Packer AMI, single-node TF module, CLI bootstrap, Caddy + git-sync, basic auth, public AMI build, docker-compose try-it path | "self-hostable, gated static hosting" |
| **v0.1** | OIDC (oauth2-proxy + forward_auth), `sheesh status`, `sheesh logs`, file-type allowlist | usable |
| **v0.2** | Go webserver + GH App `/api/publish`, `sheesh publish file.html`, GH webhook → /sync, on-disk versioning, `sheesh rollback`/`versions` | "self-hostable display.dev with git as the audit log" |
| **v0.3** | Inline comments as git files, thin MCP server, JS render bundle | "git-native gated publishing with git-native inline comments" |
| **v0.4+** | Multi-site per box, optional CloudFront, comment-aware agent workflows (Specledger lineage) | scale + edge |

### Forward-compat constraints honored from v0

1. CLI surface (`sheesh push` / `sheesh init`) stable across backends; SaaS-mode would be a
   different backend behind the same CLI.
2. git-sync writes a `.sheesh-deploy.json` (deploy_id, timestamp, commit SHA) even in v0, so
   `status` / `rollback` work identically later.
3. Auth config schema shared across Caddy and any future Lambda@Edge path.
4. File allowlist is data (YAML/JSON shipped with the AMI), one source of truth across backends.

---

## 12. Deliverables (v0)

- Public GitHub repo `cdktn-io/sheesh` (Apache 2.0)
  - `packer/` — HCL template, public AMI build
  - `terraform/` — single-node module (EIP + EBS + ASG + Route53 or pass-in `zone_id`)
  - `cli/` — bootstrap CLI (Go; stays in the git-sync/gh ecosystem)
  - `.github/workflows/build-ami.yml` — Packer build on tagged release
- README with positioning + 60-second docker-compose demo

### First vertical slice to build

The AMI + Caddyfile + systemd triple — if that boots and serves a git repo behind basic auth,
the rest is wiring:

1. Caddyfile template (basic-auth and OIDC branches)
2. systemd units (`git-sync.service`, `caddy.service` override)
3. Boot-time renderer script
4. Packer HCL template

Then the TF module is "launch this AMI, attach this EIP/EBS, set these SSM params," and the
CLI automates the SSM-param-and-repo-create dance.
