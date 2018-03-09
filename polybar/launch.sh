#!/usr/bin/env sh

# Terminate already running bar instances
killall -q polybar

# Wait until the processes have been shut down
while pgrep -u $UID -x polybar >/dev/null; do sleep 1; done

# Launch bar1 and bar2
if type "xrandr"; then
  for m in $(xrandr --query | grep " connected" | cut -d" " -f1); do
    MONITOR=$m polybar --reload -c /home/mahdi/.config/polybar/config main &
  done
else
  polybar --reload -c /home/mahdi/.config/polybar/config main &
fi


echo "Bars launched..."
