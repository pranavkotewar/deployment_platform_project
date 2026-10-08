#!/bin/bash
# detect_apps.sh <repo_dir>
# Repo scan karke apps ki JSON list print karta hai.

REPO_DIR="${1:-.}"

if [ ! -d "$REPO_DIR" ]; then
  echo '{"error":"repo directory not found"}'
  exit 1
fi

has_compose() {
  [ -f "$1/docker-compose.yml" ] || [ -f "$1/docker-compose.yaml" ] || [ -f "$1/compose.yml" ] || [ -f "$1/compose.yaml" ]
}

has_dockerfile() {
  [ -f "$1/Dockerfile" ]
}

has_flask() {
  local d="$1"
  grep -qsi 'flask' "$d/requirements.txt" "$d/pyproject.toml" "$d/Pipfile" && return 0
  grep -qsiE '^(from|import) flask' "$d/app.py" "$d/main.py" "$d/server.py" "$d/wsgi.py" "$d/run.py" "$d/application.py" "$d/app/__init__.py"
}

suggest_template() {
  local d="$1"
  if [ -f "$d/package.json" ]; then
    echo "node"
  elif has_flask "$d"; then
    echo "flask"
  elif [ -f "$d/index.html" ]; then
    echo "static"
  else
    echo ""
  fi
}

# Weak folders: sirf tab ignore karte hain jab unme Dockerfile/compose na ho
is_helper_folder() {
  case "$1" in
    node_modules|venv|env|__pycache__|templates|static|public|assets|dist|build|docs|doc|test|tests) return 0 ;;
  esac
  return 1
}

emit() {
  local name="$1" dir="$2" tpl
  if has_compose "$dir"; then
    printf '{"name":"%s","path":"%s","supported":false,"reason":"Multi-container (docker-compose) apps are not supported in V2"}' "$name" "$name"
  elif has_dockerfile "$dir"; then
    printf '{"name":"%s","path":"%s","dockerfile_found":true,"suggested_template":null,"supported":true}' "$name" "$name"
  else
    tpl="$(suggest_template "$dir")"
    if [ -n "$tpl" ]; then
      printf '{"name":"%s","path":"%s","dockerfile_found":false,"suggested_template":"%s","supported":true}' "$name" "$name" "$tpl"
    else
      printf '{"name":"%s","path":"%s","dockerfile_found":false,"suggested_template":null,"supported":true}' "$name" "$name"
    fi
  fi
}

items=()

if has_dockerfile "$REPO_DIR" || has_compose "$REPO_DIR"; then
  # Single-app mode: root hi app hai
  items+=("$(emit "." "$REPO_DIR")")
else
  root_tpl="$(suggest_template "$REPO_DIR")"
  if [ -n "$root_tpl" ]; then
    items+=("$(emit "." "$REPO_DIR")")
  fi

  while IFS= read -r d; do
    name="$(basename "$d")"
    [ "${name:0:1}" = "." ] && continue
    [ "$name" = "node_modules" ] && continue
    [ "$name" = "venv" ] && continue

    if has_compose "$d" || has_dockerfile "$d"; then
      items+=("$(emit "$name" "$d")")
      continue
    fi

    tpl="$(suggest_template "$d")"
    [ -z "$tpl" ] && continue
    is_helper_folder "$name" && continue
    if [ "$tpl" = "static" ] && [ -n "$root_tpl" ]; then
      continue
    fi
    items+=("$(emit "$name" "$d")")
  done < <(find "$REPO_DIR" -mindepth 1 -maxdepth 1 -type d | sort)

  # Kuch na mila to root ko hi app maano
  if [ ${#items[@]} -eq 0 ]; then
    items+=("$(emit "." "$REPO_DIR")")
  fi
fi

IFS=','
printf '[%s]\n' "${items[*]}"
