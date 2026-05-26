# Handover: publishing `amis.json` via the `sheesh-release-bot` GitHub App

Context for the agent wiring the `build-ami.yml` "Publish amis.json" step (currently a TODO).
The cross-repo credentials are already provisioned on **`sheesh-host/box`**; consume them as below.

## GitHub App: `sheesh-release-bot`

- **App ID:** `3864019` (also exposed as repo variable `RELEASE_BOT_APP_ID`)
- **Client ID:** `Iv23liVt3fYwOMlzzi08` (not needed for token minting; FYI only)
- **Installation:** org `sheesh-host`, installation id `135646948`
- **Installed on (only these repos):** `sheesh-host/box`, `sheesh-host/sheesh-host.github.io`
- **Permissions granted:** Contents: **read & write**; Metadata: read
  - Enough to clone + commit + push to `sheesh-host.github.io`. No Pages/Actions/PR scopes.

## Credentials already set on `sheesh-host/box`

| Kind     | Name                      | Value / source                                   |
|----------|---------------------------|--------------------------------------------------|
| Secret   | `RELEASE_BOT_PRIVATE_KEY` | App private key PEM (`sheesh-release-bot.2026-05-25.private-key.pem`) |
| Variable | `RELEASE_BOT_APP_ID`      | `3864019`                                        |

(Set by `so0k`, the only account with admin on the repo.)

## How to use in the workflow

Mint a short-lived installation token scoped **only** to the Pages repo, then push to it:

```yaml
      - name: Mint release-bot token
        if: vars.AWS_OIDC_ROLE_ARN != ''
        id: app-token
        uses: actions/create-github-app-token@v2
        with:
          app-id: ${{ vars.RELEASE_BOT_APP_ID }}
          private-key: ${{ secrets.RELEASE_BOT_PRIVATE_KEY }}
          owner: sheesh-host
          repositories: sheesh-host.github.io

      - name: Publish amis.json to the Pages repo
        if: vars.AWS_OIDC_ROLE_ARN != ''
        run: |
          tmp="$(mktemp -d)"
          git clone --depth 1 \
            "https://x-access-token:${{ steps.app-token.outputs.token }}@github.com/sheesh-host/sheesh-host.github.io.git" "$tmp"
          # IMPORTANT: see "Where amis.json must land" below — public/, not repo root.
          cp ami/amis.json "$tmp/public/amis.json"
          cd "$tmp"
          git config user.name  "sheesh-release-bot[bot]"
          git config user.email "sheesh-release-bot[bot]@users.noreply.github.com"
          git add public/amis.json
          git commit -m "chore: update amis.json (${GITHUB_REF_NAME})" || { echo "no changes"; exit 0; }
          git push origin HEAD:main
```

## Where `amis.json` must land (non-obvious!)

`sheesh-host.github.io` is **NOT** raw static files — it's a **Vite app deployed via GitHub
Actions** (`gh api repos/.../pages` → `build_type: "workflow"`, source branch `main`).

- The deploy workflow (`.github/workflows/deploy.yml`) runs `pnpm run build` and publishes `dist/`.
- Vite copies everything under **`public/`** to the site root at build time.
- Therefore write the file to **`public/amis.json`** → it is served at `https://sheesh.host/amis.json`.
- Do **NOT** drop it at the repo root; the root is source, not served output.
- Pushing to `main` automatically triggers `deploy.yml`, which rebuilds and publishes. No extra
  Pages API call needed (and per house rules, never `POST .../pages/builds` — that forces a
  legacy Jekyll build of source).

## Verify after a run

```sh
curl -fsSL https://sheesh.host/amis.json | jq .
```

The CLI's default `--ami-catalog-url` is `https://sheesh.host/amis.json`, so this closes the
TODO in `build-ami.yml`.
