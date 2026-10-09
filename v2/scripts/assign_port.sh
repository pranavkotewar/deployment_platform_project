#!/bin/bash
# assign_port.sh assign <name> <container_port> | get <name> | list | release <name>
# Registry: ~/deployforge/ports.db  (har line: name host_port container_port)

REG_DIR="$HOME/deployforge"
REG="$REG_DIR/ports.db"
LOCK="$REG_DIR/ports.lock"
MIN_PORT=9001
MAX_PORT=9099

die() { echo "ERROR: $1"; exit 1; }

command -v flock >/dev/null 2>&1 || die "flock is not installed"
command -v ss >/dev/null 2>&1 || die "ss is not installed"
mkdir -p "$REG_DIR" || die "cannot create $REG_DIR"
touch "$REG" || die "cannot create registry file"

CMD="$1"
NAME="$2"
CPORT="${3:-80}"

valid_name() {
  echo "$1" | grep -qE '^[a-z0-9][a-z0-9-]{0,40}$'
}

valid_port() {
  echo "$1" | grep -qE '^[0-9]{1,5}$' && [ "$1" -ge 1 ] && [ "$1" -le 65535 ]
}

lookup_port() {
  awk -v n="$1" 'NF==3 && $1==n {print $2; exit}' "$REG"
}

port_in_registry() {
  awk -v p="$1" 'NF==3 && $2==p {f=1} END {exit !f}' "$REG"
}

port_in_use() {
  ss -ltn < /dev/null 2>/dev/null | awk 'NR>1 {print $4}' | grep -qE ":$1$"
}

# Is port ko is app ka apna docker container use kar raha hai?
owned_by_app() {
  command -v docker >/dev/null 2>&1 || return 1
  docker port "$1" < /dev/null 2>/dev/null | grep -qE ":$2$"
}

# Command chalao, output tmp file mein lo. Command fail to registry untouched.
update_registry() {
  local tmp
  tmp=$(mktemp "$REG_DIR/ports.XXXXXX") || return 1
  if "$@" > "$tmp" && mv "$tmp" "$REG"; then
    return 0
  fi
  rm -f "$tmp"
  return 1
}

# Purani entries + ek nayi entry. awk fail ho to echo nahi chalta.
add_entry() {
  awk 'NF==3 {print}' "$REG" && echo "$1 $2 $3"
}

lock() {
  exec 9>"$LOCK" || die "cannot open lock file"
  flock -w 30 9 || die "could not acquire registry lock"
}

allocate_free_port() {
  local p
  for ((p=MIN_PORT; p<=MAX_PORT; p++)); do
    if ! port_in_registry "$p" && ! port_in_use "$p"; then
      echo "$p"
      return 0
    fi
  done
  return 1
}

case "$CMD" in
  assign)
    valid_name "$NAME" || die "invalid app name (use lowercase letters, digits, hyphen)"
    valid_port "$CPORT" || die "invalid container port ($CPORT), must be 1-65535"
    lock
    EXISTING=$(lookup_port "$NAME")

    if [ -n "$EXISTING" ]; then
      PORT="$EXISTING"
      if port_in_use "$PORT" && ! owned_by_app "$NAME" "$PORT"; then
        NEWPORT=$(allocate_free_port) || die "no free port available in range $MIN_PORT-$MAX_PORT"
        echo "WARNING: port $PORT is used by another process, moving $NAME to $NEWPORT"
        PORT="$NEWPORT"
      fi
      update_registry awk -v n="$NAME" -v p="$PORT" -v c="$CPORT" \
        'NF==3 && $1==n {print $1, p, c; next} NF==3 {print}' "$REG" \
        || die "could not update registry"
      echo "PORT=$PORT"
      exit 0
    fi

    PORT=$(allocate_free_port) || die "no free port available in range $MIN_PORT-$MAX_PORT"
    update_registry add_entry "$NAME" "$PORT" "$CPORT" || die "could not update registry"
    echo "PORT=$PORT"
    ;;
  get)
    valid_name "$NAME" || die "invalid app name"
    lock
    PORT=$(lookup_port "$NAME")
    [ -n "$PORT" ] || die "app not found in registry ($NAME)"
    echo "PORT=$PORT"
    ;;
  list)
    lock
    awk 'NF==3 {print}' "$REG"
    ;;
  release)
    valid_name "$NAME" || die "invalid app name"
    lock
    if [ -z "$(lookup_port "$NAME")" ]; then
      echo "Nothing to release ($NAME not in registry)"
      exit 0
    fi
    update_registry awk -v n="$NAME" 'NF==3 && $1!=n {print}' "$REG" \
      || die "could not update registry"
    echo "Released $NAME"
    ;;
  *)
    echo "Usage: assign_port.sh assign <name> <container_port> | get <name> | list | release <name>"
    exit 1
    ;;
esac
