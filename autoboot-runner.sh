#!/bin/bash
# PyRunner Autoboot Script Runner
# This script checks for an autoboot configuration and runs the specified Python script

AUTOBOOT_FILE="/home/pi/pyrunner/autoboot.txt"
CODE_DIR="/home/pi/pythoncode"
LOG_DIR="/home/pi/pyrunner/logs"

# Ensure log directory exists
mkdir -p "$LOG_DIR"

# Check if autoboot file exists and has content
if [ ! -f "$AUTOBOOT_FILE" ]; then
    echo "No autoboot configuration found"
    exit 0
fi

SCRIPT_NAME=$(cat "$AUTOBOOT_FILE" | tr -d '[:space:]')

if [ -z "$SCRIPT_NAME" ]; then
    echo "Autoboot file is empty"
    exit 0
fi

SCRIPT_PATH="$CODE_DIR/$SCRIPT_NAME"

if [ ! -f "$SCRIPT_PATH" ]; then
    echo "Autoboot script not found: $SCRIPT_PATH"
    exit 1
fi

echo "Starting autoboot script: $SCRIPT_NAME"

# Run the script with unbuffered output
cd "$CODE_DIR"
exec /usr/bin/python3 -u "$SCRIPT_PATH" 2>&1 | tee "$LOG_DIR/${SCRIPT_NAME}.log"
