#!/bin/bash

# Ensure the latest tags are fetched
git fetch --tags --force

docker run -v $(pwd):/app bng-cc-core-builder