#!/bin/zsh
# zsh-omnibar entry point.
#
# Sources the upstream-named plugin file rather than replacing it. Every
# internal name -- the `.autocomplete__*` function files, the `~autocomplete`
# named directory, the `:autocomplete:` style namespace -- is left exactly as
# upstream has it, so merging upstream stays a fast-forward instead of a
# rename conflict in every file. The fork is renamed; its guts are not.
source "${${(%):-%x}:A:h}/zsh-autocomplete.plugin.zsh" "$@"
