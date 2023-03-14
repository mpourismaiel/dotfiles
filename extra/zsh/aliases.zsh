alias cat="bat"
alias vim="nvim"
alias dl="aria2c -x 16 -c"
alias projects="cd ~/Documents/projects"

run_cdp_command() {
  if [[ ! -z "$1" ]]; then
    if [[ "$1" = "code" ]]; then
      code .
    elif [[ -f "./Makefile" ]]; then
      make $1
    elif [[ -f "./package.json" ]]; then
      if [[ -f "./yarn.lock" ]]; then
        yarn $1
      else
        npm run $1
      fi
    elif [[ -d "./__ignore__" ]]; then
      if [[ -f "./__ignore__/commands.sh" ]]; then
        sh ./__ignore__/commands.sh $1
      fi
    fi
  fi
}

cdp() {
  cd ~/Documents/projects
  if [[ ! -z "$1" ]]; then
    if [[ -d "./$1" ]]; then
      cd "./$1"
    elif [[ -d "./private/$1" ]]; then
      cd "./private/$1"
    elif [[ -d "./guts/$1" ]]; then
      cd "./guts/$1"
    fi

    run_cdp_command $2
  fi
}

ainur() {
  cdp ainur
  if [[ "$1" = "ossrs" ]]; then
    cd ./ossrs
  else
    cd "./gettv-$1"

    run_cdp_command $2
  fi
}
