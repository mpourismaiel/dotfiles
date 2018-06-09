#!/bin/sh

state=$(upower -i /org/freedesktop/UPower/devices/battery_BAT0 2> /dev/null | grep "state" | sed s/"state:"// | sed s/" "//g)
percentage=$(upower -i /org/freedesktop/UPower/devices/battery_BAT0 2> /dev/null | grep "percentage" | sed s/"percentage:"// | sed s/" "//g)
time_to_full=$(upower -i /org/freedesktop/UPower/devices/battery_BAT0 2> /dev/null | grep "time to full" | sed s/"time to full:"// | sed s/" "//g)
time_to_empty=$(upower -i /org/freedesktop/UPower/devices/battery_BAT0 2> /dev/null | grep "time to empty" | sed s/"time to empty:"// | sed s/" "//g)

if [ "$1" = "notify" ]
then
  if [ "$state" = "discharging" ]
  then
    notify-send "Battery" "$percentage Discharging\n$time_to_empty"
  else
    notify-send "Battery" "$percentage Charging\n$time_to_full"
  fi
else
  if [ "$state" = "discharging" ]
  then
    echo  $percentage
  else
    echo  $percentage
  fi
fi
