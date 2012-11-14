#! /bin/bash
NAME="darkspires"

BD="$HOME/backup"
MUT="$BD/backup-in-progress"
GAME="$HOME/tinymux/mux/game"
PID="$GAME/$NAME.pid"
OMEGA="$GAME/bin/omega"
FLAT="$NAME.db.FLAT"
DFLAT="$BD/data/$FLAT"
MAXCOUNT=30
CRON=201

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

cd "$GAME"

[ "$(whoami)" = "$NAME" ] || die "Running as wrong user."
[ -e "$PID" ] || die "No pid file."
[ ! -e "$MUT" ] || die "Aborting.  Backup already in progress."
mkdir "$MUT" || die "Unable to acquire backup mutex."
kill -0 $(<"$PID") || die "Stale pidfile."
try="$NAME.db.new $NAME.db $NAME.db.old"
for f in $try; do
    if [ -r "$GAME/data/$f" ]; then
	use="$f"
	break
    fi
done
[ "$use" = "$NAME.db.new" ] || warn "Using $use for backup."
LD_LIBRARY_PATH="$GAME/bin" \
    "$GAME/bin/dbconvert" -d"$GAME/data/$NAME" -u -i"$GAME/data/$use" -o"$DFLAT" 2>/dev/null 1>/dev/null \
    || die "Unable to retrieve flatfile."
tick=$("$OMEGA" -x $CRON "$DFLAT" 2>&1 \
    |grep '^&LAST_TICK' \
    |cut -d= -f2)
[ $(( $(date +%s) - $tick )) -lt 3720 ] || warn "Cron tick indicates stale dump from $tick."
for f in comsys.db mail.db; do 
    cp "$GAME/data/$f" "$BD/data/$f" || die "Unable to copy $f."
done
for f in "$NAME.conf" mux.config; do 
    cp "$GAME/$f" "$BD/$f" || die "Unable to copy $f."
done
cp -rp "$GAME/text" "$BD" || die "Trouble copying textfiles."

cd "$BD"

# make sure there is something new to back up
[ "$(git status -s)" != "" ] || clean_exit

# make sure we don't have untracked files
[ "$(git status -s |grep '^\?\?')" != "" ] || warn "Untracked files in repo."

git commit -q -a -m 'timed backup' || die "Git commit failed."
git push -q "$HOME/git/backup.git" || die "Push to external repo failed."

clean_exit
