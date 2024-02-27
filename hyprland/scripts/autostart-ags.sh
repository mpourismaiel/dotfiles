#!/bin/bash

# Define the config file path
CONFIG_FILE="$HOME/.config/ags/config.json"

# Get the directory where the script is located
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

# Generate the log file name with timestamp
LOG_FILE="$SCRIPT_DIR/autostart-$(date '+%Y-%m-%d %H:%M').log"

# Check if the config file exists
if [ ! -f "$CONFIG_FILE" ]; then
  echo "Config file does not exist: $CONFIG_FILE" >>"$LOG_FILE"
  exit 1
fi

# Extract 'autostart' array using jq and iterate through each item
jq -r '.autostart[]?' "$CONFIG_FILE" 2>>"$LOG_FILE" | while read -r item; do
  # Check if item is a file
  if [ -f "$item" ]; then
    # Check if the file is executable
    if [ -x "$item" ]; then
      "$item" &
    else
      echo "File is not executable: $item" >>"$LOG_FILE"
    fi
  # If not a file, assume it's a command and check if it exists in the PATH
  elif command -v "$item" >/dev/null 2>&1; then
    $item &
  else
    echo "Command or file does not exist: $item" >>"$LOG_FILE"
  fi
done
