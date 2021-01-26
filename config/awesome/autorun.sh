#!/usr/bin/env bash

function run() {
  if [ ! -f /tmp/started ]; then
    $@ &
  fi
}

setxkbmap -layout us,ir -option grp:alt_shift_toggle
xrdb -merge $HOME/.Xresources

#run sh $HOME/.screenlayout/single-screen-full-hd.sh
#run sh $HOME/bin/desktop-environment.sh

#run xautolock -time 10 -locker "sh $HOME/.config/i3/i3lock $HOME/Pictures/Lockscreen/wallpaper.jpg"
run xss-lock -- sh $HOME/.config/i3/i3lock $HOME/Pictures/Lockscreen/wallpaper.jpg
run xxkb
run google-chrome-beta
run alacritty
run telegram-desktop
run nm-applet
run mpd
# run picom -b --config $HOME/.config/picom.conf --experimental-backend
run show-ping.sh
run polychromatic-tray-applet
run node $HOME/Documents/Projects/network-manager/index.js

touch /tmp/started
