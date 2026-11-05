# opencode-mask

Docker environment for running [OpenCode](https://opencode.ai) with files and directories hidden from the agent.

Requires Docker with the Compose v2 plugin.

## Motivation

OpenCode lets you restrict file access through permissions in `opencode.json` or plugins such as `opencode-ignore`. However, this kind of protection only covers OpenCode's own tools: the agent can still execute shell commands (`grep`, `cat`, ...) via `bash` and read secrets directly from disk.

`opencode-mask` hides files at the filesystem level before OpenCode starts:

- a masked **file** is bind-mounted over `/dev/null` — reading it returns nothing, writes are discarded;
- a masked **directory** is covered with an empty read-only tmpfs (`ro,mode=000`) — it appears empty and cannot be listed or entered.

Secrets therefore remain inaccessible even to commands the agent runs inside the container. This repository masks its own secrets: `.opencode-mask` in the root hides `.direnv`, `volumes/`, `docker-compose/.env` and `opencode-acp/.acp.env`.

## How it works

`opencode/mask-entrypoint.sh` is the container entrypoint. On startup it reads `.opencode-mask` from the container's working directory and applies the rules before launching `opencode`:

- one path per line, relative to the working directory (a leading `/` is stripped);
- `#` starts a comment; blank lines are ignored;
- paths that do not exist are skipped with a warning;
- a file is bind-mounted over `/dev/null` (best-effort remounted read-only);
- a directory is masked with a read-only tmpfs (`ro,mode=000,size=4k`).

Masking requires the `SYS_ADMIN` capability for `mount`: the ACP launcher passes `--cap-add SYS_ADMIN`, and `docker-compose/docker-compose.yml` does the same.

Example `.opencode-mask` (also present in the repository root):

```
.direnv
volumes/
docker-compose/.env
opencode-acp/.acp.env
```

The rules are applied once, at container start, relative to the container's working directory (`$PWD`). The ACP launcher mounts your project at the same absolute path and sets it as the working directory, so `.opencode-mask` in the project root works as expected. The web service does not set a working directory itself — it is primarily intended for building the image and configuring providers.

### Limitations

The mask file is not a full `.gitignore` implementation:

- no globs (`*`, `?`, `[]`);
- no negation (`!`);
- comments, blank lines and whitespace trimming are supported; everything else is a literal path.

## Project layout

| Path | Description |
|------|-------------|
| `docker-compose/` | Builds the image (`docker-compose.build.yml`) and runs OpenCode in web mode. Providers are added through the web UI. |
| `opencode/` | `Dockerfile` (based on `ghcr.io/anomalyco/opencode:1.19.5` plus `tini` and `util-linux-misc`) and `mask-entrypoint.sh`. |
| `opencode-acp/` | `.acp.env` and `opencode-docker-acp.sh` for running the container in ACP mode, used for editor/IDE integration. A Docker volume keeps provider settings and chat history. |
| `.opencode-mask` | Example mask file at the repository root. |
| `docker-compose/.env.example`, `opencode-acp/.acp.env.example` | Templates copied to `.env` / `.acp.env` by the `Makefile` (the real files are git-ignored). |
| `Makefile` | Builds the image, runs web mode, installs the ACP launcher script. |
| `shell.nix`, `.envrc` | Nix development shell. |

## Web mode

1. `make compose_env` creates `docker-compose/.env` from `.env.example` (it is also created automatically as a dependency of the other targets). Adjust `HOME_DIR`, `HTTP_PROXY`/`NO_PROXY` and the image name/version.
2. To expose a project to the container, uncomment and edit the volume entries in `docker-compose/docker-compose.yml`:

   ```yaml
   volumes:
     - ${HOME_DIR}/project-foo:/workspace/project-foo
   ```

3. Build and start:

   ```
   make compose_up
   ```

   or, to also install the ACP launcher script:

   ```
   make all
   ```

4. Open http://localhost:3000 and add providers through the web UI.

## ACP mode (editors / IDEs)

1. Edit `opencode-acp/.acp.env` (created from `.acp.env.example`) — proxy settings, if needed.
2. Install the launcher script:

   ```
   make acp_install_script
   ```

   This copies `opencode-docker-acp.sh` to `~/.local/bin/opencode-docker-acp.sh`.
3. Configure your editor/IDE to use this script as the OpenCode ACP command. Follow the official documentation: https://opencode.ai/docs/acp/ (Zed, JetBrains IDEs, Avante.nvim, CodeCompanion.nvim).

The launcher:

- runs the container with `--cap-add SYS_ADMIN` (required for masking);
- mounts the current directory at the same absolute path and uses it as the working directory, so the project's `.opencode-mask` is applied;
- mounts the `opencode_opencode` volume at `/root/.local/share/opencode`, which persists provider settings and chat history across runs;
- starts `opencode --print-logs acp`.

## Makefile targets

| Target | Description |
|--------|-------------|
| `compose_env` | Creates `docker-compose/.env` from `.env.example` if missing. |
| `prepare_volumes` | Creates `volumes/opencode` if missing (host directory for the persistent volume). |
| `compose_stop` | Stops the compose services. |
| `compose_down` | Stops and removes the compose services. |
| `compose_reset` | Same as `compose_down`, plus removal of volumes. |
| `compose_up` | Starts the services in the background. |
| `compose_rebuild` | Builds the image via `docker-compose.build.yml`. |
| `compose_up_rebuild` | Stops the services, rebuilds the image and starts them again. |
| `acp_env` | Creates `opencode-acp/.acp.env` from `.acp.env.example` if missing. |
| `acp_install_script` | Installs `opencode-docker-acp.sh` to `~/.local/bin/`. |
| `acp_uninstall_script` | Removes the installed ACP launcher. |
| `all` (default) | `compose_rebuild` + `acp_install_script`. |

Extra arguments can be passed through `ARGS`, for example `make compose_up ARGS="--build"`.

## HTTP proxy

If the agent must reach the internet through a proxy running on the host, the proxy's listening address must be reachable from inside the Docker container:

- make the proxy client listen on `0.0.0.0` (not `127.0.0.1`);
- specify the host's network interface address, or the address of the tun interface created by the proxy client (for example `198.18.0.1` used in the examples), in `HTTP_PROXY`/`HTTPS_PROXY` in `docker-compose/.env` and/or `opencode-acp/.acp.env`;
- add local addresses to `NO_PROXY` (for example `localhost,127.0.0.1`).

## Development (Nix)

A `shell.nix` with development tools (GNU Make; `shellcheck` and `pre-commit` are commented out) is provided for Nix users:

```
nix-shell
```

or, with direnv:

```
direnv allow
```
