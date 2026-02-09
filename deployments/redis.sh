#!/bin/bash

# Ensure the script is run as root to access Docker volumes

# Check if the first argument is 'staging'
if [ "$1" == "staging" ]; then
  YAML_FILE="stage.yaml"
else
  YAML_FILE="stack.yaml"
fi

echo "Removing the docker stack..."
docker stack rm redis-stack

echo "Clearing the persisted data..."
rm -rf /mnt/data/redis-stack/redis-node-*/*

echo "Deploying the stack using the $YAML_FILE file..."
cd ~/deployments/redis-stack
docker stack deploy -d -c $YAML_FILE redis-stack

echo "Redis stack redeployment completed."
