#!/bin/bash

# Check if the secrets file exists
SECRETS_FILE=${1:-secrets}

if [ ! -f "$SECRETS_FILE" ]; then
  echo "Secrets file '$SECRETS_FILE' not found!"
  exit 1
fi

# Read secrets from the file and create Docker secrets
while IFS= read -r line || [ -n "$line" ]; do
  # Skip empty lines and comments
  if [[ -z "$line" ]] || [[ "$line" =~ ^# ]]; then
    continue
  fi

  # Extract secret name and value
  secret_name="${line%%=*}"
  secret_value="${line#*=}"

  # Trim whitespace from secret_name
  secret_name="$(echo -e "${secret_name}" | sed -e 's/^[[:space:]]*//;s/[[:space:]]*$//')"

  # Remove surrounding single quotes from secret_value
  secret_value="${secret_value#\'}"
  secret_value="${secret_value%\'\'}"

  # Replace escaped newlines and tabs
  secret_value="$(echo -e "$secret_value")"

  # Check if the secret already exists
  if docker secret ls --format '{{.Name}}' | grep -wq "$secret_name"; then
    echo "Secret '$secret_name' already exists. Skipping."
    continue
  fi

  # Create the Docker secret using printf
  printf "%s" "$secret_value" | docker secret create "$secret_name" -
  echo "Secret '$secret_name' created."
done < "$SECRETS_FILE"
