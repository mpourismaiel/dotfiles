export project_dirs=($HOME/Documents/projects $HOME/Documents/projects/private/ainur $HOME/Documents/projects/guts $HOME/Documents/projects/private $HOME/Documents/projects/godot $HOME/Documents/Unreal\ Projects $HOME/Documents/projects/honestgroup/ $HOME/Documents/projects/private/games $HOME/bin $HOME/Documents/projects/root-sustainability)
export STARSHIP_CONFIG=~/.config/starship/starship.toml
export exclude_project_dirs=(ainur)

plugins+=(zsh-autosuggestions)
eval "$(starship init zsh)"
eval "$(rbenv init - zsh)" # rbenv

if [ -e $HOME/.nix-profile/etc/profile.d/nix.sh ]; then . $HOME/.nix-profile/etc/profile.d/nix.sh; fi # added by Nix installer
[ -s "$HOME/.bun/_bun" ] && source "$HOME/.bun/_bun"                                                  # bun completions
export BUN_INSTALL="$HOME/.bun"
export GOPATH=$HOME/go
export GOROOT=/usr/lib/go
export ANDROID_HOME=$HOME/Android/Sdk
export ANDROID_SDK_ROOT=$HOME/Android/Sdk
export GOPATH=$HOME/go
export CHROME_EXECUTABLE=/usr/bin/google-chrome-stable
export GAMEMODERUNEXEC="prime-run"
export SUDO_EDITOR=vim
export EDITOR=vim
export GUI_EDITOR=code-insiders
export RENPY_EXECUTABLE_PATH="/home/mahdi/Documents/projects/private/renpy-8.5.3-sdk/renpy.sh"
export PATH="$BUN_INSTALL/bin:$HOME/.local/bin:$PATH:/opt/unreal-engine/Engine/Binaries/Linux:$HOME/bin/flutter/bin:$GOPATH:$ANDROID_SDK_ROOT/emulator:$HOME/Android/Sdk:$ANDROID_SDK_ROOT/platform-tools:/usr/local/go/bin:$HOME/bin:$GOPATH/bin:$GOROOT/bin:$HOME/.local/bin:$HOME/bin/eww/target/release:$HOME/.cargo/bin:$HOME/.config/emacs/bin"
export LIQUIBASE_HOME="/opt/liquibase/"


export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

alias guts-vpn-up="wg-quick up gvpn"
alias guts-vpn-down="wg-quick down gvpn"
alias vpn-guts-up="wg-quick up gvpn"
alias vpn-guts-down="wg-quick down gvpn"
# alias code="code-insiders"

# bun completions
[ -s "$HOME/.bun/_bun" ] && source "$HOME/.bun/_bun"

# Turso
export PATH="$HOME/.turso:$PATH"
export PNPM_HOME="/home/mahdi/.local/share/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME:"*) ;;
  *) export PATH="$PNPM_HOME:$PATH" ;;
esac

export JAVA_HOME=/usr/lib/jvm/java-17-openjdk
export ANDROID_SDK_ROOT=$HOME/Android/Sdk
export ANDROID_HOME=$ANDROID_SDK_ROOT
export PATH=$JAVA_HOME/bin:$ANDROID_SDK_ROOT/platform-tools:$PATH

pre_upgrade_tag() {
  local date_tag
  date_tag=$(date +"%Y-%m-%d")
  local tag_name="pre-upgrade-${date_tag}"

  git tag "$tag_name"
}

tmp-project() {
  local PROJECT_DIR=$HOME/Documents/projects/test-projects
  # Ensure PROJECT_DIR is defined
  if [[ -z "$PROJECT_DIR" ]]; then
    echo "Error: \$PROJECT_DIR is not set." >&2
    return 1
  fi

  # Define a list of words to choose from
  local words=(
    alpha bravo charlie delta echo foxtrot golf hotel india juliet kilo lima
    mike november oscar papa quebec romeo sierra tango uniform victor whiskey
    xray yankee zulu
  )

  # Randomly select two distinct words
  local word1=${words[$((RANDOM % ${#words[@]} + 1))]}
  local word2=${words[$((RANDOM % ${#words[@]} + 1))]}

  # Ensure they aren't identical
  while [[ $word1 == $word2 ]]; do
    word2=${words[$((RANDOM % ${#words[@]} + 1))]}
  done

  # Create the project directory
  local dir_name="${word1}-${word2}"
  local dir_path="${PROJECT_DIR}/${dir_name}"
  mkdir -p "$dir_path" || return 1

  # Enter directory and open in VS Code
  cd "$dir_path" || return 1
  code .

  # Optional: print path for confirmation
  echo "Created and opened: $dir_path"
}

autoload -U add-zsh-hook

load-nvmrc() {
  local nvmrc_path
  nvmrc_path="$(nvm_find_nvmrc)"

  if [ -n "$nvmrc_path" ]; then
    nvm use --silent
  fi
}

add-zsh-hook chpwd load-nvmrc
load-nvmrc

chpwd() {
  if [ -f ./.zsh_enter ]; then
    source ./.zsh_enter
  fi
}
