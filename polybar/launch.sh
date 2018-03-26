#!/usr/bin/env sh

# Terminate already running bar instances
killall -q polybar

# Wait until the processes have been shut down
while pgrep -u $UID -x polybar >/dev/null; do sleep 1; done

# Launch bar1 and bar2
if type "xrandr"; then
  for m in $(xrandr --query | grep " connected" | cut -d" " -f1); do
    MONITOR=$m polybar --reload -c ~/.config/polybar/config main &
    # MONITOR=$m polybar --reload -c ~/.config/polybar/config time &
    # MONITOR=$m polybar --reload -c ~/.config/polybar/config i3 &
  done
else
  polybar --reload -c ~/.config/polybar/config main &
  # polybar --reload -c ~/.config/polybar/config time &
  # polybar --reload -c ~/.config/polybar/config i3 &
fi


echo "Bars launched..."
