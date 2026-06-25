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

hex_to_rgb() {
  local hex="${1#\#}"
  echo "$((16#${hex[1,2]}));$((16#${hex[3,4]}));$((16#${hex[5,6]}))"
}

styled_segment() {
  local text="$1" bg_hex="$2" fg_hex="$3" italic="${4:-0}"
  local bg_rgb fg_rgb

  bg_rgb=$(hex_to_rgb "$bg_hex")
  fg_rgb=$(hex_to_rgb "$fg_hex")

  if (( italic )); then
    printf '\033[0;3;38;2;%s;48;2;%sm%s\033[0m' "$fg_rgb" "$bg_rgb" "$text"
  else
    printf '\033[0;38;2;%s;48;2;%sm%s\033[0m' "$fg_rgb" "$bg_rgb" "$text"
  fi
}

project_pwd() {
  local pwd dir expanded best best_len=0 len
  local rel display_path output bg_primary bg_alt fg_icon fg_text tail_path
  local i
  local -a parts
  pwd=$(pwd)

  bg_primary="#424868"
  bg_alt="#224868"
  fg_icon="#7AA2F7"
  fg_text="#A8ABC0"

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

  output+="$(styled_segment '  ' "$bg_primary" "$fg_icon" 0)"

  if [[ -n "$best" && ( "$pwd" == "$best" || "$pwd" == "$best"/* ) ]]; then
    if [[ "$pwd" == "$best" ]]; then
      rel=""
    else
      rel="${pwd#$best/}"
    fi

    output+="$(styled_segment " ${best:t} " "$bg_primary" "$fg_text" 1)"

    if [[ -z "$rel" ]]; then
      echo "$output"
      return 0
    fi

    if [[ -n "$rel" ]]; then
      IFS='/' read -rA parts <<< "$rel"

      output+="$(styled_segment " ${parts[1]} " "$bg_alt" "$fg_text" 1)"

      if (( ${#parts[@]} > 1 )); then
        tail_path="${parts[2]}"
        for (( i = 3; i <= ${#parts[@]}; i++ )); do
          tail_path+="/${parts[i]}"
        done
        output+="$(styled_segment " $tail_path " "$bg_primary" "$fg_text" 1)"
      fi

      echo "$output"
      return 0
    fi
  fi

  display_path="${pwd/#$HOME/~}"
  output+="$(styled_segment " $display_path " "$bg_primary" "$fg_text" 1)"
  echo "$output"
  return 0
}

# If executed directly, run and print result
if [[ "${(%):-%x}" == "$0" ]]; then
  project_pwd
fi
