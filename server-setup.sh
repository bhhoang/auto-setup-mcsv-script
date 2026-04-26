#!/usr/bin/env bash
set -euo pipefail

# ========== Config ==========
SERVER_DIR="server2"
MINECRAFT_VERSION="latest"
PAPER_JAR="${PAPER_JAR:-paper.jar}"

# Java Config
JAVA_MAJOR_VERSION="25"
JAVA_LOCAL_DIR="java"

# API Info
PROJECT="paper"
USER_AGENT="PaperSetupScript/1.0.0 (admin@example.com)"

PLUGINS=(
  "modrinth|luckperms|LuckPerms.jar"
  "modrinth|coreprotect|CoreProtect.jar"
  "direct|https://download.geysermc.org/v2/projects/floodgate/versions/latest/builds/latest/downloads/spigot|Floodgate.jar"
  "direct|https://download.geysermc.org/v2/projects/geyser/versions/latest/builds/latest/downloads/spigot|Geyser-Spigot.jar"
  "modrinth|skinsrestorer|SkinsRestorer.jar"
  "modrinth|chunky|Chunky.jar"
  "modrinth|viaversion|ViaVersion.jar"
  "modrinth|tab-was-taken|TAB.jar"
  "modrinth|gsit|GSit.jar"
  "modrinth|bYazc7fd|InvSee++.jar"
  "modrinth|clickvillagers|ClickVillagers.jar"
  "modrinth|veinminer|Veinminer.jar"
  "modrinth|dynmap|Dynmap.jar"
  "modrinth|infinite-villager-trading|InfiniteVillagerTrading.jar"
)

# ========== Core Utilities ==========

download() {
  local url="$1"
  local out="$2"
  if command -v curl >/dev/null 2>&1; then
    curl -sSL --fail --retry 3 --retry-delay 2 -o "$out" "$url"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$out" "$url"
  else
    echo "Error: Neither curl nor wget is installed." >&2
    exit 1
  fi
}

api_fetch() {
  local endpoint="$1"
  if command -v curl >/dev/null 2>&1; then
    curl -s -H "User-Agent: $USER_AGENT" "$endpoint"
  else
    wget -qO- --header="User-Agent: $USER_AGENT" "$endpoint"
  fi
}

check_dependencies() {
  if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
    echo "Error: Neither curl nor wget found. Cannot proceed." >&2
    exit 1
  fi

  # Handle missing jq by downloading a standalone local binary
  local_bin="$SERVER_DIR/.bin"
  mkdir -p "$local_bin"
  export PATH="$PWD/$local_bin:$PATH"

  if ! command -v jq >/dev/null 2>&1; then
    echo "System 'jq' not found. Downloading portable local jq..."
    download "https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-linux-amd64" "$local_bin/jq"
    chmod +x "$local_bin/jq"
  fi
}

# ========== Setup Modules ==========

install_local_java() {
  local target_dir="$SERVER_DIR/$JAVA_LOCAL_DIR"
  if [ -f "$target_dir/bin/java" ]; then
    echo "Local Java $JAVA_MAJOR_VERSION is already installed."
    return
  fi

  echo "Downloading local Java (JDK $JAVA_MAJOR_VERSION)..."
  mkdir -p "$target_dir"
  local java_url="https://api.adoptium.net/v3/binary/latest/${JAVA_MAJOR_VERSION}/ga/linux/x64/jdk/hotspot/normal/eclipse?project=jdk"
  local tmp_tar="$SERVER_DIR/local_java_${JAVA_MAJOR_VERSION}.tar.gz"
  
  if ! command -v tar >/dev/null 2>&1; then
    echo "Error: 'tar' is required to extract Java." >&2
    exit 1
  fi
  
  download "$java_url" "$tmp_tar"
  tar -xzf "$tmp_tar" -C "$target_dir" --strip-components=1
  rm -f "$tmp_tar"
  echo "Local Java successfully installed."
}

