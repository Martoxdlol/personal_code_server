# devbox

A self-contained development box in a single Docker image: **code-server**
(VS Code in the browser) on a **Debian** base, plus a **shared, system-wide
polyglot toolchain** — Node.js, Python, Bun, Go, Rust, Java (JDK) and
**Flutter** (which bundles its own Dart) — all at their latest versions.

Every toolchain is installed to system paths and exported on `PATH`, so the
same binaries are reachable from the code-server terminal.

Based on the reference image:
<https://github.com/EscuelaTecnicaHenryFord/code-server-docker>

## Layout

| File                 | Purpose                                                        |
| -------------------- | -------------------------------------------------------------- |
| `Dockerfile`         | Builds code-server + the polyglot toolchain                    |
| `docker-compose.yml` | Runs the container, mounts `src/` as the workspace             |
| `.env.example`       | Template for the code-server password                          |
| `src/`               | Your workspace files (`/workspace`)                            |

## Ports

code-server is served over plain **HTTP** (no TLS).

| Port (host) | Port (container) | Service                            |
| ----------- | ---------------- | ---------------------------------- |
| 8081        | 8081             | code-server (VS Code web UI, HTTP) |

## Build & run

1. Create the secrets file (sets the code-server password):

   ```bash
   cp .env.example .env
   echo "CODE_SERVER_PASSWORD=$(openssl rand -hex 24)" >> .env
   ```

2. Start it (from this directory):

   ```bash
   docker compose up -d --build
   ```

   > The first build is slow — it downloads the full toolchain (Node, Go, Rust,
   > Bun, Flutter, JDK) and the editor extensions.

- Editor: <http://localhost:8081> — log in with `CODE_SERVER_PASSWORD`. It opens
  `/workspace` (the same `src/` folder), so edits show up immediately.

## Flutter

`flutter` and `dart` are on `PATH` out of the box and target **web and desktop**.
**Android tooling is intentionally not included**: Google's `android` CLI and the
Android build-tools are amd64-only, so they don't work on this arm64 host. For
Android builds, use a dedicated amd64 builder/CI instead.

## Adding your files

Put your files into `src/`. The folder is bind-mounted as code-server's
workspace, so edits apply immediately — no rebuild or restart needed:

```
src/
└── ...your files...
```

To bake files into the image instead (immutable deploys), `COPY src/ /workspace/`
in the `Dockerfile` and remove the `volumes:` entry from `docker-compose.yml`.

## What's installed

| Tool         | Version source                | Notes                                            |
| ------------ | ----------------------------- | ------------------------------------------------ |
| Node.js      | NodeSource (Active LTS, v24)  | System-wide; `sharp` installed globally          |
| Python 3     | Debian apt (latest)           | `python3` + `pip` + `venv`                       |
| Bun          | official installer (latest)   | `/usr/local/bun`                                 |
| Go           | go.dev (resolved latest)      | `/usr/local/go`; version fetched live at build   |
| Rust         | rustup (latest stable)        | `/usr/local/cargo`, world-readable               |
| Java (JDK)   | Debian apt (`default-jdk`)    | Headless (OpenJDK 21 on trixie)                  |
| Flutter      | git `stable` branch (latest)  | `/usr/local/flutter`; bundles its own `dart`     |
| C / C++      | Debian apt                    | `build-essential`, `clang`, `cmake`, `ninja`     |
| code-server  | official installer (latest)   | HTTP web UI on 8081, password auth, opens workspace |

The toolchain `PATH` is set both via `ENV` (for the `code-server` process) and
via `/etc/profile.d/dev-toolchain.sh` (for interactive editor terminals), so the
same binaries are reachable everywhere.

### A note on versions

Go, Bun, Rust, Flutter and code-server resolve to the latest release at build
time, so rebuilding picks up newer versions automatically. Node uses the
**Active LTS** (currently v24) via NodeSource for stability; bump the
`setup_NN.x` line in the `Dockerfile` to track a different line (e.g. the Current
release). Dart comes bundled with Flutter rather than being installed separately.
