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

compdef _cdp_autocomplete cdp
