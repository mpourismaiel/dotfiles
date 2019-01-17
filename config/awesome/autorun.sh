#!/usr/bin/env bash

setxkbmap -layout us,ir -option grp:alt_shift_toggle
xrdb -merge $HOME/.Xresources
nm-applet&

sh $HOME/.screenlayout/single-screen-full-hd.sh&
sh $HOME/bin/desktop-environment.sh&

sh $HOME/bin/ping.sh&
watch -n30 $HOME/bin/battery&

currenttime=$(date +%H:%M)
if [[ "$currenttime" > "19:00" ]] || [[ "$currenttime" < "06:30" ]]; then
  xbacklight -set 70%
else
  xbacklight -set 100%
fi

function run {
  if pgrep -x "gedit" > /dev/null; then
    $@&
  fi
}

run xautolock -time 10 -locker "sh $HOME/.config/i3/i3lock $HOME/Pictures/Lockscreen/wallpaper.jpg"
run xss-lock -- sh $HOME/.config/i3/i3lock $HOME/Pictures/Lockscreen/wallpaper.jpg
run xxkb
run visual-studio-code
run google-chrome-beta
run terminator
run telegram-desktop
