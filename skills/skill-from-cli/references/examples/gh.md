---
name: gh
description: >-
  GitHub CLI for repositories, issues, pull requests, releases, gists, Actions
  workflows, and API queries. Use when working with GitHub from the command line:
  creating/viewing/merging PRs, managing issues, checking CI status, browsing
  repos, making API calls, or any GitHub operation. Covers gh auth, gh pr, gh
  issue, gh repo, gh run, gh api, and extensions.
---

# GitHub CLI

## Quick start

```bash
# Authenticate (one-time)
gh auth login
# Clone a repo and cd into it
gh repo clone owner/repo && cd repo
# Create a PR from current branch
gh pr create --fill
# Check CI status
gh pr checks
# Merge when ready
gh pr merge --squash --delete-branch
```

## Commands

### Pull requests

```bash
# List open PRs
gh pr list
# View PR details
gh pr view 42
gh pr view 42 --json state,reviews,checks
# Create PR with title and body
gh pr create --title "feat: add caching" --body "Adds Redis caching layer"
# Create PR filling title/body from commits
gh pr create --fill
# Review
gh pr review 42 --approve
gh pr review 42 --request-changes --body "needs error handling"
# Check CI status
gh pr checks 42
# Checkout a PR locally
gh pr checkout 42
# Merge
gh pr merge 42 --squash --delete-branch
gh pr merge 42 --rebase --auto
# Diff
gh pr diff 42
```

### Issues

```bash
# List issues
gh issue list
gh issue list --label bug --assignee @me
# Create
gh issue create --title "Bug: crash on startup" --body "Steps to reproduce..."
gh issue create --label bug,urgent --assignee octocat
# View
gh issue view 123
gh issue view 123 --json title,body,labels,assignees
# Close / reopen
gh issue close 123 --reason "not planned"
gh issue reopen 123
# Comment
gh issue comment 123 --body "Fixed in #42"
# Edit
gh issue edit 123 --add-label priority:high --milestone v2.0
```

### Repositories

```bash
# Clone
gh repo clone owner/repo
# Create new repo
gh repo create my-project --public --clone
gh repo create my-project --private --template owner/template
# Fork
gh repo fork owner/repo --clone
# View repo info
gh repo view owner/repo
gh repo view owner/repo --json description,stargazerCount
# List your repos
gh repo list --limit 20
gh repo list owner --language go
# Sync fork with upstream
gh repo sync owner/fork
```

### Actions / CI

```bash
# List recent workflow runs
gh run list
gh run list --workflow test.yml --branch main
# View run details
gh run view 123456
# Watch a run in real-time
gh run watch 123456
# View logs
gh run view 123456 --log
gh run view 123456 --log-failed
# Re-run failed jobs
gh run rerun 123456 --failed
# Trigger a workflow
gh workflow run deploy.yml --ref main -f environment=staging
```

### Releases

```bash
# Create release from tag
gh release create v1.0.0 --title "v1.0.0" --generate-notes
# Create with assets
gh release create v1.0.0 ./dist/*.tar.gz --title "v1.0.0"
# List releases
gh release list
# Download assets
gh release download v1.0.0 --pattern "*.tar.gz"
```

### API (escape hatch for anything)

```bash
# GET request
gh api repos/owner/repo
# With jq filtering
gh api repos/owner/repo --jq '.stargazers_count'
# POST
gh api repos/owner/repo/issues --method POST -f title="New issue" -f body="Details"
# GraphQL
gh api graphql -f query='{ viewer { login } }'
# Paginate
gh api repos/owner/repo/issues --paginate --jq '.[].title'
```

## Auth

```bash
gh auth login                  # interactive browser login
gh auth login --with-token     # pipe a token via stdin
gh auth status                 # check current auth
gh auth switch                 # switch between accounts
gh auth token                  # print current token
```

## Example: Full PR workflow

```bash
git checkout -b feat/caching
# ... make changes ...
git add -A && git commit -m "feat: add Redis caching"
git push -u origin feat/caching
gh pr create --fill --reviewer teammate
gh pr checks                   # wait for CI
gh pr merge --squash --delete-branch
```

## Example: Triage issues

```bash
# Find unassigned bugs
gh issue list --label bug --assignee "" --json number,title --jq '.[] | "#\(.number) \(.title)"'
# Assign yourself
gh issue edit 45 --add-assignee @me
# Add to milestone
gh issue edit 45 --milestone "v2.1"
```

## Gotchas

- **`--json` + `--jq` combo**: Use `--json` to select fields, `--jq` to filter.
  Without `--json`, `--jq` won't work.
- **Default branch**: `gh pr create` targets the repo's default branch.
  Use `--base other-branch` to override.
- **Auth scopes**: Some operations need extra scopes.
  `gh auth refresh -s read:project` adds scopes without re-login.
- **Rate limits**: `gh api` respects GitHub rate limits. Use `--paginate`
  carefully on large repos.

## Specific tasks

* **Gists** — `gh gist create`, `gh gist list`, `gh gist view`
* **Codespaces** — `gh codespace create`, `gh codespace ssh`
* **Extensions** — `gh extension install owner/gh-ext`, `gh extension list`
* **SSH keys** — `gh ssh-key add ~/.ssh/id_ed25519.pub`
* **Search** — `gh search repos "language:rust stars:>1000"`, `gh search issues "is:open label:bug"`
