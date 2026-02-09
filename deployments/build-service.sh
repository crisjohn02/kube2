#!/bin/bash

# Parse arguments
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --version=*)
            VERSION="${1#*=}"
            shift
            ;;
        *)
            if [[ -z "$REPO_NAME" ]]; then
                REPO_NAME="$1"
                shift
            else
                echo "Unknown parameter: $1"
                exit 1
            fi
            ;;
    esac
done

if [[ -z "$REPO_NAME" ]]; then
    logger "Script called without repository name"
    exit 1
fi

# Default to 'latest' if VERSION is not set
if [[ -z "$VERSION" ]]; then
    VERSION="latest"
fi

TMPDIR=$(mktemp -d)

cd "$TMPDIR" || { logger "Error changing directory"; exit 1; }

# Corrected git clone command with SSH syntax
git clone "git@github.com:ssr-platforms/${REPO_NAME}.git" . || { logger "Error cloning project"; exit 1; }


# Check if the .env file exists before copying
ENV_FILE="$HOME/config/env/${REPO_NAME}.env"
if [[ -f "$ENV_FILE" ]]; then
    cp "$ENV_FILE" .env
else
    logger "No .env file found for ${REPO_NAME}"
fi

# Display the contents of the .env file
cat .env

# Build the Docker image
docker image build --no-cache -t "${REPO_NAME}:${VERSION}" . || { logger "Error building Docker image"; exit 1; }

cd - || exit

rm -rf "$TMPDIR"
