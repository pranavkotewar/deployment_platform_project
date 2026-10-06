#!/bin/bash
#detect_apps.sh <repo_dir>
# It scans the repo and gives the JSON list of apps detected in the repo.

REPO_DIR="${1:-.}"

if [ ! -d "$REPO_DIR" ]; then
    echo '{"error": "Repo directory not found"}'
    exit 1
fi

has_compose() {
    [ -f "$1/docker-compose.yml" ] || [ -f "$1/docker-compose.yaml" ]
}

has_dockerfile() {
    [ -f "$1/Dockerfile" ]
}

suggest_template() {
    local d="$1"
    if [ -f "$d/package.json" ]; then
        echo "node"
    elif [ -f "$d/requirements.txt" ] || [ -f "$d/app.py" ] || [ -f "$d/main.py" ]; then
        echo "flask"
    elif ls "$d"/*.html >/dev/null 2>&1; then
        echo "static"
    else
        echo ""
    fi
}

is_candidate() {
    local d="$1"
    has_compose "$d" || has_dockerfile "$d" || [ -n "$(suggest_template "$d")" ]
}

#emit <name> <dir -> prints a JSON object
emit() {
    local name="$1" dir="$2" tpl
    if has_compose "$dir"; then
        printf '{"name":"%s", "path":"%s", "supported":false, "reason":"Multi-container (docker-compose) apps are not supported in V2"}' "$name" "$name"
    elif has_dockerfile "$dir"; then
        printf '{"name":"%s", "path":"%s", "dockerfile_found":true, "suggested_template":null, "supported":true}' "$name" "$name"
    else
        tpl="$(suggest_template "$dir")"
        if [ -n "$tpl" ]; then
            printf '{"name":"%s", "path":"%s", "dockerfile_found":false, "suggested_template":"%s", "supported":true}' "$name" "$name" "$tpl"
        else
            printf '{"name":"%s","path":"%s", "dockerfile_found":false, "suggested_template":null, "supported":true}' "$name" "$name"
        fi
    fi
}

items=()

if has_dockerfile "$REPO_DIR" || has_compose "$REPO_DIR"; then
    #Single-app mode: root is app
    items+=("$(emit "." "$REPO_DIR")")
else
    #1-level-deep folders scan
    for d in "$REPO_DIR"/*/; do
        [ -d "$d" ] || continue
        name="$(basename "$d")"
        [ "$name" = "node_modules" ] && continue
        if is_candidate "$d"; then
            items+=("$(emit "$name" "${d%/}")")
        fi
    done
    # If nothing found, then consider root as app (like simple static repo)
    if [ ${#items[@]} -eq 0 ]; then
        items+=("$(emit "." "$REPO_DIR")")
    fi
fi

IFS=','
printf '[%s]\n' "${items[*]}"
