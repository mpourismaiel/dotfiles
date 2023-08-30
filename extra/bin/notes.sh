#! /bin/bash
# This script is used to create a new note in the notes directory. It will
# also list all the notes which can be categorized and timestamped. The
# script will also open the note in vim if the user wants to edit it.

DEFAULT_NOTES_DIR=~/notes

CONFIG_FILE=~/.config/notes.conf
if [ ! -f $CONFIG_FILE ]; then
  touch $CONFIG_FILE
else
  if [ -z "$NOTES_DIR" ]; then
    NOTES_DIR=$(grep NOTES_DIR $CONFIG_FILE | cut -d '=' -f2)
  fi
fi

if [ -z "$NOTES_DIR" ]; then
  NOTES_DIR=$DEFAULT_NOTES_DIR
fi
NOTES_DIR=$(eval echo $NOTES_DIR)

if [ ! -d $NOTES_DIR ]; then
  mkdir -p $NOTES_DIR
  if [ $NOTES_DIR == ~/notes ]; then
    echo "Created the default notes directory at ~/notes"
  fi
fi

ACCEPTED_COMMANDS=("list ls --list --ls -l" "search s --search --s -s" "new n --new --n -n" "edit e --edit --e -e" "move mv --move --mv -m" "remove rm --remove --rm -r" "help h --help --h -h")
function help() {
  echo "Usage: notes [OPTION] [ARGUMENTS]"
  echo "Create a new note or edit an existing note."
  echo ""
  echo "Options (required) [optional]:"
  echo "  (list, --list, -l) (long,short,simple)"
  echo "    List all the notes."
  echo "  (search, --search, -s)"
  echo "    Search for a note."
  echo "  (new,  --new,  -n) (title) (category) [tags]"
  echo "    Create a new note."
  echo "  (edit, --edit, -e) (title) (category)"
  echo "    Edit an existing note."
  echo "  (move, --move, -m) (title) (from category) (to category)"
  echo "    Move an existing note."
  echo "  (remove, --remove, -r) (title) (category)"
  echo "    Remove an existing note."
  echo "  (help, --help, -h)"
  echo "    Display this help and exit."
  echo ""
  echo "Examples:"
  echo "  notes ls"
  echo "  notes ls short"
  echo "  notes new title category tag1,tag2,tag3"
  echo "  notes edit title category"
  echo "  notes remove title category"
  echo "  notes -h"
  echo ""
}

OPTION=""

