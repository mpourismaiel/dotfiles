#! /bin/bash

MY_PATH="$(dirname -- "${BASH_SOURCE[0]}")" # relative
MY_PATH="$(cd -- "$MY_PATH" && pwd)"        # absolutized and normalized
if [[ -z "$MY_PATH" ]]; then
  # error; for some reason, the path is not accessible
  # to the script (e.g. permissions re-evaled after suid)
  exit 1 # fail
fi

if [ -f "$HOME/.zshrc" ]; then
  mv "$HOME/.zshrc" "$HOME/.zshrc.backup"
  rm "$HOME/.zshrc"
fi

if [ -d "$HOME/.zsh" ]; then
  mv "$HOME/.zsh" "$HOME/.zsh.backup"
  rm -rf "$HOME/.zsh"
else
  mkdir "$HOME/.zsh"
fi

ln "$MY_PATH/zshrc" "$HOME/.zshrc"
ln "$MY_PATH/aliases.zsh" "$HOME/.zsh/aliases.zsh"
