autoload -Uz compinit
compinit

alias cat="bat"
alias vim="nvim"
alias dl="aria2c -x 16 -c"

open_repo_in_browser() {
  # Check if current directory is a git repository
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    # Check if the repository has a remote origin
    if git config --get remote.origin.url >/dev/null 2>&1; then
      # Get the remote origin URL
      local remote_url="$(git config --get remote.origin.url)"

      # Convert the remote URL to the corresponding web URL
      local web_url="${remote_url%.git}"
      web_url="${web_url#git@}"
      web_url="${web_url/:/\/}"
      web_url="https://${web_url}"

      # Open the repository in the browser based on the platform
      case "$(uname)" in
      Darwin*)
        open "${web_url}"
        ;;
      Linux*)
        xdg-open "${web_url}"
        ;;
      CYGWIN* | MINGW32* | MSYS* | MINGW*)
        start "${web_url}"
        ;;
      *)
        echo "Unsupported platform."
        ;;
      esac
    else
      echo "No remote origin found for this git repository."
    fi
  else
    echo "Not inside a git repository."
  fi
}

_run_cdp_command() {
  if [[ ! -z "$1" ]]; then
    ran_command=0

    if [[ "$1" = "repo" ]]; then
      open_repo_in_browser
      ran_command=1
    fi

    if [[ "$1" = "code" ]]; then
      # if code-insiders exists, run than
      if [[ -f "/usr/bin/code-insiders" ]]; then
        code-insiders .
      else
        code .
      fi
      ran_command=1
    fi

    if [[ $ran_command -eq 0 && -f "./Makefile" ]]; then
      if [[ -z "$(make -qp | awk -F':' '/^[a-zA-Z0-9][^$#\/\t=]*:([^=]|$)/ {split($1,A,/ /); print A[1]}' | sort -u | grep "^$1$")" ]]; then
        ran_command=0
      else
        make $1
        ran_command=1
      fi
    fi

    if [[ $ran_command -eq 0 && -f "./package.json" ]]; then
      if [[ -f "./yarn.lock" ]]; then
        yarn $1
      else
        npm run $1
      fi
      ran_command=1
    elif [[ -d "./__ignore__" ]]; then
      if [[ -f "./__ignore__/commands.sh" ]]; then
        sh ./__ignore__/commands.sh $1
      fi
      ran_command=1
    fi
  fi
}

