#!/bin/bash

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
        user_input=$(echo "$user_input" | tr '[:upper:]' '[:lower:]') # Convert to lowercase

        if [ "$user_input" = "n" ] || [ "$user_input" = "no" ]; then
            echo "Build aborted."
            exit 1
        fi
    fi
fi

# Function to get version information
get_version_info() {
    local latest_tag=$(git describe --tags --abbrev=0 2>/dev/null || echo "v0.0.0")
    latest_tag=$(echo "$latest_tag" | sed 's/^v//')

    if [[ "$GITHUB_RELEASE" == "true" ]]; then
        echo "$latest_tag"
        return
    fi

    local current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
    local commit_hash=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")

    if [ "$is_dirty" = "true" ]; then
        commit_hash="dirty"
    fi

    if git describe --exact-match --tags >/dev/null 2>&1 && [ "$is_dirty" = "false" ]; then
        version="$latest_tag"
    else
        version="${latest_tag}+${current_branch}.${commit_hash}"
    fi

    echo "$version"
}

# Get version info
VERSION=$(get_version_info)
echo "Building version: $VERSION"

# Validate required directories
if [ ! -d "bng-cc-core/lib" ]; then
    echo "ERROR: Required directory 'bng-cc-core/lib' not found!"
    exit 1
fi

# Create version.lua
cat >bng-cc-core/version.lua <<EOL
-- Generated by build script
return {
    VERSION = '${VERSION}',
    COMMIT = '$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")',
    BRANCH = '$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")',
    BUILD_DATE = '$(date '+%Y-%m-%d %H:%M:%S')'
}
EOL

# Create dist directory
mkdir -p dist
rm -rf dist/*

# Build core bundle
echo "Building core bundle..."
cd bng-cc-core

MODULES=$(find lib -type f -name "*.lua" | sed -E 's|lib/||g; s|.lua$||g')
echo "Found core modules: $MODULES"

luacc -o ../dist/bng-cc-core.lua -i lib init $MODULES
cd ..

# Verify core bundle was created
if [ ! -f "dist/bng-cc-core.lua" ]; then
    echo "ERROR: Core bundle creation failed"
    exit 1
fi

# Handle vendor dependencies (if any)
if [ -d "bng-cc-core/vendor" ] && [ -n "$(find bng-cc-core/vendor -name '*.lua' 2>/dev/null)" ]; then
    echo "Building vendor bundle..."
    cd bng-cc-core/vendor

    VENDOR_MODULES=$(find . -name "*.lua" | sed 's|.lua$||g; s|^\./||g')
    echo "Found vendor modules: $VENDOR_MODULES"

    luacc -o ../../dist/vendor.lua -i . init $VENDOR_MODULES
    cd ../..
else
    echo "No vendor modules found, skipping vendor.lua bundle."
fi

# Minify both core and vendor (if vendor exists)
echo 'Minifying Lua bundles...'
mkdir -p dist/release

for file in "bng-cc-core" "vendor"; do
    if [ -f "dist/${file}.lua" ]; then
        echo "-- ${file} by bngarren" >dist/release/${file}.min.lua
        echo "-- MIT License" >>dist/release/${file}.min.lua
        echo "-- Version $VERSION" >>dist/release/${file}.min.lua
        echo "-- Generated $(date '+%Y-%m-%d %H:%M:%S')" >>dist/release/${file}.min.lua

        CONTENT=$(cat dist/${file}.lua)
        if [ -n "$CONTENT" ]; then
            echo "$CONTENT" | luamin -c >>dist/release/${file}.min.lua
        else
            echo "ERROR: No content to minify for $file"
            exit 1
        fi
    fi
done

echo "Build complete! Output files:"
ls -lh dist/release/
