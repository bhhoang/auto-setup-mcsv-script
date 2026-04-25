#!/usr/bin/env bash
set -euo pipefail

# ========== Config ==========
SERVER_DIR="${SERVER_DIR:-server2}"
MC_VERSION="${MC_VERSION:-latest}"

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
)

# Install plugins
install_plugins() {
  mkdir -p "$SERVER_DIR/plugins"
  for entry in "${PLUGINS[@]}"; do
    IFS="|" read -r type identifier outfile <<< "$entry"
    dest="$SERVER_DIR/plugins/$outfile"
    if [ "$type" == "modrinth" ]; then
      dl_url=$(curl -s "https://api.modrinth.com/v2/project/$identifier/version" | \
        jq -r '[.[] | select(.loaders != null and (.loaders | index("paper") or index("bukkit") or index("spigot")))] | .[0].files[0].url // empty')
      [ -n "$dl_url" ] && curl -sSL --fail -o "$dest" "$dl_url"
    elif [ "$type" == "direct" ]; then
      curl -sSL --fail -o "$dest" "$identifier"
    fi
  done
}

install_plugins
