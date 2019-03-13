#!/usr/bin/zsh

export DISPLAY=:0
export XAUTHORITY=/home/mahdi/.Xauthority

sleep 0.5
IS_HDMI_CONNECTED=$(xrandr --query | grep -E "HDMI.*\sconnected" | wc -l)
echo "HOW MANY CONNECTED?"
echo $IS_HDMI_CONNECTED
if [ $IS_HDMI_CONNECTED -eq 1 ]; then
  echo "Initiating second screen"
  /usr/bin/sh /home/mahdi/.screenlayout/single-screen-second-full-hd.sh
else
  echo "Initiating builtin screen"
  /usr/bin/sh /home/mahdi/.screenlayout/single-screen-full-hd.sh
fi

sleep 0.5
echo "awesome.restart()" | /usr/bin/awesome-client
