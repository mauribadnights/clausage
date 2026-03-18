#!/bin/bash
set -e

# Usage: ./release.sh [major|minor|patch]
# Defaults to patch if no argument given.
#
# This script:
# 1. Ensures you're on dev with a clean tree
# 2. Runs tests
# 3. Bumps the version (semver)
# 4. Updates Info.plist
# 5. Commits the version bump to dev
# 6. Pushes dev
# 7. Creates a PR from dev → main
# 8. Merges the PR (CI must pass first)
# 9. Tags main with the new version
# 10. Pushes the tag (triggers release workflow)

BUMP_TYPE="${1:-patch}"

if [[ "$BUMP_TYPE" != "major" && "$BUMP_TYPE" != "minor" && "$BUMP_TYPE" != "patch" ]]; then
    echo "Usage: ./release.sh [major|minor|patch]"
    exit 1
fi

# Ensure working tree is clean
if [ -n "$(git status --porcelain)" ]; then
    echo "Error: Working tree is not clean. Commit or stash changes first."
    exit 1
fi

# Ensure we're on dev
BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ "$BRANCH" != "dev" ]; then
    echo "Error: Must be on dev branch (currently on $BRANCH)"
    exit 1
fi

# Ensure dev is up to date
git pull origin dev

# Run tests
echo "Running tests..."
swift test
echo "Tests passed."

# Get current version from latest tag (or default to 0.0.0)
CURRENT_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "v0.0.0")
CURRENT_VERSION="${CURRENT_TAG#v}"

IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT_VERSION"
MAJOR="${MAJOR:-0}"
MINOR="${MINOR:-0}"
PATCH="${PATCH:-0}"

case "$BUMP_TYPE" in
    major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
    minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
    patch) PATCH=$((PATCH + 1)) ;;
esac

NEW_VERSION="$MAJOR.$MINOR.$PATCH"
NEW_TAG="v$NEW_VERSION"

echo ""
echo "Version bump: $CURRENT_VERSION → $NEW_VERSION ($BUMP_TYPE)"
echo ""

# Update Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $NEW_VERSION" Clausage/Info.plist

# Generate changelog
CHANGELOG=$(git log "$CURRENT_TAG"..HEAD --pretty=format:"- %s" --no-merges | grep -v "^- Release v")
echo "Changelog:"
echo "$CHANGELOG"
echo ""

# Commit version bump on dev
git add Clausage/Info.plist
git commit -m "Bump version to $NEW_VERSION"
git push origin dev

# Create PR from dev → main
echo "Creating PR..."
PR_URL=$(gh pr create \
    --base main \
    --head dev \
    --title "Release $NEW_TAG" \
    --body "$(cat <<EOF
## Release $NEW_TAG

### Changes since $CURRENT_TAG
$CHANGELOG

---
Merging this PR and pushing the tag will trigger the release workflow.
EOF
)")

echo "PR created: $PR_URL"
echo ""

# Wait for CI to pass, then merge
echo "Waiting for CI checks to pass..."
gh pr checks "$PR_URL" --watch --fail-fast

echo "CI passed. Merging..."
gh pr merge "$PR_URL" --merge --delete-branch=false

# Tag the merge commit on main
git fetch origin main
git tag -a "$NEW_TAG" origin/main -m "Release $NEW_VERSION" -m "$CHANGELOG"
git push origin "$NEW_TAG"

# Stay on dev
git checkout dev
git pull origin dev

echo ""
echo "Released $NEW_TAG"
echo "GitHub Release will be created at:"
echo "https://github.com/mauribadnights/clausage/releases/tag/$NEW_TAG"
