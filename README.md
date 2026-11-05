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

The rules are applied once, at container start, relative to the container's working directory (`$PWD`): the entrypoint reads `.opencode-mask` from that directory, so `working_dir` determines which mask file is used.

- **Web mode**: the compose service sets `working_dir: /workspace` and bind-mounts `.opencode-mask-workspace` to `/workspace/.opencode-mask`. Mask paths are therefore relative to `/workspace`, that is, to the mounted project directories (`project-foo/.env`, `project-bar/.git/`, ...).
- **ACP mode**: the launcher mounts your project at the same absolute path and sets it as the working directory, so the project's own `.opencode-mask` is applied.

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
| `.opencode-mask` | Mask file for ACP mode / a project root (the example is for this repository). |
| `.opencode-mask-workspace` | Mask file for web mode, mounted as `/workspace/.opencode-mask`; paths are relative to `/workspace`. |
| `docker-compose/.env.example`, `opencode-acp/.acp.env.example` | Templates copied to `.env` / `.acp.env` by the `Makefile` (the real files are git-ignored). |
| `Makefile` | Builds the image, runs web mode, installs the ACP launcher script. |
| `shell.nix`, `.envrc` | Nix development shell. |

## Web mode

1. `make compose_env` creates `docker-compose/.env` from `.env.example` (it is also created automatically as a dependency of the other targets). Adjust `HOME_DIR`, `HTTP_PROXY`/`NO_PROXY` and the image name/version.
2. The web mode scenario is comparing two projects and porting changes from one to the other, so uncomment both project mounts in `docker-compose/docker-compose.yml`:

   ```yaml
   volumes:
     - ${HOME_DIR}/project-foo:/workspace/project-foo
     - ${HOME_DIR}/project-bar:/workspace/project-bar
   ```

3. Define masking rules in `.opencode-mask-workspace` in the repository root — paths are relative to `/workspace`:

   ```
   project-foo/.env
   project-bar/.git/
   ```

   The file is mounted as `/workspace/.opencode-mask`, so the entrypoint applies it at container start.

   **Note:** `.opencode-mask-workspace` must exist before `make compose_up`; if it is missing, Docker creates a directory at the mount target and masking silently does not apply.

4. Build and start:

   ```
   make compose_up
   ```

   or, to also install the ACP launcher script:

   ```
   make all
   ```

5. Open http://localhost:3000 and add providers through the web UI.

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

- preferred: bind the listener to a virtual interface the container can reach, or reuse the listener already created by your proxy client (for example a tun interface — the `198.18.0.1` address used in the examples above). Specify that address in `HTTP_PROXY`/`HTTPS_PROXY` in `docker-compose/.env` and/or `opencode-acp/.acp.env`;
- a listener bound to `127.0.0.1` is not reachable from the container at all;
- listening on `0.0.0.0` also works, but is not recommended: without a properly configured firewall it exposes the proxy to the whole local network;
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
