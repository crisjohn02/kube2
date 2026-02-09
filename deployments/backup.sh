#!/bin/bash

# Ensure the script is run as root to access Docker volumes
if [ "$(id -u)" -ne 0 ]; then
  echo "Please run this script as root or with sudo."
  exit 1
fi

# Get the current date to create a backup folder
TODAYS_DATE=$(date +%F)
BACKUP_DIR="/backup/$TODAYS_DATE"

# Create the backup directory if it doesn't exist
mkdir -p "$BACKUP_DIR"

# Get the list of all Docker volume names
VOLUME_NAMES=$(docker volume ls --format "{{.Name}}")

# Check if there are any Docker volumes
if [ -z "$VOLUME_NAMES" ]; then
  echo "No Docker volumes found."
  exit 0
fi

# Loop through each volume and create a backup
for VOLUME_NAME in $VOLUME_NAMES; do
  # Inspect the volume to get the Mountpoint
  MOUNTPOINT=$(docker volume inspect --format '{{.Mountpoint}}' "$VOLUME_NAME")
  
  # Check if the mountpoint exists and is accessible
  if [ -d "$MOUNTPOINT" ]; then
    # Backup file name with timestamp
    BACKUP_NAME="${BACKUP_DIR}/${VOLUME_NAME}_backup_$(date +%F_%T).tar.gz"
    
    # Run the backup
    echo "Backing up volume '$VOLUME_NAME' from '$MOUNTPOINT' to $BACKUP_NAME..."
    tar czf "$BACKUP_NAME" -C "$MOUNTPOINT" .
    echo "Backup of volume '$VOLUME_NAME' completed."
  else
    echo "Warning: Mountpoint '$MOUNTPOINT' does not exist or is inaccessible."
  fi
done

echo "All backups completed and stored in $BACKUP_DIR."
