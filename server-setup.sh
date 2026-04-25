#!/usr/bin/env bash
set -euo pipefail

# ========== Config ==========
SERVER_DIR="${SERVER_DIR:-server}"
MINECRAFT_VERSION="${MINECRAFT_VERSION:-latest}"
PAPER_JAR="${PAPER_JAR:-paper.jar}"

# Java Config
JAVA_MAJOR_VERSION="21"
JAVA_LOCAL_DIR="java" # Created inside SERVER_DIR

# Fill v3 API requires a non-generic User-Agent
PROJECT="paper"
USER_AGENT="PaperSetupScript/1.0.0 (admin@example.com)"

PLUGINS=(
  # name|url|outfile
  "Floodgate|https://download.geysermc.org/v2/projects/floodgate/versions/latest/builds/latest/downloads/spigot|Floodgate.jar"
  "Geyser|https://download.geysermc.org/v2/projects/geyser/versions/latest/builds/latest/downloads/spigot|Geyser-Spigot.jar"
  "SkinsRestorer|https://cdn.modrinth.com/data/TsLS8Py5/versions/MrnIxdcp/SkinsRestorer.jar|SkinsRestorer.jar"
  "InvSee++|https://cdn.modrinth.com/data/bYazc7fd/versions/TBZvA0QG/InvSee%2B%2B.jar|InvSee++.jar"
)

# ========== Helpers ==========

download() {
  local url="$1"
  local out="$2"
  if command -v curl >/dev/null 2>&1; then
    curl -sSL --fail --retry 3 --retry-delay 2 -o "$out" "$url"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$out" "$url"
  else
    echo "Error: Neither curl nor wget is installed. Cannot download files." >&2
    exit 1
  fi
}

check_dependencies() {
  echo "Checking dependencies..."
  
  # Ensure we have a way to download
  if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
    echo "Error: Neither curl nor wget found. Cannot proceed without a downloader." >&2
    exit 1
  fi

  # Ensure we have tar to extract Java
  if ! command -v tar >/dev/null 2>&1; then
    echo "Error: 'tar' is required to extract the Java downloaded archive." >&2
    exit 1
  fi

  # Handle jq locally if missing (needed for API parsing)
  local_bin="$SERVER_DIR/.bin"
  mkdir -p "$local_bin"
  export PATH="$local_bin:$PATH"

  if ! command -v jq >/dev/null 2>&1; then
    echo "System 'jq' not found. Downloading portable local jq..."
    # Download static jq binary for Linux x64
    download "https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-linux-amd64" "$local_bin/jq"
    chmod +x "$local_bin/jq"
  fi
}

# ========== Core Functions ==========

install_local_java() {
  local target_dir="$SERVER_DIR/$JAVA_LOCAL_DIR"
  
  if [ -f "$target_dir/bin/java" ]; then
    echo "Local Java $JAVA_MAJOR_VERSION is already installed in $target_dir"
    return
  fi

  echo "Downloading local Java (JDK $JAVA_MAJOR_VERSION) to $target_dir..."
  mkdir -p "$target_dir"
  
  # Fetch latest JDK tarball for Linux x64 from Adoptium (Eclipse Temurin)
  local java_url="https://api.adoptium.net/v3/binary/latest/${JAVA_MAJOR_VERSION}/ga/linux/x64/jdk/hotspot/normal/eclipse?project=jdk"
  local tmp_tar="$SERVER_DIR/local_java_${JAVA_MAJOR_VERSION}.tar.gz"
  
  download "$java_url" "$tmp_tar"
  
  # Extract and strip the top-level directory so the bin/ folder sits directly in target_dir
  tar -xzf "$tmp_tar" -C "$target_dir" --strip-components=1
  rm -f "$tmp_tar"
  
  echo "Local Java successfully installed."
}

