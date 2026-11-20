#!/bin/zsh
# Installer for `work`: one tmux session per Linear issue, with persistent Claude Code chats.
# Asks for your settings (with editable defaults), installs what's missing, and links `work`
# into ~/.local/bin. Safe to rerun: it shows your current settings as the defaults.
set -e
setopt extended_glob

HERE=${0:A:h}
CONF_DIR=${XDG_CONFIG_HOME:-$HOME/.config}/work
CONF=$CONF_DIR/config
BIN=$HOME/.local/bin
CLAUDE_MD=$HOME/.claude/CLAUDE.md
TMUX_CONF=$HOME/.tmux.conf

bindkey -e
title() { print -P "\n%B%F{cyan}$1%f%b" }
hint()  { print -P "%F{8}$1%f" }
ok()    { print -P "%F{green}✓%f $1" }
warn()  { print -P "%F{yellow}!%f $1" }
fail()  { print -P "%F{red}✗%f $1" >&2; exit 1 }
tilde() { print -r -- "${1/#$HOME/~}" }
# ask VAR: edit the value of VAR in place (arrows work, Enter accepts)
ask()   { vared -p "%F{cyan}❯%f " -c "$1" }
# confirm Q [Y|N]: yes/no question with a default
confirm() {
  local a; read "a?$1 [$([[ ${2:-Y} == Y ]] && echo Y/n || echo y/N)] "
  [[ -z $a ]] && a=${2:-Y}
  [[ $a == [Yy]* ]]
}

print -P "%BInstalling work%b  $(hint "(Ctrl-C to stop at any point; nothing is changed until the end)")"

# ---- Requirements ----------------------------------------------------------
title "Checking requirements"
[[ $(uname) == Darwin ]] || warn "work is made for macOS; other systems may need changes"
for c in git claude; do
  (( $+commands[$c] )) || fail "$c is not installed. Install it, then rerun this script."
