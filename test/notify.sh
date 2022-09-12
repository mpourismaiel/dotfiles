#! /bin/bash

for i in {1..10}; do
  if [ $i -eq 1 ] || [ $i -eq 3 ] || [ $i -eq 7 ]; then
    notify-send "No Image #$i!!" "This is notification #$i.
This is a long notification.
Multiple lines!"
  else
    notify-send -i "/usr/share/icons/hicolor/48x48/apps/google-chrome.png" "Notification #$i!!" "This is notification #$i.
This is a long notification.
Multiple lines!"
  fi
done
