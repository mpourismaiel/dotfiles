#!/bin/sh

# Generate timestamp and create log file name
timestamp=$(date +"%Y-%m-%d-%H-%M-%S")
log_file=~/.config/awesome/logs/log-${timestamp}.log
touch $log_file

# Redirect stdout and stderr to the log file
exec /usr/bin/awesome >>"$log_file" 2>>"$log_file"
