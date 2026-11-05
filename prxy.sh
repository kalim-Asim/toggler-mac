#!/bin/bash
# Toggle the college proxy on or off for macOS command-line tools.
# Usage:
#   ./college-proxy.sh set
#   ./college-proxy.sh unset
#   ./college-proxy.sh status

set -u

PROXY_URL="http://172.31.2.4:8080"
ZSHRC="${HOME}/.zshrc"
STATE_DIR="${HOME}/.college-proxy-state"
MARKER_BEGIN="# >>> college-proxy managed block >>>"
MARKER_END="# <<< college-proxy managed block <<<"

usage() {
  echo "Usage: $0 {set|unset|status}"
}

backup_value() {
  local key="$1"
  local value="${2-}"
  if [ ! -f "${STATE_DIR}/${key}.saved" ]; then
    printf '%s' "$value" > "${STATE_DIR}/${key}.saved"
  fi
}

restore_git() {
  if [ -f "${STATE_DIR}/git-proxy.saved" ]; then
    local value
    value="$(cat "${STATE_DIR}/git-proxy.saved")"
    if [ -n "$value" ]; then
      git config --global http.proxy "$value"
    else
      git config --global --unset-all http.proxy 2>/dev/null || true
    fi
    rm -f "${STATE_DIR}/git-proxy.saved"
  fi
}

restore_npm_key() {
  local key="$1"
  local saved="${STATE_DIR}/npm-${key}.saved"
  if [ -f "$saved" ]; then
    local value
    value="$(cat "$saved")"
    if [ -n "$value" ]; then
      npm config set "$key" "$value" >/dev/null 2>&1 || true
    else
      npm config delete "$key" >/dev/null 2>&1 || true
    fi
    rm -f "$saved"
  fi
}

restore_pip() {
  if [ -f "${STATE_DIR}/pip-proxy.saved" ]; then
    local value
    value="$(cat "${STATE_DIR}/pip-proxy.saved")"
    if [ -n "$value" ]; then
      python3 -m pip config set global.proxy "$value" >/dev/null 2>&1 || true
    else
      python3 -m pip config unset global.proxy >/dev/null 2>&1 || true
    fi
    rm -f "${STATE_DIR}/pip-proxy.saved"
  fi
}

case "${1-}" in
  set)
    mkdir -p "$STATE_DIR"
    touch "$ZSHRC"

    # Save existing tool settings only once, so repeated "set" won't
    # accidentally save the proxy as the original setting.
    if [ ! -f "${STATE_DIR}/git-proxy.saved" ]; then
      backup_value git-proxy "$(git config --global --get http.proxy 2>/dev/null || true)"
    fi
    if command -v npm >/dev/null 2>&1; then
      for key in proxy https-proxy; do
        if [ ! -f "${STATE_DIR}/npm-${key}.saved" ]; then
          backup_value "npm-${key}" "$(npm config get "$key" 2>/dev/null | grep -v '^null$' || true)"
        fi
      done
    fi
    if command -v python3 >/dev/null 2>&1; then
      if [ ! -f "${STATE_DIR}/pip-proxy.saved" ]; then
        backup_value pip-proxy "$(python3 -m pip config get global.proxy 2>/dev/null || true)"
      fi
    fi

    # Replace any previously managed block in ~/.zshrc.
    tmp="$(mktemp)"
    awk -v b="$MARKER_BEGIN" -v e="$MARKER_END" '
      $0 == b { skip=1; next }
      $0 == e { skip=0; next }
      !skip { print }
    ' "$ZSHRC" > "$tmp"
    cat "$tmp" > "$ZSHRC"
    rm -f "$tmp"

    cat >> "$ZSHRC" <<EOF

$MARKER_BEGIN
export HTTP_PROXY="$PROXY_URL"
export HTTPS_PROXY="$PROXY_URL"
export ALL_PROXY="$PROXY_URL"
export http_proxy="\$HTTP_PROXY"
export https_proxy="\$HTTPS_PROXY"
export all_proxy="\$ALL_PROXY"
export NO_PROXY="localhost,127.0.0.1,::1"
export no_proxy="\$NO_PROXY"
$MARKER_END
EOF

    git config --global http.proxy "$PROXY_URL"
    if command -v npm >/dev/null 2>&1; then
      npm config set proxy "$PROXY_URL" >/dev/null
      npm config set https-proxy "$PROXY_URL" >/dev/null
    fi
    if command -v python3 >/dev/null 2>&1; then
      python3 -m pip config set global.proxy "$PROXY_URL" >/dev/null 2>&1 || true
    fi

    export HTTP_PROXY="$PROXY_URL" HTTPS_PROXY="$PROXY_URL" ALL_PROXY="$PROXY_URL"
    export http_proxy="$PROXY_URL" https_proxy="$PROXY_URL" all_proxy="$PROXY_URL"
    export NO_PROXY="localhost,127.0.0.1,::1" no_proxy="localhost,127.0.0.1,::1"

    echo "College proxy enabled: $PROXY_URL"
    echo "Persistent shell settings written to $ZSHRC"
    echo "Current shell: environment variables set for this script only."
    echo "Run: source ~/.zshrc   (or open a new Terminal window) to load them."
    ;;

  unset)
    # Remove only the block managed by this script.
    if [ -f "$ZSHRC" ]; then
      tmp="$(mktemp)"
      awk -v b="$MARKER_BEGIN" -v e="$MARKER_END" '
        $0 == b { skip=1; next }
        $0 == e { skip=0; next }
        !skip { print }
      ' "$ZSHRC" > "$tmp"
      cat "$tmp" > "$ZSHRC"
      rm -f "$tmp"
    fi

    restore_git
    restore_npm_key proxy
    restore_npm_key https-proxy
    restore_pip

    unset HTTP_PROXY HTTPS_PROXY ALL_PROXY http_proxy https_proxy all_proxy NO_PROXY no_proxy
    echo "College proxy disabled in saved settings and this script's shell."
    echo "Run: source ~/.zshrc   (or open a new Terminal window) to refresh the current Terminal."
    echo "Note: system-wide macOS proxy settings were not changed."
    ;;

  status)
    echo "Proxy environment:"
    env | grep -iE '^(http|https|all|no)_proxy=' || echo "No proxy environment variables set in this shell."
    echo
    echo "Git proxy: $(git config --global --get http.proxy 2>/dev/null || echo '(not set)')"
    if command -v npm >/dev/null 2>&1; then
      echo "npm proxy: $(npm config get proxy 2>/dev/null)"
      echo "npm HTTPS proxy: $(npm config get https-proxy 2>/dev/null)"
    fi
    if command -v python3 >/dev/null 2>&1; then
      echo "pip proxy: $(python3 -m pip config get global.proxy 2>/dev/null || echo '(not set)')"
    fi
    echo
    echo "macOS system proxy (read-only):"
    scutil --proxy
    ;;

  *)
    usage
    exit 2
    ;;
esac
