#!/bin/bash

# update system and install yay
pacman -Syu
sudo pacman -S --needed git base-devel
git clone https://aur.archlinux.org/yay.git
cd yay
makepkg -si

# install packages
yay -S zsh bat neovim fzf rbenv ruby-build telegram-desktop windscribe-bin visual-studio-code-bin google-chrome betterdiscord-installer-bin vim steam awesome-git rofi lua-pam-git docker gamemode

# create projects directory and clone dotfiles
mkdir ~/Documents/projects
cd ~/Documents/projects
git clone --recurse-submodules https://github.com/mpourismaiel/dotfiles.git

# prepare docker
sudo groupadd docker
sudo usermod -aG docker $USER
sudo systemctl enable docker.service

# isntall nvm
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.3/install.sh | bash

# install oh-my-zsh and starship
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
curl -sS https://starship.rs/install.sh | sh

# backup awesome config if exists
if [[ -d ~/.config/awesome ]]; then
  mv ~/.config/awesome ~/.config/awesome.backup
fi

# create awesome config directory and link dotfiles
mkdir ~/.config/awesome-config
touch ~/.config/awesome-config/autostart
ln -s ~/Documents/projects/dotfiles/awesome $HOME/.config/awesome
sh ~/Documents/projects/dotfiles/extra/zsh/setup.sh
