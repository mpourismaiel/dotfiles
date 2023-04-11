#! /bin/bash

MY_PATH="$(dirname -- "${BASH_SOURCE[0]}")" # relative
MY_PATH="$(cd -- "$MY_PATH" && pwd)"        # absolutized and normalized
if [[ -z "$MY_PATH" ]]; then
  # error; for some reason, the path is not accessible
  # to the script (e.g. permissions re-evaled after suid)
  exit 1 # fail
fi

if [[ ! -d "$HOME/.zsh" ]]; then
  mkdir "$HOME/.zsh"
fi
if [[ ! -d "$HOME/.zsh/backup" ]]; then
  mkdir "$HOME/.zsh/backup"
fi

if [[ -f "$HOME/.zsh/aliases.zsh" ]]; then
  mv "$HOME/.zsh/aliases.zsh" "$HOME/.zsh/backup/aliases.zsh-$(date +%Y-%m-%d-%H-%M-%S).bak"
fi
if [[ -f "$HOME/.zsh/extra_config.zsh" ]]; then
  mv "$HOME/.zsh/extra_config.zsh" "$HOME/.zsh/backup/extra_config.zsh-$(date +%Y-%m-%d-%H-%M-%S).bak"
fi
if [[ -f "$HOME/.zshrc" ]]; then
  mv "$HOME/.zshrc" "$HOME/.zsh/backup/zshrc-$(date +%Y-%m-%d-%H-%M-%S).bak"
fi

if [[ ! -L "$HOME/.zsh/aliases.zsh" ]]; then
  ln "$MY_PATH/aliases.zsh" "$HOME/.zsh/aliases.zsh"
fi
if [[ ! -L "$HOME/.zsh/extra_config.zsh" ]]; then
  ln "$MY_PATH/extra_config.zsh" "$HOME/.zsh/extra_config.zsh"
fi
if [[ ! -L "$HOME/.zshrc" ]]; then
  ln "$MY_PATH/zshrc" "$HOME/.zshrc"
fi
