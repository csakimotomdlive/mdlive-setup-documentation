# Cherry-pick to QA8

Utility script for applying a single commit from another branch onto `qa8`.

**Script:** [`cherry_pick_to_qa8.sh`](./cherry_pick_to_qa8.sh)

## Prerequisites

- Run from anywhere inside the Stern git repository.
- Working tree must be clean (no uncommitted changes). Stash or commit first if needed.
- Network access to fetch from `origin`.

## Setup

Make the script executable once:

```bash
chmod +x bin/cherry_pick_to_qa8.sh
```

## Usage

```bash
bin/cherry_pick_to_qa8.sh <commit-hash> [--push]
```

| Argument | Description |
|----------|-------------|
| `<commit-hash>` | Full or abbreviated commit SHA to cherry-pick (required) |
| `--push` | Push `qa8` to `origin` after a successful cherry-pick |
| `-h`, `--help` | Show usage |

## Examples

Cherry-pick only (does not push):

```bash
bin/cherry_pick_to_qa8.sh ea50b889
bin/cherry_pick_to_qa8.sh ea50b889c9be8cf28b24f41e3f6d5cbed51ce036
```

Cherry-pick and push:

```bash
bin/cherry_pick_to_qa8.sh ea50b889 --push
```

## What the script does

1. Validates the commit hash exists locally.
2. Verifies the working tree is clean.
3. Records your current branch.
4. Fetches, checks out, and pulls the latest `qa8` from `origin`.
5. Cherry-picks the given commit onto `qa8`.
6. Optionally pushes to `origin/qa8` when `--push` is passed.
7. Returns you to your original branch (unless you were already on `qa8`).

On success, the script prints the new commit SHA and how many commits `qa8` is ahead of `origin/qa8`.

## Resolving conflicts

If the cherry-pick fails due to merge conflicts:

1. Fix conflicts in the affected files.
2. Stage the resolved files: `git add <files>`
3. Continue: `git cherry-pick --continue`
4. Push when ready: `git push origin qa8`

To abandon the cherry-pick:

```bash
git cherry-pick --abort
```

## Manual equivalent

The script automates these steps:

```bash
git fetch origin qa8
git checkout qa8
git pull origin qa8
git cherry-pick <commit-hash>
git push origin qa8   # optional
```
