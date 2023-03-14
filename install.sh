#!/bin/bash

mkdir ~/Documents/projects
mkdir ~/Documents/projects/dotfiles
cd ~/Documents/projects/dotfiles
git clone --recurse-submodules https://github.com/mpourismaiel/dotfiles.git awesome

pacman -Syu

sudo pacman -S --needed git base-devel
git clone https://aur.archlinux.org/yay.git
cd yay
makepkg -si

yay -S telegram-desktop windscribe-bin visual-studio-code-bin google-chrome betterdiscord-installer-bin vim steam awesome-git rofi lua-pam-git docker gamemode

sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
sudo groupadd docker
sudo usermod -aG docker $USER
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.3/install.sh | bash

curl -sS https://starship.rs/install.sh | sh

mv ~/.config/awesome ~/.config/awesome.backup
mkdir ~/.config/awesome-backup
touch ~/.config/awesome-backup/autostart
ln -s ~/Documents/projects/dotfiles/awesome $HOME/.config/awesome
sh ~/Documents/projects/dotfiles/extra/zsh/setup.sh
