# Thanks a lot to Jess Frazelle. https://github.com/jessfraz/dotfiles/blob/master/.functions

# Create a new directory and enter it
mkd() {
  mkdir -p "$@"
  cd "$@" || exit
}

# Make a temporary directory and enter it
tmpd() {
  local dir
  if [ $# -eq 0 ]; then
    dir=$(mktemp -d)
  else
    dir=$(mktemp -d -t "${1}.XXXXXXXXXX")
  fi
  cd "$dir" || exit
}

# Create a .tar.gz archive, using `zopfli`, `pigz` or `gzip` for compression
targz() {
  local tmpFile="${1%/}.tar"
  tar -cvf "${tmpFile}" --exclude=".DS_Store" "${1}" || return 1

  size=$(
  stat -f"%z" "${tmpFile}" 2> /dev/null; # OS X `stat`
  stat -c"%s" "${tmpFile}" 2> /dev/null # GNU `stat`
  )

  local cmd=""
  if (( size < 52428800 )) && hash zopfli 2> /dev/null; then
    # the .tar file is smaller than 50 MB and Zopfli is available; use it
    cmd="zopfli"
  else
    if hash pigz 2> /dev/null; then
      cmd="pigz"
    else
      cmd="gzip"
    fi
  fi

  echo "Compressing .tar using \`${cmd}\`…"
  "${cmd}" -v "${tmpFile}" || return 1
  [ -f "${tmpFile}" ] && rm "${tmpFile}"
  echo "${tmpFile}.gz created successfully."
}

# Create a data URL from a file
dataurl() {
  local mimeType
  mimeType=$(file -b --mime-type "$1")
  if [[ $mimeType == text/* ]]; then
    mimeType="${mimeType};charset=utf-8"
  fi
  echo "data:${mimeType};base64,$(openssl base64 -in "$1" | tr -d '\n')"
}

# Compare original and gzipped file size
gz() {
  local origsize
  origsize=$(wc -c < "$1")
  local gzipsize
  gzipsize=$(gzip -c "$1" | wc -c)
  local ratio
  ratio=$(echo "$gzipsize * 100 / $origsize" | bc -l)
  printf "orig: %d bytes\\n" "$origsize"
  printf "gzip: %d bytes (%2.2f%%)\\n" "$gzipsize" "$ratio"
}

# Get colors in manual pages
man() {
  env \
    LESS_TERMCAP_mb="$(printf '\e[1;31m')" \
    LESS_TERMCAP_md="$(printf '\e[1;31m')" \
    LESS_TERMCAP_me="$(printf '\e[0m')" \
    LESS_TERMCAP_se="$(printf '\e[0m')" \
    LESS_TERMCAP_so="$(printf '\e[1;44;33m')" \
    LESS_TERMCAP_ue="$(printf '\e[0m')" \
    LESS_TERMCAP_us="$(printf '\e[1;32m')" \
    man "$@"
}

# Use feh to nicely view images
openimage() {
  local types='*.jpg *.JPG *.png *.PNG *.gif *.GIF *.jpeg *.JPEG'

  cd "$(dirname "$1")" || exit
  local file
  file=$(basename "$1")

  feh -q "$types" --auto-zoom \
    --sort filename --borderless \
    --scale-down --draw-filename \
    --image-bg black \
    --start-at "$file"
}

