#!/usr/bin/zsh

export DISPLAY=:0
export XAUTHORITY="$HOME/.Xauthority"

sleep 0.5
IS_HDMI_CONNECTED=$(xrandr --query | grep -E "HDMI.*\sconnected" | wc -l)
echo "HOW MANY CONNECTED?"
echo $IS_HDMI_CONNECTED
if [ $IS_HDMI_CONNECTED -eq 1 ]; then
  echo "Initiating second screen"
  sh "$HOME/.screenlayout/single-screen-second-full-hd.sh"
  sed -i 's/size: 9.5/size: 11.5/g' $HOME/.config/alacritty/alacritty.yml
else
  echo "Initiating builtin screen"
  sh "$HOME/.screenlayout/single-screen-full-hd.sh"
  sed -i 's/size: 11.5/size: 9.5/g' $HOME/.config/alacritty/alacritty.yml
fi

sleep 0.5
#echo "awesome.restart()" | /usr/bin/awesome-client
