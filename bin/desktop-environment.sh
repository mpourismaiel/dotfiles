#!/bin/bash
sleep 0.5
MONITOR_COUNT=$(xrandr --query | grep " connected" | cut -d" " -f1 | wc -l)

if [ $MONITOR_COUNT -eq 1 ]
then
  sh $HOME/.screenlayout/single-screen-full-hd.sh
else
  sh $HOME/.screenlayout/single-screen-second-full-hd.sh
fi

sleep 0.5
i3-msg "restart"