install_paper() {
  if [ -f "$SERVER_DIR/$PAPER_JAR" ]; then
    echo "Paper already present."
    return
  fi

  echo "Resolving Paper URL..."
  local target_version="$MINECRAFT_VERSION"
  local paper_url="null"

  if [ "$target_version" != "latest" ]; then
    local builds_response
    builds_response=$(api_fetch "https://fill.papermc.io/v3/projects/${PROJECT}/versions/${target_version}/builds")
    if ! echo "$builds_response" | jq -e '.ok == false' > /dev/null 2>&1; then
      paper_url=$(echo "$builds_response" | jq -r 'first(.[] | select(.channel == "STABLE") | .downloads."server:default".url) // "null"')
    fi
  fi

  if [ "$paper_url" == "null" ]; then
    local versions
    versions=$(api_fetch "https://fill.papermc.io/v3/projects/${PROJECT}" | jq -r '.versions | to_entries[] | .value[]' | sort -V -r)

    for version in $versions; do
      local version_builds
      version_builds=$(api_fetch "https://fill.papermc.io/v3/projects/${PROJECT}/versions/${version}/builds")
      local stable_url
      stable_url=$(echo "$version_builds" | jq -r 'first(.[] | select(.channel == "STABLE") | .downloads."server:default".url) // "null"')

      if [ "$stable_url" != "null" ]; then
        paper_url="$stable_url"
        break
      fi
    done
  fi

  if [ "$paper_url" != "null" ]; then
    echo "Downloading Paper..."
    download "$paper_url" "$SERVER_DIR/$PAPER_JAR"
  else
    echo "Error: No stable builds available." >&2
    exit 1
  fi
}

install_plugins() {
  mkdir -p "$SERVER_DIR/plugins"
  echo "Checking and downloading plugins..."
  
  for entry in "${PLUGINS[@]}"; do
    IFS="|" read -r type identifier outfile <<< "$entry"
    dest="$SERVER_DIR/plugins/$outfile"
    
    echo "Resolving plugin: $outfile..."
    local dl_url=""
    
    if [ "$type" == "modrinth" ]; then
      local response
      response=$(api_fetch "https://api.modrinth.com/v2/project/$identifier/version")
      
      # Filter to ONLY versions that declare paper, bukkit, or spigot as their loader
      dl_url=$(echo "$response" | jq -r '
        [ .[] | select(.loaders != null and (.loaders | index("paper") or index("bukkit") or index("spigot"))) ]
        | .[0].files[0].url // empty
      ')
      
      if [ -z "$dl_url" ] || [ "$dl_url" == "null" ]; then
        echo "  [!] Error: Could not find a Bukkit/Paper version for '$identifier'. Skipping."
        continue
      fi
    elif [ "$type" == "direct" ]; then
      dl_url="$identifier"
    fi

    if [ -n "$dl_url" ]; then
      echo "  -> Downloading to $outfile..."
      download "$dl_url" "$dest"
    fi
  done
}

write_run_script() {
  local run_file="$SERVER_DIR/run.sh"
  
  if [ ! -f "$SERVER_DIR/eula.txt" ]; then
    echo "eula=true" > "$SERVER_DIR/eula.txt"
  fi

  echo "Generating $run_file..."
  cat << 'EOF' > "$run_file"
#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export JAVA_HOME="$DIR/java"
chmod +x "$JAVA_HOME/bin/java"

"$JAVA_HOME/bin/java" \
  -Xms16G -Xmx16G --add-modules=jdk.incubator.vector \
  -XX:+UseG1GC -XX:+ParallelRefProcEnabled -XX:MaxGCPauseMillis=200 \
  -XX:+UnlockExperimentalVMOptions -XX:+DisableExplicitGC -XX:+AlwaysPreTouch \
  -XX:G1HeapWastePercent=5 -XX:G1MixedGCCountTarget=4 \
  -XX:InitiatingHeapOccupancyPercent=15 -XX:G1MixedGCLiveThresholdPercent=90 \
  -XX:G1RSetUpdatingPauseTimePercent=5 -XX:SurvivorRatio=32 \
  -XX:+PerfDisableSharedMem -XX:MaxTenuringThreshold=1 \
  -XX:G1NewSizePercent=40 -XX:G1MaxNewSizePercent=50 \
  -XX:G1HeapRegionSize=16M -XX:G1ReservePercent=15 \
  -XX:+UseNUMA -XX:+UseFastUnorderedTimeStamps -XX:+UseFMA \
  -jar paper.jar --nogui
EOF

  chmod +x "$run_file"
}

# ========== Main Execution ==========
main() {
  mkdir -p "$SERVER_DIR"
  check_dependencies

  local action="${1:-all}"

  case "$action" in
    all)
      echo "=== Starting Full Server Setup ==="
      install_local_java
      install_paper
      install_plugins
      write_run_script
      echo
      echo "Setup complete!"
      echo "  cd \"$SERVER_DIR\""
      echo "  ./run.sh"
      ;;
    plugins)
      echo "=== Updating Plugins Only ==="
      install_plugins
      echo
      echo "Plugins successfully updated!"
      ;;
    *)
      echo "Usage: $0 [all|plugins]"
      echo "  all     - Set up the entire server (Default)"
      echo "  plugins - Only download/update plugins in the PLUGINS list"
      exit 1
      ;;
  esac
}

main "$@"
