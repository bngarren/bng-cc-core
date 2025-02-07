#!/bin/bash

# Ensure the latest tags are fetched
git fetch --tags --force

# Check if running in GitHub Actions release workflow
GITHUB_RELEASE=false
if [[ "$GITHUB_REF_TYPE" == "tag" ]]; then
    GITHUB_RELEASE=true
fi

# Check for uncommitted changes (both modified and untracked files) – only for local builds
is_dirty="false"
if [[ "$GITHUB_RELEASE" == "false" ]]; then
    if ! git diff --quiet HEAD -- || ! git diff --cached --quiet || [ -n "$(git ls-files --others --exclude-standard)" ]; then
        is_dirty="true"
    fi

    # Prompt the user if dirty
    if [ "$is_dirty" = "true" ]; then
        read -r -p "There are uncommitted changes. Are you sure you want to build? (Y/n) " user_input
        user_input=$(echo "$user_input" | tr '[:upper:]' '[:lower:]') # Convert to lowercase (POSIX-compliant)

        if [ "$user_input" = "n" ] || [ "$user_input" = "no" ]; then
            echo "Build aborted."
            exit 1
        fi
    fi
fi

# Function to get version information
get_version_info() {
    # Get latest tag (fallback to "v0.0.0" if no tags exist)
    local latest_tag=$(git describe --tags --abbrev=0 2>/dev/null || echo "v0.0.0")
    latest_tag=$(echo $latest_tag | sed 's/^v//') # Strip 'v' prefix for consistency

    # Detect if running in GitHub Actions release
    if [[ "$GITHUB_RELEASE" == "true" ]]; then
        echo "$latest_tag"
        return
    fi

    # Get current branch, handling detached HEAD (GitHub Actions checkouts)
    local current_branch
    if [[ -n "$GITHUB_REF_NAME" ]]; then
        current_branch="$GITHUB_REF_NAME"
    else
        current_branch=$(git rev-parse --abbrev-ref HEAD)
        [[ "$current_branch" == "HEAD" ]] && current_branch="detached"
    fi

    # Get short commit hash
    local commit_hash=$(git rev-parse --short HEAD)

    # If dirty, override commit_hash with "dirty"
    if [ "$is_dirty" = "true" ]; then
        commit_hash="dirty"
    fi

    # Check if current commit is tagged and clean
    if git describe --exact-match --tags >/dev/null 2>&1 && [ "$is_dirty" = "false" ]; then
        version="$latest_tag" # Use the exact tag for clean releases
    else
        # Format: lastTag-wip-branch-commitHash (or dirty)
        version="${latest_tag}-wip-${current_branch}-${commit_hash}"
    fi

    echo "$version"
}

# Get version info
VERSION=$(get_version_info)
echo "Building version: $VERSION"

if [ -d "src" ]; then
    echo "Found src directory"
else
    echo "ERROR: src directory not found!"
    exit 1
fi

# Create version.lua that will be included in the bundle
cat >src/version.lua <<EOL
-- Generated by build script
return {
    VERSION = '${VERSION}',
    COMMIT = '$(git rev-parse --short HEAD)',
    BRANCH = '$(git rev-parse --abbrev-ref HEAD)',
    BUILD_DATE = '$(date '+%Y-%m-%d %H:%M:%S')'
}
EOL

# Create dist directory
mkdir -p dist
rm -rf dist/*

# Build core bundle using luacc
echo 'Building core bundle...'
echo "Attempting to build from $(pwd)"

cd src
echo "Working from $(pwd)"

# Find all .lua files in current directory, strip .lua extension, exclude init and version
MODULES="version $(find . -maxdepth 1 -name "*.lua" ! -name "init.lua" ! -name "version.lua" -exec basename {} .lua \;)"
echo "Found modules: $MODULES"

# Use luacc with found modules
luacc \
    -o ../dist/bng-cc-core.lua \
    -i . \
    init \
    $MODULES

cd ..

# Only continue if the bundle was created successfully
if [ ! -f "dist/bng-cc-core.lua" ]; then
    echo "ERROR: Bundle creation failed"
    exit 1
fi

# Create minified version
echo 'Minifying bng-cc-core.lua...'
mkdir -p dist/release

# Save header comments with git tag version
echo "-- bng-cc-core by bngarren" >dist/release/bng-cc-core.min.lua
echo "-- MIT License" >>dist/release/bng-cc-core.min.lua
echo "-- Version $VERSION" >>dist/release/bng-cc-core.min.lua
echo "-- Generated $(date '+%Y-%m-%d %H:%M:%S')" >>dist/release/bng-cc-core.min.lua

# Minify using luamin
CONTENT=$(cat dist/bng-cc-core.lua)
if [ -n "$CONTENT" ]; then
    echo "$CONTENT" | luamin -c >>dist/release/bng-cc-core.min.lua
else
    echo "ERROR: No content to minify"
    exit 1
fi

echo "Build complete! Output files:"
ls -s dist/release/