cdp() {
  if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    echo "Usage: cdp [directory_name] [command]"
    echo "Changes the current directory to the first level directory with the given name in the project directories specified in the 'project_dirs' array."
    echo "Excludes any directories specified in the 'exclude_project_dirs' array."
    return
  fi

  local found=false
  for project_dir in "${project_dirs[@]}"; do
    if [[ -d "$project_dir/$1" ]] && ! [[ " ${exclude_project_dirs[@]} " =~ " $1 " ]]; then
      cd "$project_dir/$1"
      _run_cdp_command $2
      found=true
      break
    fi
  done

  if [[ $found == false ]]; then
    echo "Error: could not find directory '$1' in any of the following directories:"
    printf ' - %s\n' "${project_dirs[@]}"
    if [[ ${#exclude_project_dirs[@]} -gt 0 ]]; then
      echo "Excluded directories:"
      printf ' - %s\n' "${exclude_project_dirs[@]}"
    fi
  fi
}

# get and return npm scripts and make targets, along with "code" for opening vscode and "./__ignore__/commands.sh" for running custom commands if the file exists in a given directory
_get_cdp_commands() {
  local current_dir=$(pwd)
  cdp $1

  local -a commands=("code" "repo")
  if [[ -f "./Makefile" ]]; then
    commands+=($(make -qp | awk -F':' '/^[a-zA-Z0-9][^$#\/\t=]*:([^=]|$)/ {split($1,A,/ /); print A[1]}' | sort -u))
  fi

  if [[ -f "./package.json" ]]; then
    commands+=($(jq -r '.scripts | keys[]' package.json))
  fi

  if [[ -d "./__ignore__" && -f "./__ignore__/commands.sh" ]]; then
    commands+=("__ignore__/commands.sh")
  fi

  cd $current_dir
  echo "${commands[@]}"
}

# autocomplete for cdp command, first argument should be directories inside ~/Documents/projects, ~/Documents/projects/private, ~/Documents/projects/guts and second argument should be make targets, npm scripts and yarn scripts and "code" for opening vscode
_cdp_autocomplete() {
  local -a commands
  local index=$CURRENT
  local cur_word="${words[index]}"
  local prev_word="${words[index - 1]}"

  if [[ $index -eq 2 ]]; then
    local project_names=()
    for project_dir in "${project_dirs[@]}"; do
      # Suppress errors from find
      project_names+=($(find "$project_dir" -mindepth 1 -maxdepth 1 -type d -not -path '*/\.*' -printf '%f\n' 2>/dev/null))
    done
    project_names=(${project_names[@]//${exclude_project_dirs[@]}/})
    commands=("${project_names[@]}")
  elif [[ $index -eq 3 ]]; then
    commands=($(_get_cdp_commands $prev_word))
  fi

  _describe -t commands 'Possible commands:' commands && return
}

compdef _cdp_autocomplete cdp

dcm() {
  local COMPOSE_FILE="docker-compose.yml"

  if [[ ! -f $COMPOSE_FILE ]]; then
    echo "Error: $COMPOSE_FILE not found in the current directory."
    return 1
  fi

  # Function to list services
  list_services() {
    docker-compose -f $COMPOSE_FILE config --services
  }

  # Function to start a service
  start_service() {
    service=$1
    docker-compose -f $COMPOSE_FILE up -d $service
  }

  start_all_services() {
    docker-compose -f $COMPOSE_FILE up
  }

  # Function to stop a service
  stop_service() {
    service=$1
    docker-compose -f $COMPOSE_FILE stop $service
  }

  # Function to remove a service's container
  remove_service() {
    service=$1
    docker-compose -f $COMPOSE_FILE rm -f $service
  }

  # Function to update (rebuild) a service
  update_service() {
    service=$1
    docker-compose -f $COMPOSE_FILE up -d --no-deps --build $service
  }

  # Main menu
  show_menu() {
    echo "Usage: dcm {start|stop|rm|ls|update} [service_name]"
    echo "Commands:"
    echo "  ls                List all services"
    echo "  start <service>   Start a specific service"
    echo "  stop <service>    Stop a specific service"
    echo "  rm <service>      Remove a specific service's container"
    echo "  update <service>  Update (rebuild) a specific service"
  }

  if [ $# -lt 1 ]; then
    show_menu
    return 1
  fi

  case $1 in
  ls)
    list_services
    ;;
  start)
    if [ -z "$2" ]; then
      start_all_services
      return 1
    fi
    start_service $2
    ;;
  stop)
    if [ -z "$2" ]; then
      echo "Please provide a service name."
      return 1
    fi
    stop_service $2
    ;;
  rm)
    if [ -z "$2" ]; then
      echo "Please provide a service name."
      return 1
    fi
    remove_service $2
    ;;
  update)
    if [ -z "$2" ]; then
      echo "Please provide a service name."
      return 1
    fi
    update_service $2
    ;;
  *)
    show_menu
    ;;
  esac
}

_dcm_completions() {
  local state
  local -a commands
  local -a services

  commands=(
    'ls:List all services'
    'start:Start a specific service'
    'stop:Stop a specific service'
    'rm:Remove a specific service container'
    'update:Update a specific service'
  )

  if [[ ! -f docker-compose.yml ]]; then
    return 1
  fi

  services=($(docker-compose -f docker-compose.yml config --services))

  _arguments \
    '1:command:->command' \
    '2:service:->service' \
    '*::arg:->args'

  case $state in
  command)
    _describe 'command' commands
    ;;
  service)
    _describe 'service' services
    ;;
  esac
}

compdef _dcm_completions dcm
