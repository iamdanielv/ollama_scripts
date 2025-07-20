# Ollama & OpenWebUI Setup

This repository provides utilities to setup Ollama and OpenWebUI.

## Prerequisites 🛠️

* **Docker:** [https://docs.docker.com/get-docker/](https://docs.docker.com/get-docker/) for OpenWebUI

## Ollama Installation 📦

Run the Ollama Installation Script:

```bash
./installollama.sh
```

The script will:

* Check pre-req's
* Install Ollama (if not already installed)
* Check the version of Ollama, and update if newer version is available
* Verify the service is running

## Restarting Ollama 🔄

If Ollama goes into a weird state, you can restart it with:

```bash
./restartollama.sh
```

This script will:

* Stop the ollama service
* Reset NVIDIA UVM (if NVIDIA GPU is detected).
* Start the ollama service
* Verify the service is running

## Stopping Ollama 🛑

If you need to stop the Ollama service:

```bash
./stopollama.sh
```

## Ollama Update

Run the `./installollama.sh` script to update ollama. It will automatically check for the latest version and download it if needed.

## Starting OpenWebUI 🌐

```bash
./openwebui/startopenwebui.sh
```

This script will:

* Use docker compose to run the OpenWebUI containers in detached mode
* Wait for the service to start and print out a link to the UI

### Environment Configuration (`.env`)

You can create a `.env` file inside the `openwebui/` directory to configure ports. The start script will automatically load it.

Example `.env` file:

``` shell
OPEN_WEBUI_PORT=8080
OLLAMA_PORT=11435
```

## OpenWebUI Configuration ⚙️

The Docker Compose file (`docker-compose.yaml`) defines the services:

* `open-webui`:  Runs the OpenWebUI application using a Docker image.
* `host.docker.internal:host-gateway`:  Allows OpenWebUI to access network resources from within the Docker container.

> [!TIP]
> On first run you have to create an account.
> You may have to configure the `Settings` -> `Connections`.
>
> Use `http://localhost:11434/v1` for the Ollama Server URL. If you have configured a custom `OLLAMA_PORT`, use that port instead.

## Troubleshooting

* **Container Not Starting:**
  * Check your Docker logs: `docker logs <container_id>`
  * Ensure you have sufficient resources (CPU, memory) available.
  * Verify the Docker Compose configuration file (`docker-compose.yaml`) is correct.
* **OpenWebUI can't access the Ollama Models:**
  * Make sure the firewall isn't blocking the port (3000).
  * Try `host.docker.internal` instead of `localhost` in the connection config.

## For Contributors 🤝

* I'm open and encourage contributions of bug fixes, improvements, and documentation!

## License 📜

This project is licensed under the MIT License.  See the `LICENSE` file for details.

## Contact 📧

Let me know if you have any questions. I can be reached at [@IAmDanielV](https://twitter.com/IAmDanielV) or [@iamdanielv.bsky.social](https://bsky.app/profile/iamdanielv.bsky.social).