if [ $# -eq 0 ]; then
  help
  exit 1
else
  for i in "${ACCEPTED_COMMANDS[@]}"; do
    for j in $i; do
      if [ "$1" == "$j" ]; then
        OPTION=${i%% *}
        break
      fi
    done
  done

  if [ -z "$OPTION" ]; then
    echo "Invalid option: $1"
    echo "Try 'notes --help' for more information."
    exit 1
  fi
fi

function is_imported() {
  local file=$1
  if [ -f $file ]; then
    if [ -s $file ]; then
      local lines_to_check=""
      while read line; do
        if [ "$line" == "---" ]; then
          if [[ $lines_to_check == *"- with notes"* ]]; then
            return 0
          fi
        else
          lines_to_check="$lines_to_check$line\n"
        fi
      done <$file
    fi
  fi

  return 1
}

function grab_details() {
  local file=$1
  if is_imported $file; then
    local lines_to_check=""
    while read line; do
      if [ "$line" == "---" ]; then
        echo $lines_to_check
      else
        lines_to_check="$lines_to_check$line\n"
      fi
    done <$file
  fi

  echo
}

function prettify_details() {
  local file=$1
  local format=$2
  local details=$(grab_details $file)
  local title=$(echo -e "$details" | head -n 1)
  if [ -z "$title" ]; then
    title=$(basename $file)
  elif [[ $title == "- category="* ]] || [[ $title == "- tags="* ]] || [[ $title == "- created_at="* ]] || [[ $title == "- updated_at="* ]]; then
    title=$(basename $file)
  fi

  local category=$(echo -e "$details" | grep -E "^- category=" | cut -d '=' -f2)
  category=$(echo $category | sed 's/\//\\\//g')

  local tags=$(echo -e "$details" | grep -E "^- tags=" | cut -d '=' -f2)
  local created_at=$(echo -e "$details" | grep -E "^- created_at=" | cut -d '=' -f2)
  local updated_at=$(echo -e "$details" | grep -E "^- updated_at=" | cut -d '=' -f2)

  tags=$(echo $tags | sed 's/, /,/')
  tags=$(echo $tags | sed 's/,/, /g')

  format=$(echo $format | sed "s/%title%/$title/")
  format=$(echo $format | sed "s/%category%/$category/")
  format=$(echo $format | sed "s/%tags%/$tags/")
  format=$(echo $format | sed "s/%created_at%/$created_at/")
  format=$(echo $format | sed "s/%updated_at%/$updated_at/")
  echo -e $format
}

function format_file() {
  if [[ $2 == "long" ]] || [[ $2 == "l" ]]; then
    prettify_details $1 "\e[1;37m%title%\e[0m\n\e[1;33m%tags%\e[0m\nCreated at: \e[0;37m%created_at%\e[0m\nUpdated at: \e[0;37m%updated_at%\e[0m"
    echo
  elif [[ $2 == "short" ]] || [[ $2 == "s" ]]; then
    prettify_details $1 "\e[1;37m%title%\e[0m - [\e[1;33m%tags%\e[0m] - Created at: \e[0;37m%created_at%\e[0m - Updated at: \e[0;37m%updated_at%\e[0m"
  elif [[ $2 == "simple" ]] || [[ $2 == "ss" ]]; then
    prettify_details $1 "%title%"
  else
    prettify_details $1 $2
  fi
}

function list() {
  local dir=$1
  local format=$2
  if [ -z $format ]; then
    format="long"
  fi
  local level=$3
  if [ -z $level ]; then
    level=0
  fi

  if [ -z "$(ls -A $dir)" ]; then
    if [[ $format != "simple" ]] && [[ $format != "ss" ]]; then
      str="No notes found."
      for ((i = 0; i < $level; i++)); do
        str="  $str"
      done
      echo -e $str
    fi
    return
  fi

  for i in $dir/*; do
    if [ -f $i ]; then
      if [ -s $i ]; then
        format_file "$i" "$format"
      fi
    elif [ -d $i ]; then
      if [[ $format != "simple" ]] && [[ $format != "ss" ]]; then
        local category=$(basename $i)
        str="\e[1;32m$category\e[0m"
        for ((j = 0; j < $level; j++)); do
          str="  $str"
        done
        echo -e $str
      fi
      list $i $format $(($level + 1))
    fi
  done
}

function search() {
  local dir=$1
  local query=$2
  local format="short"

  for i in $dir/*; do
    if [ -f $i ]; then
      if [ -s $i ]; then
        local file=$(basename $i)
        local file_name=$(echo $file | cut -d '.' -f1)
        if [[ $file_name == *$query* ]]; then
          echo "Found $file_name: $(format_file "$i" "$format")"
        fi
      fi
    elif [ -d $i ]; then
      search $i $query $format
    fi
  done
}

function new() {
  local file=$1

  if [ -z "$file" ]; then
    echo "No file specified."
    echo "Try 'notes --help' for more information."
    exit 1
  fi

  local title=$1
  if [ -z "$title" ]; then
    echo "No title specified."
    echo "Try 'notes --help' for more information."
    exit 1
  fi

  local category=$2
  if [ -z "$category" ]; then
    category="uncategorized"
  fi

  local tags=""
  for i in "${@:3}"; do
    tags="$tags, $i"
  done

  if [[ $file != *.md ]]; then
    file="$file.md"
  else
    title=$(echo $title | sed 's/\.md//')
  fi

  category=$(echo $category | sed 's/\/$//')
  file="$category/$file"

  if [ -f $NOTES_DIR/$file ]; then
    echo "File already exists. To edit the file, use 'notes -e $file'"
    echo "Try 'notes --help' for more information."
    exit 1
  else
    if [ ! -d $NOTES_DIR/$category ]; then
      mkdir -p $NOTES_DIR/$category
    fi
  fi

  if [ ! -d $NOTES_DIR ]; then
    echo "No notes directory found."
    echo "Try 'notes --help' for more information."
    exit 1
  fi

  if [ ! -f $NOTES_DIR/$file ]; then
    touch $NOTES_DIR/$file
  fi

  local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
  echo "$title" >>$NOTES_DIR/$file
  echo
  echo "- category=$category" >>$NOTES_DIR/$file
  echo "- tags=$tags" >>$NOTES_DIR/$file
  echo "- created_at=$timestamp" >>$NOTES_DIR/$file
  echo "- updated_at=$timestamp" >>$NOTES_DIR/$file
  echo "- with notes" >>$NOTES_DIR/$file
  echo
  echo "---" >>$NOTES_DIR/$file
  echo

  echo "Created a new note at $NOTES_DIR/$file"

  if [ ! -z "$EDITOR" ]; then
    $EDITOR $NOTES_DIR/$file
  else
    vim $NOTES_DIR/$file
  fi
}

function find_category() {
  local category=$1
  if [ -z "$category" ]; then
    category="uncategorized"
  fi

  if [ ! -d $NOTES_DIR/$category ]; then
    echo "Category does not exist. To create a new category, use 'notes -n $category'"
    echo "Try 'notes --help' for more information."
    exit 1
  fi

  echo $category
}

function find_file() {
  local file=$1
  local category=$(find_category $2)

  if [ -z "$file" ]; then
    echo "No file specified."
    echo "Try 'notes --help' for more information."
    exit 1
  fi

  if [[ $file != *.md ]]; then
    file="$file.md"
  fi
  file="$category/$file"

  if [ ! -f $NOTES_DIR/$file ]; then
    echo "File does not exist. To create a new file, use 'notes -n $file'"
    echo "Try 'notes --help' for more information."
    exit 1
  fi

  echo $file
}

function edit() {
  local file=$(find_file $1 $2)

  if [ ! -z "$EDITOR" ]; then
    $EDITOR $NOTES_DIR/$file
  else
    vim $NOTES_DIR/$file
  fi

  local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
  local lines_to_check=""
  while read line; do
    if [ "$line" == "---" ]; then
      lines_to_check=$(echo -e "$lines_to_check" | sed "s/- updated_at=.*/- updated_at=$timestamp/")
      sed -i '1,/^---$/d' $NOTES_DIR/$file
      if [[ $lines_to_check != *"- with notes"* ]]; then
        lines_to_check="$lines_to_check\n- with notes"
      fi
      echo -e "$lines_to_check\n---" | cat - $NOTES_DIR/$file >temp && mv temp $NOTES_DIR/$file
      break
    else
      lines_to_check="$lines_to_check$line\n"
    fi
  done <$NOTES_DIR/$file
}

function move() {
  local category=$(find_category $2)
  local file=$(find_file $1 $2)

  local category=$3
  if [ -z "$category" ]; then
    echo "No category specified."
    echo "Try 'notes --help' for more information."
    exit 1
  fi

  if [ ! -d $NOTES_DIR/$category ]; then
    mkdir -p $NOTES_DIR/$category
  fi

  mv $NOTES_DIR/$file $NOTES_DIR/$category/$1.md
  if [ -z "$(ls -A $NOTES_DIR/$category)" ]; then
    rm -rf $NOTES_DIR/$category
  fi
}

function remove() {
  local category=$(find_category $2)
  local file=$(find_file $1 $2)

  rm $NOTES_DIR/$file
  if [ -z "$(ls -A $NOTES_DIR/$category)" ]; then
    rm -rf $NOTES_DIR/$category
  fi
}

if [ "$OPTION" == "list" ]; then
  list $NOTES_DIR $2
  exit 0
elif [ "$OPTION" == "search" ]; then
  search $NOTES_DIR $2
  exit 0
elif [ "$OPTION" == "new" ]; then
  new $2 $3 $4 $5 $6 $7 $8 $9
  exit 0
elif [ "$OPTION" == "edit" ]; then
  edit $2 $3
  exit 0
elif [ "$OPTION" == "move" ]; then
  move $2 $3 $4
  exit 0
elif [ "$OPTION" == "remove" ]; then
  remove $2 $3
  exit 0
elif [ "$OPTION" == "help" ]; then
  help
  exit 0
else
  echo "Invalid option: $OPTION"
  echo "Try 'notes --help' for more information."
  exit 1
fi
