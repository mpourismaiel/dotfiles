#!/usr/bin/env bash

CREATE_PROJECTS=false
INSTALL_PACKAGES=false
while test $# -gt 0; do
  case "$1" in
  --create-projects)
    CREATE_PROJECTS=true
    ;;
  --install-packages)
    INSTALL_PACKAGES=true
    ;;
  --*)
    echo "bad option $1"
    ;;
  *)
    echo "argument $1"
    ;;
  esac
  shift
done

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)

if [[ $CREATE_PROJECTS = "true" ]]; then
  mkdir ~/Documents/projects
  mkdir ~/Documents/projects/dotfiles
  cd ~/Documents/projects/dotfiles
  git clone --recurse-submodules git@github.com:mpourismaiel/dotfiles.git awesome
fi

pacman -Syu

if [[ $INSTALL_PACKAGES = "true" ]]; then
  pacman -S --needed git base-devel
  git clone https://aur.archlinux.org/yay.git
  cd yay
  makepkg -si

  yay -S telegram-desktop windscribe-bin visual-studio-code-bin google-chrome betterdiscord-installer-bin vim steam awesome-git rofi lua-pam-git docker gamemode

  sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
  sudo groupadd docker
  sudo usermod -aG docker $USER
  curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.3/install.sh | bash
fi

curl -sS https://starship.rs/install.sh | sh

mv ~/.config/awesome ~/.config/awesome.backup
mkdir ~/.config/awesome-backup
touch ~/.config/awesome-backup/autostart
ln -s $SCRIPT_DIR/awesome $HOME/.config/awesome
sh $SCRIPT_DIR/extra/zsh/setup.sh
