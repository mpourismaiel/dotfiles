# Dot files

Since a week before this commit I've been enjoying i3 and I don't think I'm ever going back to gnome or KDE. As that's the case, I need to preserve the my config!

## Requirements
- i3, of course!
- i3-gaps
- compton
- betterlockscreen
- i3lock-color
- polybar
- rofi
- feh
- redshift
- jq

**FONT**: Go to [icomoon](https://icomoon.io/app/) and generate a font containing all Feather icons just to be safe. It's free as well as the other dependencies. You can use Icomoon to generate fonts containing any icons you want and use their glyphs any where you like.

### Commands to run
After installing the above requirements (in arch, most of them are found in AUR) run the following commands in a terminal

```
cp ~/.config/i3/config ~/.config/i3/config.backup
ln i3/config ~/.config
mkdir -p ~/.config/polybar/scripts
ln polybar/{config,launch.sh} ~/.config/polybar/
ln polybar/scripts/{inbox-github,inbox-reddit,redshift}.sh ~/.config/polybar/scripts
mkdir ~/.config/rofi
ln rofi/config ~/.config/rofi/
mkdir ~/.config/conky
ln conky/{shortcuts,start_conky_maia,usage} ~/.config/conky
cp .Xresources ~/.Xresources.backup
ln .Xresources ~/.Xresources
ln compton.conf ~/.config/compton.conf
ln redshift.conf ~/.config/redshift.conf
```
