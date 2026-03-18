#!/bin/bash
set -e

# Usage: ./release.sh [major|minor|patch]
# Defaults to patch if no argument given.
#
# This script:
# 1. Runs tests
# 2. Bumps the version (semver)
# 3. Updates Info.plist
# 4. Commits the version bump
# 5. Tags the commit
# 6. Pushes to origin (triggers CI release workflow)

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

# Ensure we're on main
BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ "$BRANCH" != "main" ]; then
    echo "Error: Must be on main branch (currently on $BRANCH)"
    exit 1
fi

# Run tests first
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

# Generate changelog from commits since last tag
echo "## What's Changed" > /tmp/clausage-changelog.md
echo "" >> /tmp/clausage-changelog.md
git log "$CURRENT_TAG"..HEAD --pretty=format:"- %s" --no-merges >> /tmp/clausage-changelog.md
echo "" >> /tmp/clausage-changelog.md

echo "Changelog:"
cat /tmp/clausage-changelog.md
echo ""

# Commit version bump
git add Clausage/Info.plist
git commit -m "Release $NEW_TAG"

# Tag
git tag -a "$NEW_TAG" -m "Release $NEW_VERSION" -m "$(cat /tmp/clausage-changelog.md)"

# Push commit and tag
echo "Pushing to origin..."
git push origin main
git push origin "$NEW_TAG"

echo ""
echo "Released $NEW_TAG"
echo "CI will now build and publish the release at:"
echo "https://github.com/mauribadnights/clausage/releases/tag/$NEW_TAG"
