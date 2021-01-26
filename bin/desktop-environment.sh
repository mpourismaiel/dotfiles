#!/usr/bin/zsh

export DISPLAY=:0
export XAUTHORITY="$HOME/.Xauthority"

sleep 0.5
sh "$HOME/.screenlayout/single-screen-full-hd.sh"
sed -i 's/size: 11.5/size: 9.5/g' $HOME/.config/alacritty/alacritty.yml

#echo "awesome.restart()" | /usr/bin/awesome-client