get_paper_url() {
  local target_version="$1"
  local paper_url="null"

  # Curl wrapper for API calls to support fallback to wget
  api_fetch() {
    local endpoint="$1"
    if command -v curl >/dev/null 2>&1; then
      curl -s -H "User-Agent: $USER_AGENT" "$endpoint"
    else
      wget -qO- --header="User-Agent: $USER_AGENT" "$endpoint"
    fi
  }

  if [ "$target_version" != "latest" ]; then
    local builds_response
    builds_response=$(api_fetch "https://fill.papermc.io/v3/projects/${PROJECT}/versions/${target_version}/builds")
    
    if ! echo "$builds_response" | jq -e '.ok == false' > /dev/null 2>&1; then
      paper_url=$(echo "$builds_response" | jq -r 'first(.[] | select(.channel == "STABLE") | .downloads."server:default".url) // "null"')
    fi
  fi

  if [ "$paper_url" == "null" ]; then
    local versions
    versions=$(api_fetch "https://fill.papermc.io/v3/projects/${PROJECT}" | \
      jq -r '.versions | to_entries[] | .value[]' | \
      sort -V -r)

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
    echo "$paper_url"
  else
    echo "Error: No stable builds available for any version." >&2
    exit 1
  fi
}

write_run_script() {
  local run_file="$SERVER_DIR/run.sh"
  echo "Generating $run_file..."

  cat << 'EOF' > "$run_file"
#!/usr/bin/env bash

# Resolve the directory of this script so it can be run from anywhere
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Point JAVA_HOME to the local java folder we downloaded
export JAVA_HOME="$DIR/java"

# Ensure the local java binary is executable
chmod +x "$JAVA_HOME/bin/java"

# Start the server using the optimized flags
"$JAVA_HOME/bin/java" \
  -Xms16G \
  -Xmx16G \
  --add-modules=jdk.incubator.vector \
  -XX:+UseG1GC \
  -XX:+ParallelRefProcEnabled \
  -XX:MaxGCPauseMillis=200 \
  -XX:+UnlockExperimentalVMOptions \
  -XX:+DisableExplicitGC \
  -XX:+AlwaysPreTouch \
  -XX:G1HeapWastePercent=5 \
  -XX:G1MixedGCCountTarget=4 \
  -XX:InitiatingHeapOccupancyPercent=15 \
  -XX:G1MixedGCLiveThresholdPercent=90 \
  -XX:G1RSetUpdatingPauseTimePercent=5 \
  -XX:SurvivorRatio=32 \
  -XX:+PerfDisableSharedMem \
  -XX:MaxTenuringThreshold=1 \
  -XX:G1NewSizePercent=40 \
  -XX:G1MaxNewSizePercent=50 \
  -XX:G1HeapRegionSize=16M \
  -XX:G1ReservePercent=15 \
  -XX:+UseNUMA \
  -XX:+UseFastUnorderedTimeStamps \
  -XX:+UseFMA \
  -jar paper.jar --nogui
EOF

  chmod +x "$run_file"
}

# ========== Main ==========
main() {
  mkdir -p "$SERVER_DIR"
  echo "Using server directory: $SERVER_DIR"

  # 1. Check for basic tools or download them locally
  check_dependencies

  # 2. Install local portable Java
  install_local_java

  # 3. Paper jar download
  if [ -f "$SERVER_DIR/$PAPER_JAR" ]; then
    echo "Paper already present: $SERVER_DIR/$PAPER_JAR"
  else
    echo "Resolving Paper download URL..."
    local paper_url
    paper_url=$(get_paper_url "$MINECRAFT_VERSION")
    
    echo "Downloading Paper..."
    download "$paper_url" "$SERVER_DIR/$PAPER_JAR"
  fi

  # 4. EULA bypass
  if [ ! -f "$SERVER_DIR/eula.txt" ]; then
    echo "eula=true" > "$SERVER_DIR/eula.txt"
  fi

  # 5. Plugins download
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

  # 6. Generate run.sh
  write_run_script

  # Friendly breadcrumbs
  echo
  echo "Setup complete."
  echo "Server folder:  $(realpath "$SERVER_DIR" || echo "$SERVER_DIR")"
  echo "Paper jar:      $PAPER_JAR"
  echo "Local Java:     $JAVA_LOCAL_DIR/bin/java"
  echo "Run Script:     run.sh"
  echo
  echo "When you're ready to start the server, just run:"
  echo "  cd \"$SERVER_DIR\""
  echo "  ./run.sh"
}

main "$@"
