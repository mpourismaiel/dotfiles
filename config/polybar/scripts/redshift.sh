#!/bin/sh
# https://github.com/x70b1/polybar-scripts/blob/master/polybar-scripts/info-redshift-temp/info-redshift-temp.sh

if [ "$(pgrep -x redshift)" ]; then
  temp=$(redshift -p 2> /dev/null | grep temp | cut -d ":" -f 2 | tr -dc "[:digit:]")

  if [ -z "$temp" ]; then
    echo "%{F#65737E} "
  elif [ "$temp" -ge 5000 ]; then
    echo "%{F#8FA1B3} "
  elif [ "$temp" -ge 4000 ]; then
    echo "%{F#EBCB8B} "
  else
    echo "%{F#D08770} "
  fi
fi
