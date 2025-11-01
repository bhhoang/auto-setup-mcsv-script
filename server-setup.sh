#!/usr/bin/env bash
set -euo pipefail

# ========== Config ==========
SERVER_DIR="${SERVER_DIR:-server}"
PAPER_URL="${PAPER_URL:-https://fill-data.papermc.io/v1/objects/f6d8d80d25a687cc52a02a1d04cb25f167bb3a8a828271a263be2f44ada912cc/paper-1.21.10-91.jar}"
PAPER_JAR="${PAPER_JAR:-paper.jar}"
PLUGINS=(
  # name|url|outfile
  "Floodgate|https://download.geysermc.org/v2/projects/floodgate/versions/latest/builds/latest/downloads/spigot|Floodgate.jar"
  "Geyser|https://download.geysermc.org/v2/projects/geyser/versions/latest/builds/latest/downloads/spigot|Geyser-Spigot.jar"
  "SkinsRestorer|https://cdn.modrinth.com/data/TsLS8Py5/versions/MrnIxdcp/SkinsRestorer.jar|SkinsRestorer.jar"
  "InvSee++|https://cdn.modrinth.com/data/bYazc7fd/versions/TBZvA0QG/InvSee%2B%2B.jar|InvSee++.jar"
)

# ========== Helpers ==========
have() { command -v "$1" >/dev/null 2>&1; }

as_root() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  else
    sudo "$@"
  fi
}

apt_install() {
  as_root apt-get update -y
  as_root env  DEBIAN_FRONTEND=noninteractive apt-get install -y "$@"
}

install_basics() {
  local pkgs=(curl wget zip unzip ca-certificates)
  # neovim was in your history; optional but harmless for editing files
  pkgs+=(neovim)
  apt_install "${pkgs[@]}"
}

install_java() {
  # Try system OpenJDK 21 first
  if ! have java; then
    if apt_install openjdk-21-jre-headless 2>/dev/null; then
      :
    else
      # Fallback to SDKMAN if distro repo doesn't have JDK 21
      if ! have curl; then apt_install curl ca-certificates; fi
      # Install SDKMAN for current user
      curl -fsSL "https://get.sdkman.io" | bash
      # shellcheck source=/dev/null
      source "${HOME}/.sdkman/bin/sdkman-init.sh"
      sdk install java 21 || sdk install java 21.0.9-oracle
    fi
  fi

  # Sanity check
  if ! java -version >/dev/null 2>&1; then
    echo "Java installation failed. Install Java 21 manually and re-run." >&2
    exit 1
  fi
}

download() {
  local url="$1"
  local out="$2"
  curl -fL --retry 3 --retry-delay 2 -o "$out" "$url"
}

# ========== Main ==========
main() {
  install_basics
  install_java

  mkdir -p "$SERVER_DIR"
  echo "Using server directory: $SERVER_DIR"

  # Paper jar
  if [ -f "$SERVER_DIR/$PAPER_JAR" ]; then
    echo "Paper already present: $SERVER_DIR/$PAPER_JAR"
  else
    echo "Downloading Paper..."
    download "$PAPER_URL" "$SERVER_DIR/$PAPER_JAR"
  fi

  # EULA (so first run won't pause)
  if [ ! -f "$SERVER_DIR/eula.txt" ]; then
    echo "eula=true" > "$SERVER_DIR/eula.txt"
  fi

  # Plugins
  mkdir -p "$SERVER_DIR/plugins"
  for entry in "${PLUGINS[@]}"; do
    IFS="|" read -r name url outfile <<< "$entry"
    dest="$SERVER_DIR/plugins/$outfile"
    if [ -f "$dest" ]; then
      echo "Plugin exists: $name -> $outfile"
    else
      echo "Downloading plugin: $name"
      download "$url" "$dest"
    fi
  done

  # Friendly breadcrumbs
  echo
  echo "Setup complete."
  echo "Server folder: $(realpath "$SERVER_DIR" || echo "$SERVER_DIR")"
  echo "Paper jar:     $PAPER_JAR"
  echo "Plugins:       ${#PLUGINS[@]} installed"
  echo
  echo "When you're ready to run (not doing it for you):"
  echo "  cd \"$SERVER_DIR\""
  echo "  java -jar \"$PAPER_JAR\" nogui"
}

main "$@"
