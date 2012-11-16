#! /bin/bash
# Copyright (c) 2012, Emily Backes <lucca@accela.net>
#
# Version 0.1.1

# Message handling helper-functions
die () {
    echo "ERROR: $1" 1>&2
    exit 1
}

warn () {
    echo "WARNING: $1" 1>&2
}

clean_exit () {
    rmdir "$MUT"
    exit 0
}

# Load configuration
. mux-git-backup.conf

# Change to home directory before searching for the root
cd

# locate game root
if [ -e "$GAME/mux.config" ]; then

    # Supplied $GAME in config is valid
    :

else
    GAME=unknown
    for g in \
	"game" \
	"tinymux/mux/game" \
	"mux/game" \
	"tinymux/game" \
	"mux2.10/game" \
	"mux2.9/game" \
	"mux2.8/game" \
	"mux2.7/game" \
	"mux2.6/game"; do
	[ -e "$HOME/$g/mux.config" ] && GAME="$HOME/$g"
    done
fi
[ "$GAME" = "unknown" ] && die "Unable to locate game path."

# pull more defaults from mux.config.
. "$GAME/mux.config"
NAME="$GAMENAME"
PID="$GAME/$PIDFILE"
OMEGA="$GAME/bin/omega"
FLAT="$NAME.db.FLAT"
DFLAT="$BD/data/$FLAT"
TRYDB="$NEW_DB $INPUT_DB $SAVE_DB"

# Try to bootstrap a bit, if necessary
umask 007
BOOTSTRAP=0
if [ ! -e "$BAREBD" ]; then
    warn "Creating bare backup repository (assuming bootstrap)."
    mkdir -p "$BAREBD" || die "mkdir: $BAREBD"
    cd "$BAREBD"
    git init --bare || die "Git init for bare repository failed."
    BOOTSTRAP=1
fi
if [ ! -e "$BD" ]; then
    warn "Creating backup staging repository (assuming bootstrap)."
    mkdir -p "$BD/data" "$BD/text" || die "mkdir: $BD"
    cd "$BD"
    git init || die "Git init for backup staging repository failed."
    BOOTSTRAP=1
fi

cd "$GAME"

# Basic user checking
[ "$(whoami)" != "root" ] || die "Running as root."
[ "netmux" = "$NAME" -o "$(whoami)" = "$NAME" ] || die "Running as wrong user."

[ -e "$PID" ] || die "No pid file."
[ ! -e "$MUT" ] || die "Aborting.  Backup already in progress (or failed)."
mkdir "$MUT" || die "Unable to acquire backup mutex."
kill -0 $(<"$PID") || die "Stale pidfile."

# Locate the best structure db to use for flat generation
for f in $TRYDB; do
    [ "$f" = "$NAME.db.new" ] || warn "Checking $f for structure db candidacy."
    if [ -r "$GAME/data/$f" ]; then
	use="$f"
	break
    fi
done
[ "$use" != "" ] || die "Unable to locate a structure db candidate."
[ "$use" = "$NAME.db.new" ] || warn "Using $use for backup."

# Retrieve a flatfile
LD_LIBRARY_PATH="$GAME/bin" \
    "$GAME/bin/dbconvert" \
    -d"$GAME/data/$NAME" \
    -u \
    -i"$GAME/data/$use" \
    -o"$DFLAT" \
    2>/dev/null 1>/dev/null \
    || die "Unable to retrieve flatfile."

# Check for stale flatfile, if we can
if [ -x "$OMEGA" -a "$CRON" != "" -a "$CRON" -ge 0 ]; then
    tick=$("$OMEGA" -x "$CRON" "$DFLAT" 2>&1 \
	|grep '^&LAST_TICK' \
	|cut -d= -f2)
    [ $(( $(date +%s) - $tick )) -lt "$MAXCOUNT" ] \
	|| warn "Cron tick indicates stale dump from $tick."
fi

# Copy in other useful files
for f in comsys.db mail.db; do 
    cp "$GAME/data/$f" "$BD/data/$f" || die "Unable to copy $f."
done
for f in "$NAME.conf" mux.config; do 
    cp "$GAME/$f" "$BD/$f" || die "Unable to copy $f."
done
cp -rp "$GAME/text" "$BD" || die "Trouble copying textfiles."

# Got the files; time to backup
cd "$BD"

# Make sure there is something new to back up
[ "$(git status -s)" != "" ] || clean_exit

# Deal with bootstrap-mode adds
if [ $BOOTSTRAP = 1 ]; then
    git add -A || die "Unable to bootstrap-add files."
    warn "Auto-adding new files to backup set (assuming bootstrap)."
fi

# Make sure we don't have untracked files
[ "$(git status -s |grep '^\?\?')" != "" ] || warn "Untracked files in repo."

# Record the new backup point
git commit -q -a -m 'timed backup' || die "Git commit failed."

# Push to the bare external repo
git push -q "$BAREBD" master || die "Push to external repository failed."

# Do basic gc work to conserve space
git gc --quiet || die "Failure in git gc of staging repository."
cd "$BAREBD"
git gc --quiet || die "Failure in git gc of bare repository."

clean_exit
