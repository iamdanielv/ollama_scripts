# Ollama & OpenWebUI Management Scripts

This repository provides a set of simple shell scripts to install, manage, and run Ollama and OpenWebUI on a Linux system with `systemd`. These scripts aim to simplify the setup process and ensure a consistent environment.

## Quick Start 🚀

To get up and running quickly:

> [!IMPORTANT]
> During installation, the script will prompt you to configure Ollama for network access. This is **required** for OpenWebUI (in Docker) to connect to it.

1. **Install/Update Ollama:**

   ```bash
   ./install-ollama.sh
   ```

2. **Start OpenWebUI:**

   ```bash
   ./openwebui/start-openwebui.sh
   ```

   After it starts, open the link provided (usually `http://localhost:3000`) and follow the on-screen instructions to create an account.

---
---

## Scripts Overview

### General Scripts

| Script | Description |
|---|---|
| `./check-status.sh` | Checks the status of both the Ollama service and the OpenWebUI containers. |

### Ollama Management Scripts

| Script | Description |
|---|---|
| `./install-ollama.sh` | Installs or updates Ollama. Can also be run with `--version` to check for updates without installing. |
| `./logs-ollama.sh` | A convenient wrapper to view the Ollama service logs using `journalctl`. |
| `./restart-ollama.sh` | Sometimes on wake from sleep, the `ollama` service will go into an inconsistent state. This script stops, resets GPU state (if applicable), and restarts the Ollama service using `systemd`. |
| `./stop-ollama.sh` | Stops the Ollama service. |
| `./config-ollama-net.sh` | Configures Ollama network access. Can be run interactively or with flags (`--expose`, `--restrict`, `--view`). |

### OpenWebUI Management Scripts

| Script | Description |
|---|---|
| `./openwebui/start-openwebui.sh` | Starts the OpenWebUI Docker containers in detached mode. |
| `./openwebui/stop-openwebui.sh`  | Stops the OpenWebUI Docker containers. |
| `./openwebui/update-openwebui.sh`  | Pulls the latest Docker images for OpenWebUI. If new images are downloaded, it will prompt you to restart the service. |

---
---

## Prerequisites

