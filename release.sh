#!/usr/bin/env bash
# release.sh: interactively tag and release timing_interface to GitHub.
#
# Shows the previous release tag, asks for the new tag and a message,
# commits any pending changes with that message, creates an annotated
# tag, and pushes the branch and tag to origin.

set -euo pipefail

REMOTE="origin"
SEMVER_RE='^v?([0-9]+)\.([0-9]+)\.([0-9]+)(-[0-9A-Za-z.-]+)?$'

die()  { echo "ERROR: $*" >&2; exit 1; }
info() { echo "==> $*"; }

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    echo "Usage: ./release.sh"
    echo "Interactive: shows the previous tag, asks for a new tag (vX.Y.Z) and a message,"
    echo "commits pending changes, tags, and pushes to $REMOTE."
    exit 0
fi
[[ $# -eq 0 ]] || die "release.sh takes no options (see -h)"

# True if semver $1 is strictly greater than semver $2.
# A final release ranks above its pre-releases (1.0.0 > 1.0.0-rc.1).
version_gt() {
    [[ "$1" =~ $SEMVER_RE ]] || return 1
    local a=("${BASH_REMATCH[@]:1:3}") a_pre="${BASH_REMATCH[4]#-}"
    [[ "$2" =~ $SEMVER_RE ]] || return 1
    local b=("${BASH_REMATCH[@]:1:3}") b_pre="${BASH_REMATCH[4]#-}"
    local i
    for i in 0 1 2; do
        (( a[i] > b[i] )) && return 0
        (( a[i] < b[i] )) && return 1
    done
    [[ "$a_pre" == "$b_pre" ]] && return 1
    [[ -z "$a_pre" ]] && return 0
    [[ -z "$b_pre" ]] && return 1
    [[ "$(printf '%s\n%s\n' "$a_pre" "$b_pre" | sort -V | tail -n1)" == "$a_pre" ]]
}

# Suggest the next patch version after $1 (or v0.1.0 if there is none).
next_patch() {
    [[ "$1" =~ $SEMVER_RE ]] || { echo "v0.1.0"; return; }
    echo "v${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.$((BASH_REMATCH[3] + 1))"
}

cd "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)" \
    || die "not inside a git repository"
git remote get-url "$REMOTE" >/dev/null 2>&1 || die "remote '$REMOTE' not found"

BRANCH="$(git symbolic-ref --short HEAD)" || die "not on a branch (detached HEAD)"
HAS_HEAD=0
git rev-parse -q --verify HEAD >/dev/null && HAS_HEAD=1

info "Fetching $REMOTE"
git fetch --quiet --tags "$REMOTE" || die "git fetch $REMOTE failed"
if (( HAS_HEAD )) && git rev-parse -q --verify "refs/remotes/$REMOTE/$BRANCH" >/dev/null; then
    behind="$(git rev-list --count "HEAD..$REMOTE/$BRANCH")"
    (( behind == 0 )) || die "$BRANCH is $behind commit(s) behind $REMOTE/$BRANCH; pull first"
fi

# Previous release tag
PREV_TAG=""
if (( HAS_HEAD )); then
    PREV_TAG="$(git describe --tags --abbrev=0 --match 'v[0-9]*' 2>/dev/null || true)"
fi
echo
echo "Branch       : $BRANCH"
if [[ -n "$PREV_TAG" ]]; then
    echo "Previous tag : $PREV_TAG  ($(git log -1 --format='%cs' "$PREV_TAG"): $(git tag -l --format='%(contents:subject)' "$PREV_TAG"))"
    echo
    echo "Commits since $PREV_TAG:"
    commits="$(git log --no-merges --format='  - %s (%h, %an)' "$PREV_TAG..HEAD")"
    echo "${commits:-  (none)}"
else
    echo "Previous tag : none"
fi

# Pending changes (these are committed as part of the release)
CHANGES="$(git status --porcelain)"
if [[ -n "$CHANGES" ]]; then
    echo
    echo "Uncommitted changes (will be committed with your message):"
    echo "$CHANGES" | sed 's/^/  /'
fi
echo

# Ask for the tag
DEFAULT_TAG="$(next_patch "$PREV_TAG")"
while true; do
    read -r -p "New tag [$DEFAULT_TAG]: " TAG
    TAG="${TAG:-$DEFAULT_TAG}"
    [[ "$TAG" == v* ]] || TAG="v$TAG"
    if [[ ! "$TAG" =~ $SEMVER_RE ]]; then
        echo "  Tag must look like v1.2.3 or v1.2.3-rc.1"
    elif git rev-parse -q --verify "refs/tags/$TAG" >/dev/null \
         || git ls-remote --exit-code --tags "$REMOTE" "refs/tags/$TAG" >/dev/null 2>&1; then
        echo "  Tag $TAG already exists"
    elif [[ -n "$PREV_TAG" ]] && ! version_gt "$TAG" "$PREV_TAG"; then
        echo "  Tag must be greater than $PREV_TAG"
    else
        break
    fi
done

# Ask for the message
while true; do
    read -r -p "Release message: " MESSAGE
    [[ -n "${MESSAGE// }" ]] && break
    echo "  Message cannot be empty"
done

echo
echo "About to release:"
echo "  Tag     : $TAG"
echo "  Message : $MESSAGE"
[[ -n "$CHANGES" ]] && echo "  Commit  : all changes listed above"
echo "  Push    : $BRANCH and $TAG to $REMOTE ($(git remote get-url "$REMOTE"))"
read -r -p "Proceed? [y/N] " answer
[[ "$answer" =~ ^[Yy]$ ]] || die "aborted"

if [[ -n "$CHANGES" ]]; then
    info "Committing changes"
    git add -A
    git commit --quiet -m "$MESSAGE"
elif (( ! HAS_HEAD )); then
    die "nothing to release: no commits and no changes"
fi

info "Creating tag $TAG"
git tag -a "$TAG" -m "$TAG: $MESSAGE"

info "Pushing $BRANCH and $TAG to $REMOTE"
git push --atomic "$REMOTE" "$BRANCH" "$TAG" \
    || die "push failed; commit and tag exist locally. Fix the cause and rerun:
       git push --atomic $REMOTE $BRANCH $TAG"

info "Released $TAG"
