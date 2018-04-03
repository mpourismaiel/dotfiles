#!/bin/sh

CURRENT_DIR="$(pwd)"
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
CONFIG=$HOME/.config

cd $DIR
mkdir -p $CONFIG/{conky,i3,polybar,rofi}

# Copy conky config
echo "Copying conky config"
ln conky/{shortcuts,start_conky_maia,usage} $CONFIG/conky

# Copy i3 config
echo "Copying i3 config"
if [ -f $CONFIG/i3/config ]; then
  cp $CONFIG/i3/config $CONFIG/i3/config-backup
fi
ln i3/config $CONFIG/i3/config

# Copy polybar config
echo "Copying polybar config"
if [ -f $CONFIG/polybar/config ]; then
  cp $CONFIG/polybar/config $CONFIG/polybar/config-backup
fi
if [ -f $CONFIG/polybar/launch.sh ]; then
  cp $CONFIG/polybar/launch.sh $CONFIG/polybar/launch-backup.sh
fi
ln polybar/{config,launch.sh} $CONFIG/polybar

if [ -d $CONFIG/polybar/scripts ]; then
  cp -R $CONFIG/polybar/scripts $CONFIG/polybar/scripts-backup
fi
ln -s polybar/scripts $CONFIG/polybar/scripts

# Copy rofi config
echo "Copying rofi config"
if [ -f $CONFIG/rofi/config ]; then
  cp $CONFIG/rofi/config $CONFIG/rofi/config-backup
fi
ln rofi/config $CONFIG/rofi/config

# Copy redshift config
echo "Copying redshift config"
if [ -f $CONFIG/redshift.conf ]; then
  cp $CONFIG/redshift.conf $CONFIG/redshift-backup.conf
fi
ln redshift.conf $CONFIG/redshift.conf

# Copy compton config
echo "Copying compton config"
if [ -f $CONFIG/compton.conf ]; then
  cp $CONFIG/compton.conf $CONFIG/compton-backup.conf
fi
ln compton.conf $CONFIG/compton.conf

# Copy x config
echo "Copying x config"
if [ -f $HOME/.xinitrc ]; then
  cp $HOME/.xinitrc $HOME/xinitrc-backup
fi
ln .xinitrc $HOME/.xinitrc

if [ -f $HOME/.Xresources ]; then
  cp $HOME/.Xresources $HOME/Xresources-backup
fi
ln .Xresources $HOME/.Xresources

# Copy zsh config
echo "Copying zshrc config"
if [ -f $HOME/.zshrc ]; then
  cp $HOME/.zshrc $HOME/zshrc-backup
fi
ln .zshrc $HOME/.zshrc

echo "Done"
echo "Please install fonts Feather icons as icomoon and Fira code yourself. (Simply copy ttf/otf files to $HOME/.local/share/fonts)"
cd $CURRENT_DIR