- **curl:** Required by the Ollama installer.
- **Docker:** Required for running OpenWebUI. See [Docker installation docs](https://docs.docker.com/get-docker/) for instructions.
- **Docker Compose:** Required for running OpenWebUI containers.
- **systemd:** The Ollama management scripts (`stop-ollama.sh`, `restart-ollama.sh`) are designed for Linux systems using `systemd`. They will not work on systems without it (e.g., macOS or WSL without systemd enabled).

> [!NOTE]
> Most of these scripts require `sudo` to manage system services or write to protected directories. They will automatically prompt for a password if needed.

> [!WARNING]
> The Ollama management scripts will not work on systems without `systemd` (e.g., standard macOS or WSL distributions).

---
---

## Ollama Management

## Install or Update Ollama 📦

The `install-ollama.sh` script handles both initial installation and updates.

```bash
./install-ollama.sh
```

The script will:

- Check pre-req's
- Install Ollama (if not already installed)
- Check the current version and update if a newer one is available.
- Verify that the `ollama` service is running.
- **Prompt you to configure Ollama for network access.** This is **required** for OpenWebUI (in Docker) to connect to it. Please say **Yes (y)** when asked.

### Available Flags

The installer can also be run with flags for specific actions:

| Flag | Alias | Description |
|---|---|---|
| `--version` | `-v` | Displays the currently installed version and checks for the latest available version on GitHub without running the full installer. |
| `--test` | `-t` | Runs internal self-tests for script functions. |
| `--help` | `-h` | Shows the help message. |

**Example:**

```bash
$ ./install-ollama.sh --version
-------------------------------------------------------------------------------
 Ollama Version
-------------------------------------------------------------------------------
  [i] Installed: 0.9.6
  [i] Latest:    0.9.6
```

### Network Access for Docker

By default, Ollama only listens for requests from the local machine (`localhost`). For OpenWebUI (running in a Docker container) to connect to Ollama, the Ollama service must be configured to listen on all network interfaces (`0.0.0.0`).

The `install-ollama.sh` script will detect if this is needed and prompt you to apply this configuration automatically. This is the recommended way to set it up.

### Changing Network Configuration ⚙️ 🌐

If you need to change the network setting after the initial installation, you can use the dedicated configuration script:

```bash
./config-ollama-net.sh
```

This script provides an interactive menu to switch between exposing Ollama to the network or restricting it to localhost.

It can also be run non-interactively with the following flags:

| Flag | Alias | Description |
|---|---|---|
| `--expose` | `-e` | Exposes Ollama to the network. |
| `--restrict` | `-r` | Restricts Ollama to localhost. |
| `--view` | `-v` | Displays the current network configuration. |
| `--help` | `-h` | Shows the help message. |

This script requires `sudo` for modifications and will prompt for it if necessary.

## Restarting Ollama 🔄

If Ollama becomes unresponsive or encounters issues, you can use the restart script.

```bash
./restart-ollama.sh
```

This script will:

- Stop the Ollama service.
- Reset NVIDIA UVM (if a GPU is detected) to clear potential hardware state issues.
- Restart the Ollama service using `systemd`.

## Stopping Ollama 🛑

To stop the Ollama service:

```bash
./stop-ollama.sh
```

> [!NOTE]
> The `restart-ollama.sh` and `stop-ollama.sh` scripts require `sudo` to manage the systemd service. They will automatically attempt to re-run themselves with `sudo` if needed.

## Viewing Ollama Logs 📜

To view and search the logs for the `ollama` service, you can use the `logs-ollama.sh` script. This is particularly useful for debugging.

This script is a simple wrapper that passes arguments directly to `journalctl -u ollama.service`.

- **View all logs (searchable):**

  ```bash
  ./logs-ollama.sh
  ```

- **Show logs since a specific time:**

  ```bash
  ./logs-ollama.sh --since "1 hour ago"
  ```

Press `Ctrl+C` to stop following the logs. This script is a simple wrapper and requires a `systemd`-based system.

---
---

## OpenWebUI Management

## Starting OpenWebUI 🌐

```bash
./openwebui/start-openwebui.sh
```

This script uses `docker-compose` to run the OpenWebUI container in detached mode and prints a link (usually `http://localhost:3000`) to the UI once it's ready.

## OpenWebUI First-Time Setup ⚙️

On your first visit, OpenWebUI will prompt you to create an administrator account. The connection to your local Ollama instance is configured automatically.
This works because the included Docker Compose file tells OpenWebUI to connect to `http://host.docker.internal:11434`, and the `install-ollama.sh` script helps configure the host's Ollama service to accept these connections.

## Stopping OpenWebUI 🛑

To stop the OpenWebUI containers:

```bash
./openwebui/stop-openwebui.sh
```

## Updating OpenWebUI ⬆️

To update OpenWebUI to the latest version, you can pull the newest container images.

```bash
./openwebui/update-openwebui.sh
```

This script runs `docker compose pull` to download the latest images. After the pull is complete, simply restart OpenWebUI by running the start script again. It will automatically use the new images.

```bash
./openwebui/start-openwebui.sh
```

## Configuration 🛠️

To customize the ports, create a `.env` file in the `openwebui/` directory. The start script will automatically load it.

**Example `openwebui/.env` file:**

```env
# Sets the host port for the OpenWebUI interface.
# The default is 3000.
OPEN_WEBUI_PORT=8080

# Sets the port your Ollama instance is running on.
# This is used to connect OpenWebUI to Ollama.
# The default is 11434
OLLAMA_PORT=11434
```

The Docker Compose file (`docker-compose.yaml`) is pre-configured to use these environment variables.

---
---

## Troubleshooting

- **Container Not Starting:**
  - Check Docker logs for errors. In the `openwebui/` directory, run: `docker compose logs --tail 50`
  - Ensure Docker has sufficient resources (CPU, memory).
- **OpenWebUI Can't Access Ollama Models:**
  - This usually means the Ollama service on your host machine is not accessible from inside the Docker container.
  - **Solution:** Run the network configuration script and choose to expose Ollama to the network:

    ```bash
    ./config-ollama-net.sh
    ```

  - This script configures Ollama to listen on all network interfaces, which is required for Docker to connect.
  - Alternatively, re-running the installer (`./install-ollama.sh`) will also detect this and prompt you to fix it.
  - **Also check:** Ensure your firewall is not blocking traffic on port `11434` (or your custom `OLLAMA_PORT`). For example, on Ubuntu, you might run `sudo ufw allow 11434`.

## Tips 💡

- **DEBUG OLLAMA**:
  - To easily view the `ollama` service logs in real-time, use the dedicated script:

    ```bash
    ./logs-ollama.sh
    ```

  - This is helpful for debugging issues with the service itself. See the script's documentation above for more options, like viewing a specific number of past lines.

- **DEBUG OPENWEBUI**:
  - To see the logs being generated by docker-compose, you can use the `-f` flag with the docker-compose command. This allows you to follow the logs in real-time, which can be helpful for debugging issues.
  - For example:

    ```bash
    docker compose logs -f
    ```

---
---

## For Contributors 🤝

I'm open to and encourage contributions of bug fixes, improvements, and documentation!

## License 📜

This project is licensed under the MIT License. See the `LICENSE` file for details.

## Contact 📧

Let me know if you have any questions. I can be reached at [@IAmDanielV](https://twitter.com/IAmDanielV) or [@iamdanielv.bsky.social](https://bsky.app/profile/iamdanielv.bsky.social).
