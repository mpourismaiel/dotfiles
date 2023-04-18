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
      code .
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
  # save current directory
  local current_dir=$(pwd)
  cdp $2

  local commands=("code" "repo")
  if [[ -f "./Makefile" ]]; then
    commands+=($(
      make -qp | awk -F':' '/^[a-zA-Z0-9][^$#\/\t=]*:([^=]|$)/ {split($1,A,/ /); print A[1]}' | sort -u
    ))
  fi

  if [[ -f "./package.json" ]]; then
    commands+=($(
      jq '.scripts | keys[]' package.json | sort -u | tr -d '"'
    ))
  fi

  if [[ -d "./__ignore__" ]]; then
    if [[ -f "./__ignore__/commands.sh" ]]; then
      commands+=("./__ignore__/commands.sh")
    fi
  fi

  cd $current_dir
  printf '%s\n' "${commands[@]}"
}

# autocomplete for cdp command, first argument should be directories inside ~/Documents/projects, ~/Documents/projects/private, ~/Documents/projects/guts and second argument should be make targets, npm scripts and yarn scripts and "code" for opening vscode
_cdp_autocomplete() {
  local cur prev
  COMPREPLY=()
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev="${COMP_WORDS[COMP_CWORD - 1]}"

  if [[ $COMP_CWORD -eq 1 ]]; then
    local project_names=()
    for project_dir in "${project_dirs[@]}"; do
      # List first-level directories in each project directory
      project_names+=($(find "$project_dir" -mindepth 1 -maxdepth 1 -type d -not -path '*/\.*' -printf '%f\n' | sort -u))
    done
    project_names=($(printf "%s\n" "${project_names[@]}" | grep -v "$(echo "$exclude_project_dirs" | tr ' ' '\n')"))
    COMPREPLY=($(compgen -W "$(printf '%s\n' "${project_names[@]}")" -- ${cur}))
  elif [[ $COMP_CWORD -eq 2 ]]; then
    COMPREPLY=($(compgen -W "$(_get_cdp_commands cdp $prev)" -- ${cur}))
  fi
}

complete -F _cdp_autocomplete cdp
