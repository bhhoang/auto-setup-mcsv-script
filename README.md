# auto-setup-mcsv-script

A small Bash script that bootstraps a **Paper (Minecraft) server directory** by:

- Creating a server folder
- Downloading a **local Java (Adoptium JDK 25)** into that folder
- Downloading the **latest stable Paper** build (or a specific Minecraft version)
- Downloading a curated list of plugins (Modrinth + direct URLs)
- Generating a `run.sh` to start the server (and auto-accepting the EULA)

Repo: `bhhoang/auto-setup-mcsv-script`

---

## Files

- `server-setup.sh` — main setup script
- `server2/` (default) — output server directory created by the script

---

## Requirements

- Linux server or Linux VM (script downloads Linux x64 JDK)
- `bash`
- Either `curl` **or** `wget`
- `tar` (required to extract the downloaded JDK)

### About `jq`

The script uses `jq` to parse JSON from the Paper/Modrinth APIs.

If `jq` is not installed on the system, the script will automatically download a portable `jq` binary into:

- `SERVER_DIR/.bin/jq`

and temporarily prepend it to `PATH`.

---

## Quick start

1. SSH into your server and clone the repo:

```bash
git clone https://github.com/bhhoang/auto-setup-mcsv-script.git
cd auto-setup-mcsv-script
```

2. Make the script executable:

```bash
chmod +x server-setup.sh
```

3. Run full setup (default):

```bash
./server-setup.sh
```

4. Start the server:

```bash
cd server2
./run.sh
```

---

## Usage

```bash
./server-setup.sh [all|plugins]
```

### `all` (default)

Runs the full setup:

- Installs local Java into `SERVER_DIR/java`
- Downloads Paper server jar into `SERVER_DIR/paper.jar`
- Downloads plugins into `SERVER_DIR/plugins/`
- Writes `SERVER_DIR/run.sh`
- Writes `SERVER_DIR/eula.txt` with `eula=true` (if missing)

Example:

```bash
./server-setup.sh all
```

### `plugins`

Only downloads/updates plugins from the `PLUGINS` list.

Example:

```bash
./server-setup.sh plugins
```

---

## Configuration (environment variables)

You can override defaults by setting environment variables when running the script.

### `SERVER_DIR`

Server directory to create/use.

- Default: `server2`

Example:

```bash
SERVER_DIR=my-server ./server-setup.sh
```

### `MINECRAFT_VERSION`

Minecraft version to target.

- Default: `latest`
- If set to a specific version (example: `1.21.4`), the script will try to find a **STABLE** Paper build for that version.
- If it can’t find a stable build for that version, it falls back to finding the latest stable build across all versions.

Example:

```bash
MINECRAFT_VERSION=1.21.4 ./server-setup.sh
```

### `PAPER_JAR`

Paper jar filename to write inside `SERVER_DIR`.

- Default: `paper.jar`

Example:

```bash
PAPER_JAR=paper-1.21.4.jar ./server-setup.sh
```

---

## What the script generates

Assuming default config (`SERVER_DIR=server2`):

```text
server2/
  paper.jar
  run.sh
  eula.txt
  java/
    bin/java
    ...
  plugins/
    LuckPerms.jar
    CoreProtect.jar
    Floodgate.jar
    Geyser-Spigot.jar
    SkinsRestorer.jar
    Chunky.jar
    ViaVersion.jar
    TAB.jar
    GSit.jar
    InvSee++.jar
  .bin/
    jq
```

---

## Notes / troubleshooting

- If you want to change the plugin list, edit the `PLUGINS=(...)` array in `server-setup.sh`.
- If plugin downloads fail, rerun:

```bash
./server-setup.sh plugins
```

- The generated `run.sh` uses **16G RAM** by default (`-Xms16G -Xmx16G`). If your server has less memory, edit `server2/run.sh` and lower those values.

---

## Safety

This script downloads and executes third-party software (Java, Paper, plugins). Review `server-setup.sh` before running it in production.
