export GDK_SCALE=1

export GOPATH=$HOME/Documents/projects/go-projects
export GOBIN=$GOPATH/bin
export ZSH=/home/mahdi/.oh-my-zsh

export BIN_PATH=/usr/local/bin
export BIN_FOLDER=$HOME/.bin
export GO_BIN=/usr/local/go/bin
export PATH=$BIN_PATH:$BIN_FOLDER:$GO_BIN:$GOBIN:$PATH

ZSH_THEME="avit"
ENABLE_CORRECTION="true"
COMPLETION_WAITING_DOTS="true"

# Which plugins would you like to load? (plugins can be found in ~/.oh-my-zsh/plugins/*)
# Custom plugins may be added to ~/.oh-my-zsh/custom/plugins/
plugins=(git)

source $ZSH/oh-my-zsh.sh

export VISUAL='vim'
export EDITOR='vim'

# ssh
export SSH_KEY_PATH="~/.ssh/rsa_id"

export EDITOR="$VISUAL"
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

source $BIN_FOLDER/git-extras//etc/git-extras-completion.zsh

. /etc/bash.command-not-found
. $BIN_FOLDER/z/z.sh
. $BIN_FOLDER/colored-man-pages.plugin.zsh

alias res="source ~/.zshrc"
alias run_miare="API_HOST=staging.ws.miare.ir DJANGO_HOST=staging.miare.ir WEBSOCKET_HOST=staging.ws.miare.ir API_SAFE=true HOST=0.0.0.0 yarn start"
alias setIconPack="gsettings set org.gnome.desktop.interface icon-theme"
alias mng="python ./manage.py"