done
missing=()
for c in tmux fzf jq gh; do (( $+commands[$c] )) || missing+=$c; done
if (( $#missing )); then
  warn "Missing: ${(j:, :)missing}  $(hint "(gh is optional: it lets 'work done' recognise merged PRs)")"
  if (( $+commands[brew] )) && confirm "Install them with Homebrew now?"; then
    brew install $missing
  else
    for c in tmux fzf jq; do (( $+commands[$c] )) || fail "$c is required. Install it, then rerun this script."; done
  fi
fi
ok "git, claude, tmux, fzf, jq"

# ---- Settings --------------------------------------------------------------
[[ -f $CONF ]] && source $CONF

title "Where are your git repos?"
hint "The folder that holds your repo clones, one per subfolder. Edit the path or paste another."
root=$(tilde "${WORK_ROOT:-$PWD}")
while true; do
  ask root
  dir=${root/#\~/$HOME}; dir=${dir:a}
  if [[ ! -d $dir ]]; then
    confirm "$(tilde $dir) doesn't exist. Create it?" N && { mkdir -p $dir; break }
    continue
  fi
  repos=($dir/*/.git(N:h:t))
  if (( $#repos )); then ok "Found $#repos repos: ${(j:, :)repos[1,8]}$( (( $#repos > 8 )) && echo ', …')"; break; fi
  warn "No git repos directly inside $(tilde $dir)."
  confirm "Use it anyway?" N && break
done
root=$dir

title "What is your Linear team key?"
hint "The letters before the number in your issue IDs, e.g. ENG for ENG-123."
team=${WORK_TEAM:-}
while true; do
  ask team
  team=${(U)team// /}
  [[ $team == [A-Z][A-Z0-9]# ]] && break
  warn "Use letters and digits only, starting with a letter."
done

title "Where should issue folders go?"
hint "Each issue gets a folder here (wt-$team-123) with one worktree per repo it touches."
wt=$(tilde "${WORK_WORKTREES:-$root/worktrees}")
ask wt
wt=${wt/#\~/$HOME}; wt=${wt:a}

# ---- Optional extras -------------------------------------------------------
title "Extras"
add_tmux=0 add_claude=0 add_path=0
if [[ -f $TMUX_CONF ]] && grep -q 'work/tmux.conf' $TMUX_CONF; then
  ok "tmux settings already loaded from ~/.tmux.conf"
elif confirm "Add the recommended tmux settings (mouse, and Shift+Enter / Esc working in Claude Code)?"; then
  add_tmux=1
fi
confirm "Tell every Claude chat about this layout (adds a short section to ~/.claude/CLAUDE.md)?" && add_claude=1
[[ :$PATH: == *:$BIN:* ]] || { confirm "$(tilde $BIN) isn't on your PATH. Add it in ~/.zshrc?" && add_path=1 }

# ---- Summary ---------------------------------------------------------------
title "Ready to install"
print "  repos:          $(tilde $root)"
print "  team:           $team"
print "  issue folders:  $(tilde $wt)/wt-$team-123"
print "  command:        $(tilde $BIN/work) → $(tilde $HERE/work)"
(( add_tmux ))   && print "  tmux:           source $(tilde $CONF_DIR/tmux.conf) from ~/.tmux.conf"
(( add_claude )) && print "  Claude:         section in ~/.claude/CLAUDE.md"
(( add_path ))   && print "  PATH:           add $(tilde $BIN) in ~/.zshrc"
confirm "Go ahead?" || fail "Nothing was changed."

# ---- Install ---------------------------------------------------------------
mkdir -p $CONF_DIR $BIN $wt
{
  print "# work settings. Written by install.sh; rerun it to change them."
  print -r -- "WORK_ROOT=${(qq)root}"
  print -r -- "WORK_TEAM=${(qq)team}"
  print -r -- "WORK_WORKTREES=${(qq)wt}"
} > $CONF
ok "Saved settings to $(tilde $CONF)"

chmod +x $HERE/work
[[ -e $BIN/work && ! -L $BIN/work ]] && mv $BIN/work $BIN/work.bak && warn "Moved your old $(tilde $BIN/work) to work.bak"
ln -sfn $HERE/work $BIN/work
ok "Linked $(tilde $BIN/work)"

if (( add_tmux )); then
  ln -sfn $HERE/tmux.conf $CONF_DIR/tmux.conf
  print -r -- "source-file $CONF_DIR/tmux.conf  # added by work's install.sh" >> $TMUX_CONF
  tmux source-file $TMUX_CONF 2>/dev/null || true
  ok "tmux settings added"
fi

if (( add_claude )); then
  lc=${(L)team}
  block="<!-- work:begin (managed by work's install.sh; rerun it to change) -->
## Worktrees for Linear issues ($team-xxx)
- Each issue has an issue folder \`$(tilde $wt)/wt-$team-xxx\`, created by the \`work\` command, which starts the issue's Claude chats there. Keep the naming exact.
- An issue can touch several repos. For each repo it needs, create one worktree inside the issue folder: \`$(tilde $wt)/wt-$team-xxx/<repo>\` (\`<repo>\` = folder name under \`$(tilde $root)\`).
- Branch: if the issue already has a PR or branch in that repo, check out that branch. Otherwise create \`$lc-xxx\` (lowercase issue id, so Linear links the PR) from the default branch without upstream tracking: \`git -C $(tilde $root)/<repo> fetch origin && git -C $(tilde $root)/<repo> worktree add --no-track -b $lc-xxx $(tilde $wt)/wt-$team-xxx/<repo> origin/<default>\`.
- After merge, the user runs \`work done $team-xxx\`, which removes the issue's worktrees and folder, closes its tmux session and forgets it. Don't run it yourself from inside the issue's session: it ends that session, including your own chat.
<!-- work:end -->"
  mkdir -p ${CLAUDE_MD:h}; touch $CLAUDE_MD
  # Replace an earlier block, or append a new one
  awk '/<!-- work:begin/{skip=1} !skip{print} /<!-- work:end -->/{skip=0}' $CLAUDE_MD > $CLAUDE_MD.tmp
  [[ -s $CLAUDE_MD.tmp ]] && [[ $(tail -c1 $CLAUDE_MD.tmp | xxd -p) != 0a ]] && print >> $CLAUDE_MD.tmp
  [[ -s $CLAUDE_MD.tmp ]] && print >> $CLAUDE_MD.tmp
  print -r -- "$block" >> $CLAUDE_MD.tmp
  cat $CLAUDE_MD.tmp > $CLAUDE_MD; rm $CLAUDE_MD.tmp
  ok "Updated $(tilde $CLAUDE_MD)"
fi

if (( add_path )); then
  print -r -- 'export PATH="$HOME/.local/bin:$PATH"  # added by work'"'"'s install.sh' >> $HOME/.zshrc
  ok "Added $(tilde $BIN) to PATH in ~/.zshrc (open a new terminal to pick it up)"
fi

title "Done"
print "  work new          describe new work; Claude creates the Linear issue and starts on it"
print "  work $team-123      open an issue (creates its folder and Claude chats the first time)"
print "  work done         finish the current issue"
print "  work --help       everything else"
hint "\n'work new' needs Linear connected in Claude Code (claude.ai connector or Linear MCP server)."
