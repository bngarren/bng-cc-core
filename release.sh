#!/bin/zsh

set -e  # Exit on error

# Define ANSI colors for macOS & Zsh
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
GREEN='\033[1;32m'
RED='\033[1;31m'
RESET='\033[0m'


# Ensure working directory is clean
if [[ -n $(git status --porcelain) ]]; then
    echo "${YELLOW}⚠️ Warning: Your working directory is not clean. Commit or stash your changes before proceeding.${RESET}"
    exit 1
fi

# Ensure we're on the master branch
current_branch=$(git rev-parse --abbrev-ref HEAD)
if [[ "$current_branch" != "master" ]]; then
    echo "${YELLOW}⚠️ Warning: You are not on the ${RESET}master${YELLOW} branch. Please switch to master before releasing.${RESET}"
    exit 1
fi

# Fetch the latest tags
git fetch --tags

# Get the latest tag
latest_tag=$(git describe --tags --abbrev=0 2>/dev/null || echo "v0.0.0")

# Ensure the latest tag has a "v" prefix
if [[ ! "$latest_tag" =~ ^v ]]; then
    latest_tag="v$latest_tag"
fi

echo "Most recent tag is ${latest_tag}."

# Suggest a new tag version
IFS='.' read -r -a version_parts <<< "${latest_tag:1}"  # Strip "v" prefix for version split
major=${version_parts[0]}
minor=${version_parts[1]}
patch=${version_parts[2]}

new_tag="v$major.$minor.$((patch + 1))"

# Prompt for the new tag
read -p "Enter new version tag (default: $new_tag): " input_tag

# Ensure the tag starts with "v"
if [[ -z "$input_tag" ]]; then
    tag="$new_tag"
else
    tag="${input_tag#v}"  # Strip "v" if user added it
    tag="v$tag"           # Ensure "v" is always added
fi

# Confirm the release
echo "${BLUE}✨ Release version $tag${RESET}"
read -p "(y/n)? " confirm

if [[ "$confirm" != "y" ]]; then
    echo "${RED}Release aborted.${RESET}"
    exit 1
fi

# Create a new tag
git tag "$tag"

# Push the tag to GitHub
git push origin "$tag"

# Create GitHub release with autogenerated release notes
gh release create "$tag" --generate-notes

echo "${GREEN}✅ Release $tag created successfully!${RESET}"