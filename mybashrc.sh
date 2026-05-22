# shellinit:contexts=interactive,login
export PROMPT_COMMAND='history -a'

if [ -f "${XDG_CONFIG_DIR:-$HOME/.config}/opencode/bash_env.sh" ]; then
  source "${XDG_CONFIG_DIR:-$HOME/.config}/opencode/bash_env.sh"
fi

shopt -s globstar

# don't put duplicate lines or lines starting with space in the history.
# See bash(1) for more options
HISTCONTROL=ignoreboth

# append to the history file, don't overwrite it
shopt -s histappend

# for setting history length see HISTSIZE and HISTFILESIZE in bash(1)
HISTSIZE=1000
HISTFILESIZE=20000

# check the window size after each command and, if necessary,
# update the values of LINES and COLUMNS.
shopt -s checkwinsize

# make less more friendly for non-text input files, see lesspipe(1)
[ -x /usr/bin/lesspipe ] && eval "$(SHELL=/bin/sh lesspipe)"

# some more ls aliases
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'

# Add an "alert" alias for long running commands.  Use like so:
#   sleep 10; alert
alias alert='notify-send --urgency=low -i "$([ $? = 0 ] && echo terminal || echo error)" "$(history|tail -n1|sed -e '\''s/^\s*[0-9]\+\s*//;s/[;&|]\s*alert$//'\'')"'

alias make="make -j 8"
alias memhog='ps -eo user,pid,cmd,%mem,rss --sort=-rss | awk '\''NR==1{print $0; next} {printf "%-15s %-10s %-30s %5s %10s\n", $1, $2, $3, $4, $5/1024 " MB"}'\'' | head -n 11'
alias av='source .venv/bin/activate || source venv/bin/activate'
alias e='$EDITOR'

# enable color support of ls and also add handy aliases
if [ -x /usr/bin/dircolors ]; then
  test -r ~/.dircolors && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"
  alias ls='ls --color=auto'
  #alias dir='dir --color=auto'
  #alias vdir='vdir --color=auto'

  alias grep='grep --color=auto'
  alias fgrep='fgrep --color=auto'
  alias egrep='egrep --color=auto'
fi

mkcd() {
  mkdir -p "$1" && cd "$1" || return 1
}

codecs() {
  ffmpeg -encoders 2>&1 | grep -E "(h264|h265|vp8|vp9|av1|hevc)"
}

clonecd() {
  local repo_url repo_dir
  if (($# > 1)); then
    git clone "$1" "$2" && cd "$2" || return 1
  elif (($# == 1)); then
    repo_url="$1"
    if [[ "$repo_url" =~ \.git$ ]]; then
      repo_dir=$(basename "$repo_url" .git)
    else
      repo_dir=$(basename "$repo_url")
    fi
    git clone "$repo_url" && cd "$repo_dir" || return 1
  else
    printf 'Usage: clonecd <url> [directory]\n' >&2
    return 1
  fi
}

# MPV with multiple videos
mpv-multi() {
    if [ $# -lt 1 ] || [ $# -gt 4 ]; then
    echo "Usage: mpv-multi video1 [video2] [video3] [video4]"
        echo "Compares 1 - 4 videos side by side"
        return 1
    fi

    local filter=""
    local cmd="mpv --pause"

    case $# in
        1)
            cmd="$cmd '$1'"
            ;;
        2)
            filter="[vid1][vid2]hstack[vo]"
            cmd="$cmd --lavfi-complex='$filter' '$1' --external-file='$2'"
            ;;
        3)
            filter="[vid3]split[v3][v3tmp];[v3tmp]drawbox=c=black:t=fill[black];[vid1][vid2]hstack[top];[v3][black]hstack[bottom];[top][bottom]vstack[vo]"
            cmd="$cmd --lavfi-complex='$filter' '$1' --external-file='$2' --external-file='$3'"
            ;;
        4)
            filter="[vid1][vid2]hstack[top];[vid3][vid4]hstack[bottom];[top][bottom]vstack[vo]"
            cmd="$cmd --lavfi-complex='$filter' '$1' --external-file='$2' --external-file='$3' --external-file='$4'"
            ;;
        esac

    eval $cmd
}

# ---------------------------------------------------------------------------
# shellinit handles sourcing api-curl, jira, confluence, cci in dependency order.
# This eval is only needed when mybashrc.sh is sourced directly (not via shellinit).
if [[ -z "${_SHELLINIT_LOADED:-}" ]] && command -v shellinit > /dev/null 2>&1; then
  eval "$(shellinit interactive login)"
fi
