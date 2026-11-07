#
# ~/.bashrc
#

# If not running interactively, don't do anything
[[ $- != *i* ]] && return

alias ls='ls --color=auto'
alias grep='grep --color=auto'
PS1='[\u@\h \W]\$ '

# Приветствие NorkaOS в каждом новом окне терминала
command -v norka-hello >/dev/null && norka-hello
