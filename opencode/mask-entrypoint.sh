#!/bin/sh
set -eu

info() { printf '\033[1;34m[opencode-mask]\033[0m %s\n' "$*" >&2; }
warn() { printf '\033[1;33m[opencode-mask]\033[0m %s\n' "$*" >&2; }

MASK_FILE="${PWD}/.opencode-mask"

if [ ! -f "$MASK_FILE" ]; then
    info ".opencode-mask not found in ${PWD}. Masking is not required."
    exec opencode "$@"
fi

info ".opencode-mask found. Applying masking..."

# Trimming via sed (POSIX, no xargs)
trim() {
    printf '%s' "$1" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

while IFS= read -r line || [ -n "$line" ]; do
    # Strip the comment and trim whitespac
    line="${line%%#*}"
    line="$(trim "$line")"
    [ -z "$line" ] && continue

    rel_path="${line#/}"
    target="${PWD}/${rel_path}"

    if [ -d "$target" ]; then
        info "Masking directory: ${rel_path} (tmpfs)"
        # tmpfs over the directory hides the contents; ro + mode=000 for extra protection
        mount -t tmpfs -o ro,mode=000,size=4k tmpfs "$target"
    elif [ -f "$target" ]; then
        info "Masking file: ${rel_path} (/dev/null)"
        mount --bind /dev/null "$target"
        # Best-effort: make the bind mount read-only
        mount -o remount,ro,bind "$target" 2>/dev/null || true
    else
        warn "Skipping non-existent path: ${line}"
    fi
done < "$MASK_FILE"

info "Masking complete. Starting opencode $*..."
exec opencode "$@"
