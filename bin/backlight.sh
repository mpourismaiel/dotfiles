#!/bin/bash
# https://github.com/jessfraz/dotfiles/blob/master/bin/screen-backlight
##############################################################################
# screen-backlight
# -----------
# For when you are running leeenux on a Mac and it needs some help
#
# Usage:
# 	screen-backlight {up,down,total,off}
#
# :authors: Jess Frazelle, @jessfraz
# :date: 8 June 2015
# :version: 0.0.1
##############################################################################
set -e
set -o pipefail

# if [ $UID -ne 0 ]; then
#   echo "Please run this program as superuser"
#   exit 1
# fi

BLDIR=/sys/class/backlight/intel_backlight
if [[ ! -d $BLDIR ]]; then
  echo "Check what directory your backlight is stored in /sys/class/backlight/"
  exit 1
fi

BLFILE="$BLDIR/brightness"
BACKLIGHT=$(cat $BLFILE)
MAX=$(cat "$BLDIR/max_brightness")
INCREMENT=MAX/10
SET_VALUE=0

case $1 in

  up-toggle)
    TOTAL=$((BACKLIGHT + INCREMENT))
    if [ "$TOTAL" -gt "$MAX" ]; then
      TOTAL=100
    fi
    SET_VALUE=1
    ;;
  up)
    TOTAL=$((BACKLIGHT + INCREMENT))
    if [ "$TOTAL" -gt "$MAX" ]; then
      exit 1
    fi
    SET_VALUE=1
    ;;
  down-toggle)
    TOTAL=$((BACKLIGHT - INCREMENT))
    if [ "$TOTAL" -lt "100" ]; then
      TOTAL=$MAX
    fi
    SET_VALUE=1
    ;;
  down)
    TOTAL=$((BACKLIGHT - INCREMENT))
    if [ "$TOTAL" -lt "0" ]; then
      exit 1
    fi
    SET_VALUE=1
    ;;
  max)
    TEMP_VALUE=$BACKLIGHT
    while [ "$TEMP_VALUE" -lt "$MAX" ]; do
      TEMP_VALUE=$((TEMP_VALUE + INCREMENT))
      if [ "$TEMP_VALUE" -gt "$MAX" ]; then TEMP_VALUE=$MAX; fi
      echo "$TEMP_VALUE" > $BLFILE
      sleep 0.1
    done
    ;;
  min)
    TEMP_VALUE=$BACKLIGHT
    while [ "$TEMP_VALUE" -gt "0" ]; do
      TEMP_VALUE=$((TEMP_VALUE - INCREMENT))
      if [ "$TEMP_VALUE" -lt "0" ]; then TEMP_VALUE=0; fi
      echo "$TEMP_VALUE" > $BLFILE
      sleep 0.1
    done
    ;;
  *)
    echo " $((BACKLIGHT*100/MAX))%"
    ;;
esac

if [ "$SET_VALUE" -eq "1" ]; then
  echo "$TOTAL" > $BLFILE
  echo " $((TOTAL*100/MAX))%"
fi
