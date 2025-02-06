## Build & Release Workflow

This library uses a git tag-based versioning system and a build process that creates a minified bundle. Here's how to work with it:

### Development Workflow

1. Make your changes in the `src` directory
2. Build locally to test:
   ```bash
   ./build.sh
   ```

This creates:

- dist/bng-cc-core.lua: The bundled library
- dist/release/bng-cc-core.min.lua: Minified version with header info

During development, the build will have a version like:

- 0.0.5-dev if changes exist after the last tag
- dev-a1b2c3d if no tags exist or working on a new commit


## Release Workflow
When ready to release a new version:
- Ensure all changes are committed and your working directory is clean
- Tag the release and push the tag to remote (or do this all on remote through Github draft new release)

### 1. Tag the release (use semantic versioning):
```bash
git tag -a v0.0.5 -m "Release version 0.0.5"
git push origin v0.0.5
```

### 2. Build the release (optional):
- Run a dockerized build step so that lua and dependencies don't have to be managed locally
```bash
docker run -v $(pwd):/app bng-cc-core-builder
```
- This puts the bundled file in dist/ 
- The build will now use the clean tag version (e.g., "0.0.5") since it was built on a tagged commit without working dir changes
- The bng-cc-core.min.lua file can be manually attached to a release

### 3. Create a GitHub release:
- Go to GitHub releases
- Create new release from the tag
- Attach the built bng-cc-core.min.lua file

### Github action
- All in one build workflow on Release


## Version Numbering

- We use semantic versioning (MAJOR.MINOR.PATCH)
- Version numbers come from git tags
- Development builds are automatically marked with suffixes
- A version.lua is embedded in the built files

## Using the Library

### Installing
- Download the latest bng-cc-core.min.lua
- Place it in your project's lib directory

### Requiring in Your Code
- Add the library path to package.path if needed
```lua
package.path = package.path .. ";/bng/common/?.lua;/bng/common/?/init.lua"
```

- Require the library
```lua
-- ✅ Correct way:
local core = require('bng-cc-core')
local util = core.util

-- ❌ Won't work:
local util = require('bng-cc-core.util')
```

- Use the library
```lua
print(core._VERSION)  -- prints current version
```

## Why the bundled structure?
The library is bundled into a single file for easier distribution and installation. While this means you can't require individual modules directly, having them accessible through the main import provides:

- Simpler installation (just one file)
- Guaranteed module availability
- Consistent versioning across all modules