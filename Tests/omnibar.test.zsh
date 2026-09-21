#!/bin/zsh -f
# Covers the two parts of the omnibar that are easy to break silently and
# expensive to notice: how the collector parses real `compadd` calls, and how
# the ranker orders candidates from two different sources.
#
# This runs as a plain zsh script rather than a clitest transcript because it
# calls the pieces directly with prepared inputs and asserts on the resulting
# arrays, rather than replaying a fixed sequence of typed commands.

cd -- ${0:A:h:h}

zmodload -F zsh/zutil b:zparseopts
setopt extendedglob

typeset -gi failures=0
fail() {
  print -u2 -- "FAIL: $1"
  (( failures++ ))
}

# Load the pieces the way the plugin does: file contents become the body.
functions[.autocomplete__omnibar-collect]="$( < Functions/Util/.autocomplete__omnibar-collect )"
functions[.autocomplete__omnibar-rank]="$( < Functions/Util/.autocomplete__omnibar-rank )"

typeset -ga _omnibar_match=() _omnibar_disp=() _omnibar_optset=() _omnibar_src=()
typeset -ga _omnibar_order=()
typeset -gi _omnibar_noptsets=0

reset-pool() {
  _omnibar_match=() _omnibar_disp=() _omnibar_optset=() _omnibar_src=()
  _omnibar_order=()
  _omnibar_noptsets=0
}

joined() { print -r -- "${(j:,:)@}" }

# --- collector: option parsing --------------------------------------------

reset-pool
.autocomplete__omnibar-collect -J tag -- alpha beta
[[ $(joined $_omnibar_match) == 'alpha,beta' ]] ||
    fail "plain matches after --: got $(joined $_omnibar_match)"

# `-a` means the words are array names, and they are usually locals in the
# calling function, so the collector has to read them immediately.
reset-pool
() {
  local -a local_arr=( one two three )
  .autocomplete__omnibar-collect -J tag -a local_arr
}
[[ $(joined $_omnibar_match) == 'one,two,three' ]] ||
    fail "-a must dereference a *local* array at collect time: got $(joined $_omnibar_match)"

# Display strings come from a separate array, parallel to the matches.
reset-pool
() {
  local -a d=( D1 D2 )
  .autocomplete__omnibar-collect -d d -J tag -- m1 m2
}
[[ $(joined $_omnibar_match) == 'm1,m2' && $(joined $_omnibar_disp) == 'D1,D2' ]] ||
    fail "-d display array: got match=$(joined $_omnibar_match) disp=$(joined $_omnibar_disp)"

# Bundled short options where the bundle ends in one that takes an argument.
# `-ld` is `-l` plus a `-d` whose argument is the next word; reading the bundle
# character by character spills option words into the match list.
reset-pool
() {
  local -a m=( hist1 hist2 ) d=( HD1 HD2 )
  .autocomplete__omnibar-collect -S '' -QU -ld d -J history-lines -a m
}
[[ $(joined $_omnibar_match) == 'hist1,hist2' && $(joined $_omnibar_disp) == 'HD1,HD2' ]] ||
    fail "bundled -QU -ld: got match=$(joined $_omnibar_match) disp=$(joined $_omnibar_disp)"

# Per-call options that affect insertion must survive to emission; grouping and
# heading options must not, because the omnibar is a single flat group.
reset-pool
.autocomplete__omnibar-collect -S ';' -q -J tag -X 'a heading' x1 x2
[[ $(joined ${(@P)${:-_omnibar_opts_$_omnibar_noptsets}}) == '-S,;,-q' ]] ||
    fail "option set should keep -S/-q and drop -J/-X: got $(joined ${(@P)${:-_omnibar_opts_$_omnibar_noptsets}})"

# `-O`/`-A`/`-D` fill a caller-supplied array instead of adding matches;
# `_describe` uses them to decide what applies before making its real call, so
# they must pass straight through and collect nothing.
reset-pool
integer passed=0
builtin() { (( passed++ )) }
() {
  local -a out=()
  .autocomplete__omnibar-collect -O out -- m1 m2
}
unfunction builtin
(( passed == 1 && $#_omnibar_match == 0 )) ||
    fail "-O must pass through uncollected: passed=$passed collected=$#_omnibar_match"

# --- ranker: cross-source ordering ----------------------------------------

typeset -g PREFIX='c' SUFFIX=''
typeset -ga words=( git c )
typeset -gi CURRENT=2

reset-pool
# History arrives newest-first; completions arrive in the completion system's
# own order, which is roughly alphabetical and says nothing about quality.
_omnibar_match=( 'git checkout -b recent' 'git commit -m older'  'add'  'checkout' )
_omnibar_disp=(  'git checkout -b recent' 'git commit -m older'  'add'  'checkout' )
_omnibar_src=(   h                        h                      c      c )
_omnibar_optset=( 1 1 2 2 )
_omnibar_noptsets=2

.autocomplete__omnibar-rank

# `checkout` matches the typed word at position 0; `add` has no `c` at all, so
# it must not outrank it just for being collected first.
local -a ranked=()
local i
for i in $_omnibar_order; do ranked+=( $_omnibar_match[i] ); done

[[ $ranked[1] == 'git checkout -b recent' ]] ||
    fail "most recent matching history should rank first: got '$ranked[1]'"

local -i pos_checkout=${ranked[(i)checkout]} pos_add=${ranked[(i)add]}
(( pos_checkout < pos_add )) ||
    fail "a position-0 completion must outrank a non-matching one (checkout=$pos_checkout add=$pos_add)"

# Both sources must actually appear; ranking one of them off the list entirely
# is the failure mode that makes this feature pointless.
local -i n_h=0 n_c=0
for i in $_omnibar_order; do
  [[ $_omnibar_src[i] == h ]] && (( n_h++ )) || (( n_c++ ))
done
(( n_h > 0 && n_c > 0 )) ||
    fail "ranked list must blend both sources (history=$n_h completion=$n_c)"

# --- ranker: de-duplication -----------------------------------------------

# Emission passes -U, which disables compadd's own duplicate rejection, and the
# completion system does offer the same match under more than one tag.
reset-pool
_omnibar_match=( 'commit' 'commit' 'commit-tree' )
_omnibar_disp=(  'commit' 'commit  (again)' 'commit-tree' )
_omnibar_src=(   c c c )
_omnibar_optset=( 1 1 1 )
_omnibar_noptsets=1

.autocomplete__omnibar-rank

(( $#_omnibar_order == 2 )) ||
    fail "duplicate match strings should collapse to one entry: got $#_omnibar_order"

if (( failures )); then
  print -u2 -- "$failures failure(s)"
  exit 1
fi
print ok
