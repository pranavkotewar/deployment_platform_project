#!/bin/bash
# record.sh add <name> <repo_url> <app_path> <template> | remove <name>
# DB: ~/deployforge/deployments.db  (har line: name repo app_path template epoch)

DF="$HOME/deployforge"
DB="$DF/deployments.db"
LOCK="$DF/deployments.lock"
CMD="$1"
NAME="$2"

die() { echo "ERROR: $1"; exit 1; }

echo "$NAME" | grep -qE '^[a-z0-9][a-z0-9-]{0,40}$' || die "invalid name"
mkdir -p "$DF"
touch "$DB"
exec 7>"$LOCK"
flock -w 20 7 || die "lock timeout"

rewrite() {
    local tmp
    tmp=$(mktemp "$DF/dep.XXXXXX") || return 1
    if awk -v n="$NAME" 'NF==5 && $1!=n {print}' "$DB" > "$tmp"; then
        [ "$CMD" = "add" ] && echo "$NAME $2 ${3:-.} ${4:--} $(date +%s)" >> "$tmp"
        chmod 644 "$tmp"
        mv "$tmp" "$DB"
        return 0
    fi
    rm -f "$tmp"
    return 1
}

case "$CMD" in
    add)
        echo "$3" | grep -qE '^https://github\.com/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$' || die "invalid repo"
        rewrite "$NAME" "$3" "$4" "$5" || die "could not write record"
        echo "RECORDED $NAME"
        ;;
    remove)
        rewrite || die "could not update record"
        echo "Record removed ($NAME)"
        ;;
    *)
        echo "Usage: record.sh add <name> <repo_url> <app_path> <template> | remove <name>"
        exit 1
        ;;
esac
