#!/bin/sh

xrdb -merge ~/.Xresources

active_monitors=$(xrandr --query | grep -w "connected primary" | cut -d" " -f1)

# Count the number of active monitors
number_of_active_monitors=$(echo "$active_monitors" | grep -c .)

# Check if only one monitor is active and its name is HDMI-1-0
if [[ $number_of_active_monitors -eq 1 && $active_monitors == "HDMI-1-0" ]]; then
	# If the condition is true, set DPI to 96
	xfconf-query -c xsettings -p /Xft/DPI -s 96
else
	# If the condition is false, set DPI to 128
	xfconf-query -c xsettings -p /Xft/DPI -s 128
fi

openbox-session
