#!/bin/sh
get_kbd_backlight() {
  kbd_backlight=$(cat /sys/class/leds/asus::kbd_backlight/brightness)
  if [ $kbd_backlight == '3' ]; then
    echo  100%
  elif [ $kbd_backlight == '2' ]; then
    echo  66%
  elif [ $kbd_backlight == '1' ]; then
    echo  33%
  else
    echo  0%
  fi
}

if [ -z $1 ]; then
  get_kbd_backlight
else
  kbd_backlight=$(cat /sys/class/leds/asus::kbd_backlight/brightness)
  new_backlight=$(expr $kbd_backlight + 1)
  if [ $new_backlight -gt 3 ]; then
    new_backlight=0
  fi

  dbus-send --system --type=method_call --dest="org.freedesktop.UPower" "/org/freedesktop/UPower/KbdBacklight" "org.freedesktop.UPower.KbdBacklight.SetBrightness" int32:$new_backlight
  get_kbd_backlight
fi
