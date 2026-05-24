# git-sync

## Host Verification

- [March 24th 2023 - GitHub updated RSA SSH Host key](https://github.blog/2023-03-23-we-updated-our-rsa-ssh-host-key/)

[API Endpoint](https://github.blog/changelog/2022-01-18-githubs-ssh-host-keys-are-now-published-in-the-api/)

```sh
gh api \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  /meta \
  --jq '.ssh_keys[] | "github.com \(.)"' > known_hosts
```
