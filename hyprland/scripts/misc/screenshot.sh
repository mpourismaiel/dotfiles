#! /bin/bash

if [ ! -d ~/Pictures/Screenshots ]; then
  mkdir -p ~/Pictures/Screenshots
fi

grim -g "$(slurp -o -r -c '#ff0000ff')" - | satty --filename - --fullscreen --output-filename ~/Pictures/Screenshots/satty-$(date '+%Y%m%d-%H:%M:%S').png
