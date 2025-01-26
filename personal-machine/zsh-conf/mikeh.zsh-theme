setopt prompt_subst

autoload -U add-zsh-hook
autoload -Uz vcs_info

# check-for-changes can be really slow.
# you should disable it, if you work with large repositories
zstyle ':vcs_info:*:prompt:*' check-for-changes true

add-zsh-hook precmd mikeh_precmd

mikeh_precmd() {
    vcs_info
}

# user, host, full path, and time/date
# on two lines for easier vgrepping
# entry in a nice long thread on the Arch Linux forums: https://bbs.archlinux.org/viewtopic.php?pid=521888#p521888
PROMPT="%F{magenta}[%f%F{yellow}%T%f%F{magenta}]%f%F{white} || %f%F{10}%~%f "
PS2=$' \e[0;34m%}%B>%{\e[0m%}%b '
