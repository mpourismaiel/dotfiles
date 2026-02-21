#!/usr/bin/env zsh
# standalone script and also definable function when sourced

script_path="${(%):-%x}"
config_file="/home/mahdi/.zsh/extra_config.zsh"

if [[ ! -f "$config_file" ]]; then
  echo "extra_config not found: $config_file" >&2
  return 2 2>/dev/null || exit 2
fi

# Extract the project_dirs assignment block from the config safely.
# Use grep for the common single-line case, with a fallback that
# accumulates lines until a closing ")" for multi-line assignments.
assignment=$(grep -E 'project_dirs[[:space:]]*=' "$config_file" || true)

if [[ -z "$assignment" ]]; then
  # Fallback: accumulate lines starting at the opening paren
  in_block=0
  assignment=""
  while IFS= read -r line; do
    if [[ $in_block -eq 0 && $line == *project_dirs*'('* ]]; then
      in_block=1
    fi
    if [[ $in_block -eq 1 ]]; then
      assignment+="$line\n"
      if [[ $line == *")"* ]]; then
        break
      fi
    fi
  done < "$config_file"
fi

if [[ -z "$assignment" ]]; then
  echo "project_dirs assignment not found in $config_file" >&2
  return 3 2>/dev/null || exit 3
fi

# Evaluate the assignment into a local array (in a subshell to avoid side-effects when executed)
typeset -a project_dirs
eval "$assignment"

project_pwd() {
  local pwd dir expanded best best_len=0 len
  pwd=$(pwd)

  for dir in "${project_dirs[@]}"; do
    expanded=$(eval echo "$dir")
    expanded=${expanded%/}
    if [[ "$pwd" == "$expanded" || "$pwd" == "$expanded"/* ]]; then
      len=${#expanded}
      if (( len > best_len )); then
        best="$expanded"
        best_len=$len
      fi
    fi
  done

  if [[ -n "$best" ]]; then
    echo "${best:t}"
    return 0
  fi

  return 1
}

# If executed directly, run and print result
if [[ "${(%):-%x}" == "$0" ]]; then
  project_pwd
fi
