#!/bin/bash

# Ensure the script is run as root to access Docker volumes
if [ "$(id -u)" -ne 0 ]; then
  echo "Please run this script as root or with sudo."
  exit 1
fi

# Directory where backups are stored
BACKUP_DIR="/backup/$(date +%F)"  # Adjust the date or directory path as needed

# Loop through each backup file in the directory
for BACKUP_FILE in "$BACKUP_DIR"/*.tar.gz; do
  # Extract the volume name from the backup file name
  VOLUME_NAME=$(basename "$BACKUP_FILE" | cut -d '_' -f 1)

  # Determine the original mount point of the volume
  MOUNTPOINT=$(docker volume inspect --format '{{.Mountpoint}}' "$VOLUME_NAME")

  # Check if the mountpoint exists and is accessible
  if [ -d "$MOUNTPOINT" ]; then
    # Stop any containers using the volume
    CONTAINERS=$(docker ps -q --filter volume="$VOLUME_NAME")
    if [ -n "$CONTAINERS" ]; then
      echo "Stopping containers using volume '$VOLUME_NAME'..."
      docker stop $CONTAINERS
    fi

    # Restore the backup
    echo "Restoring backup from '$BACKUP_FILE' to '$MOUNTPOINT'..."
    sudo tar -xzf "$BACKUP_FILE" -C "$MOUNTPOINT"
    echo "Restoration of volume '$VOLUME_NAME' completed."

    # Restart the containers
    if [ -n "$CONTAINERS" ]; then
      echo "Restarting containers using volume '$VOLUME_NAME'..."
      docker start $CONTAINERS
    fi
  else
    echo "Warning: Mountpoint '$MOUNTPOINT' does not exist or is inaccessible."
  fi
done

echo "All restorations completed."
