#!/bin/bash

# Quick starts the dev environment by fetching from origin and pulling/rebasing the local dev branch onto any remote dev changes

# Define ANSI colors for macOS & Zsh
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
GREEN='\033[1;32m'
RED='\033[1;31m'
RESET='\033[0m'

echo "${YELLOW}🚀 Fetching latest changes from remote...${RESET}"
git fetch origin

echo "${BLUE}🔄 Checking out 'dev' branch and pulling latest updates...${RESET}"
git checkout dev && git pull origin dev --rebase

# Check if dev is behind master
echo "${BLUE}🔍 Checking if 'dev' is behind 'master'...${RESET}"
if git rev-list --left-right --count dev...master | awk '{exit $1!=0}'; then
    echo "${RED}⚠️  'dev' is behind 'master'. Syncing now...${RESET}"
    git checkout master
    git pull origin master
    git checkout dev
    git merge master --no-ff
    git push origin dev
    echo "${GREEN}✅ 'dev' is now up-to-date with 'master'!${RESET}"
else
    echo "${GREEN}✅ 'dev' is already up-to-date with 'master'!${RESET}"
fi

echo "${GREEN}💻 Your development environment is ready! Happy coding! 🚀${RESET}"
