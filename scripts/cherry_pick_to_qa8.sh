#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<EOF
Usage: $(basename "$0") <commit-hash> [--push]

Cherry-pick a commit onto the qa8 branch.

  <commit-hash>  Full or abbreviated commit SHA to cherry-pick
  --push         Push qa8 to origin after a successful cherry-pick

Examples:
  $(basename "$0") ea50b889
  $(basename "$0") ea50b889c9be8cf28b24f41e3f6d5cbed51ce036 --push
EOF
}

TARGET_BRANCH="qa8"
PUSH=false
COMMIT=""

for arg in "$@"; do
  case "$arg" in
    -h|--help)
      usage
      exit 0
      ;;
    --push)
      PUSH=true
      ;;
    *)
      if [[ -z "$COMMIT" ]]; then
        COMMIT="$arg"
      else
        echo "Error: unexpected argument: $arg" >&2
        usage >&2
        exit 1
      fi
      ;;
  esac
done

if [[ -z "$COMMIT" ]]; then
  usage >&2
  exit 1
fi

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "Error: not inside a git repository" >&2
  exit 1
}
cd "$REPO_ROOT"

if ! git cat-file -e "${COMMIT}^{commit}" 2>/dev/null; then
  echo "Error: '$COMMIT' is not a valid commit" >&2
  exit 1
fi

if [[ -n "$(git status --porcelain)" ]]; then
  echo "Error: working tree is not clean. Commit or stash changes first." >&2
  exit 1
fi

ORIGINAL_BRANCH="$(git branch --show-current)"
COMMIT_SUBJECT="$(git log -1 --format='%s' "$COMMIT")"

echo "Cherry-picking onto $TARGET_BRANCH:"
echo "  Commit:  $COMMIT"
echo "  Subject: $COMMIT_SUBJECT"
echo "  From:    ${ORIGINAL_BRANCH:-<detached HEAD>}"

git fetch origin "$TARGET_BRANCH"
git checkout "$TARGET_BRANCH"
git pull origin "$TARGET_BRANCH"

if ! git cherry-pick "$COMMIT"; then
  echo ""
  echo "Cherry-pick failed. Resolve conflicts, then run:"
  echo "  git cherry-pick --continue"
  echo "Or abort with:"
  echo "  git cherry-pick --abort"
  exit 1
fi

NEW_SHA="$(git rev-parse --short HEAD)"
AHEAD="$(git rev-list --count "origin/$TARGET_BRANCH..HEAD")"

echo ""
echo "Success! Cherry-pick applied as $NEW_SHA on $TARGET_BRANCH"
echo "$TARGET_BRANCH is ahead of origin/$TARGET_BRANCH by $AHEAD commit(s)"

if $PUSH; then
  git push origin "$TARGET_BRANCH"
  echo "Pushed to origin/$TARGET_BRANCH"
else
  echo "Run 'git push origin $TARGET_BRANCH' to publish."
fi

if [[ -n "$ORIGINAL_BRANCH" && "$ORIGINAL_BRANCH" != "$TARGET_BRANCH" ]]; then
  git checkout "$ORIGINAL_BRANCH"
  echo "Returned to branch $ORIGINAL_BRANCH"
fi
