# Ollama & OpenWebUI Management Scripts

This repository provides a set of simple shell scripts to install, manage, and run Ollama and OpenWebUI on a Linux system with `systemd`.

## Quick Start 🚀

To get up and running quickly:

1. **Install/Update Ollama:**

    ```bash
    ./installollama.sh
    ```

    > [!IMPORTANT]
    > During installation, the script will ask to configure Ollama for network access. This is **required** for OpenWebUI to connect to it.

2. **Start OpenWebUI:**

    ```bash
    ./openwebui/startopenwebui.sh
    ```

    After it starts, open the link provided (usually `http://localhost:3000`) and follow the on-screen instructions to create an account.

---
---

## Scripts Overview

| Script | Description |
|---|---|
| `./installollama.sh` | Installs or updates Ollama and configures it for network access. |
| `./restartollama.sh` | Stops, resets GPU state (if applicable), and restarts the Ollama service. |
| `./stopollama.sh` | Stops the Ollama service. |
| `./openwebui/startopenwebui.sh` | Starts the OpenWebUI Docker containers. |
| `./openwebui/stopopenwebui.sh` | Stops the OpenWebUI Docker containers. |
| `./openwebui/updateopenwebui.sh` | Pulls the latest Docker images for OpenWebUI. |

---
---

## Prerequisites

- **curl:** Required by the Ollama installer.
- **Docker:** Required for running OpenWebUI. See [Docker installation docs](https://docs.docker.com/get-docker/).
- **systemd:** The Ollama management scripts (`stopollama.sh`, `restartollama.sh`) are designed for Linux systems using `systemd`. They will not work on systems without it (e.g., macOS or WSL without systemd enabled).

> [!WARNING]
> The Ollama management scripts will not work on systems without `systemd` (e.g., standard macOS or WSL distributions).

---
---

## Ollama Management

## Install or Update Ollama 📦

The `installollama.sh` script handles both initial installation and updates.

```bash
./installollama.sh
```

The script will:

- Check pre-req's
- Install Ollama (if not already installed)
- Check the current version and update if a newer one is available.
- Verify the `ollama` service is running.
- **Prompt you to configure Ollama for network access.** This is required for OpenWebUI (in Docker) to connect to it. Please say **Yes (y)** when asked.

### Network Access for Docker

By default, Ollama only listens for requests from the local machine (`localhost`). For OpenWebUI (running in a Docker container) to connect to Ollama, the Ollama service must be configured to listen on all network interfaces (`0.0.0.0`).

The `installollama.sh` script will detect if this is needed and prompt you to apply this configuration automatically. This is the recommended way to set it up.

## Restarting Ollama 🔄

If Ollama becomes unresponsive or encounters issues, you can use the restart script.

```bash
./restartollama.sh
```

This script will stop the service, reset NVIDIA UVM (if a GPU is detected) to clear potential hardware state issues, and restart the service.

## Stopping Ollama 🛑

To stop the Ollama service:

```bash
./stopollama.sh
```

> [!NOTE]
> The `restartollama.sh` and `stopollama.sh` scripts require `sudo` to manage the systemd service. They will automatically attempt to re-run themselves with `sudo` if needed.

---
---

## OpenWebUI Management

## Starting OpenWebUI 🌐

```bash
./openwebui/startopenwebui.sh
```

This script uses `docker-compose` to run the OpenWebUI container in detached mode and prints a link (usually `http://localhost:3000`) to the UI once it's ready.

## OpenWebUI First-Time Setup ⚙️

On your first visit, OpenWebUI will prompt you to create an administrator account. The connection to your local Ollama instance is configured automatically.
This works because the included Docker Compose file tells OpenWebUI to connect to `http://host.docker.internal:11434`, and the `installollama.sh` script helps configure the host's Ollama service to accept these connections.

## Stopping OpenWebUI 🛑

To stop the OpenWebUI containers:

```bash
./openwebui/stopopenwebui.sh
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
# The default is 11434.
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
  - **Solution:** Run the `./installollama.sh` script. It will prompt you to configure Ollama to listen on all network interfaces, which resolves this issue.
  - **Verification:** The `docker-compose.yaml` is pre-configured to connect to Ollama at `http://host.docker.internal:11434`. Ensure your firewall is not blocking traffic on port `11434` (or your custom `OLLAMA_PORT`).

---
---

## For Contributors 🤝

I'm open to and encourage contributions of bug fixes, improvements, and documentation!

## License 📜

This project is licensed under the MIT License. See the `LICENSE` file for details.

## Contact 📧

Let me know if you have any questions. I can be reached at [@IAmDanielV](https://twitter.com/IAmDanielV) or [@iamdanielv.bsky.social](https://bsky.app/profile/iamdanielv.bsky.social).
