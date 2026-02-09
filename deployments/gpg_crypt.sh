#!/bin/bash

# Check for correct number of arguments
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <encrypt|decrypt>"
    exit 1
fi

ACTION=$1

# Retrieve passphrase from environment variable
PASSPHRASE="${GPG_PASSPHRASE}"

if [ -z "$PASSPHRASE" ]; then
    echo "Error: Passphrase not provided. Set the GPG_PASSPHRASE environment variable."
    exit 1
fi

# Define filenames
ENCRYPTED_FILE="secrets.gpg"
DECRYPTED_FILE="secrets"

if [ "$ACTION" = "encrypt" ]; then
    # Check if the unencrypted file exists
    if [ ! -f "$DECRYPTED_FILE" ]; then
        echo "Error: File '$DECRYPTED_FILE' not found for encryption."
        exit 1
    fi

    # Encrypt the file (overwrite if exists)
    gpg --batch --yes --passphrase "$PASSPHRASE" --symmetric --cipher-algo AES256 \
        --output "$ENCRYPTED_FILE" "$DECRYPTED_FILE"

    if [ "$?" -eq 0 ]; then
        echo "File '$DECRYPTED_FILE' encrypted successfully to '$ENCRYPTED_FILE'."

        # Delete the unencrypted file
        rm -f "$DECRYPTED_FILE"
        echo "Unencrypted file '$DECRYPTED_FILE' has been deleted."
    else
        echo "Encryption failed."
        exit 1
    fi
elif [ "$ACTION" = "decrypt" ]; then
    # Check if the encrypted file exists
    if [ ! -f "$ENCRYPTED_FILE" ]; then
        echo "Error: Encrypted file '$ENCRYPTED_FILE' not found for decryption."
        exit 1
    fi

    # Decrypt the file
    gpg --batch --yes --passphrase "$PASSPHRASE" --decrypt \
        --output "$DECRYPTED_FILE" "$ENCRYPTED_FILE"

    if [ "$?" -eq 0 ]; then
        echo "File '$ENCRYPTED_FILE' decrypted successfully to '$DECRYPTED_FILE'."
    else
        echo "Decryption failed."
        exit 1
    fi
else
    echo "Invalid action. Use 'encrypt' or 'decrypt'."
    exit 1
fi