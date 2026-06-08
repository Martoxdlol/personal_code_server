# devbox

A self-contained development box in a single Docker image: **code-server**
(VS Code in the browser) on a **PHP 8.4** base, plus a **shared, system-wide
polyglot toolchain** — Node.js, Python, Bun, Go, Rust, Java (JDK 17) and
**Flutter** (which bundles its own Dart) — all at their latest versions.
Android development is supported via Google's `android` CLI.

The code-server terminal and the PHP CLI use the **same** binaries: every
toolchain is installed to system paths and exported on `PATH`. code-server runs
under `supervisord`.

Based on the reference image:
<https://github.com/EscuelaTecnicaHenryFord/code-server-docker>

## Layout

| File                 | Purpose                                                        |
| -------------------- | -------------------------------------------------------------- |
| `Dockerfile`         | Builds PHP + code-server + the polyglot toolchain              |
| `docker-compose.yml` | Runs the container, mounts `src/` + persists the Android SDK    |
| `supervisord.conf`   | Runs the `code-server` process                                 |
| `.env.example`       | Template for the code-server password                          |
| `src/`               | Your workspace files (`/var/www/html`)                         |

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

   > The first build is slow — it compiles the PHP extensions and downloads the
   > full toolchain (Node, Go, Rust, Bun, Flutter, JDK) and the editor extensions.

- Editor: <http://localhost:8081> — log in with `CODE_SERVER_PASSWORD`. It opens
  `/var/www/html` (the same `src/` folder), so edits show up immediately.

## Android / Flutter

To keep the image lean, the **Android SDK is not baked in** — only the `android`
CLI, the JDK and Flutter are. Provision the SDK once from a terminal (it lands in
`$ANDROID_HOME` = `/usr/local/android-sdk`, a named volume, so it persists):

```bash
# Install the components you need (versions are examples — pick current ones)
android sdk install platform-tools build-tools/36.0.0 platforms/android-36 cmdline-tools/latest

# Accept the SDK licenses (non-interactive)
yes | flutter doctor --android-licenses

# Verify the toolchain
flutter doctor
```

Flutter is wired to this SDK at build time (`flutter config --android-sdk`), and
`dart`/`flutter` are already on `PATH`. Flutter **web/desktop** builds work out
of the box; **Android** builds need the one-time provisioning above.

> ⚠️ The **emulator is not included** and generally won't run in a container
> (it needs `/dev/kvm` / nested virtualization). Building APKs/AABs works fine;
> run/debug on a physical device or a host-side emulator instead.

## Adding your files

Put your files into `src/`. The folder is bind-mounted as code-server's
workspace, so edits apply immediately — no rebuild or restart needed:

```
src/
└── ...your files...
```

To bake files into the image instead (immutable deploys), `COPY src/ /var/www/html/`
in the `Dockerfile` and remove the `volumes:` entry from `docker-compose.yml`.

## What's installed

| Tool         | Version source                | Notes                                            |
| ------------ | ----------------------------- | ------------------------------------------------ |
| PHP 8.4      | base image (`php:8.4-apache`) | CLI; available on `PATH`                         |
| Imagick      | PECL (latest)                 | Built against `libmagickwand`                    |
| GD           | bundled with PHP              | Configured with Freetype/JPEG/PNG/WebP           |
| Node.js      | NodeSource (Active LTS, v24)  | System-wide; `sharp` installed globally          |
| Python 3     | Debian apt (latest)           | `python3` + `pip` + `venv`                       |
| Bun          | official installer (latest)   | `/usr/local/bun`                                 |
| Go           | go.dev (resolved latest)      | `/usr/local/go`; version fetched live at build   |
| Rust         | rustup (latest stable)        | `/usr/local/cargo`, world-readable               |
| Java (JDK 17)| Debian apt (`openjdk-17`)     | Headless; required by Gradle/Android builds      |
| Flutter      | git `stable` branch (latest)  | `/usr/local/flutter`; bundles its own `dart`     |
| Android CLI  | Google apt repo (latest)      | `android` tool; SDK provisioned on demand        |
| C / C++      | Debian apt                    | `build-essential`, `clang`, `cmake`, `ninja`     |
| code-server  | official installer (latest)   | HTTP web UI on 8081, password auth, opens workspace |
| supervisord  | Debian apt                    | Runs code-server                                 |

The toolchain `PATH` is set both via `ENV` (for the `supervisord` process) and
via `/etc/profile.d/dev-toolchain.sh` (for interactive editor terminals), so the
same binaries are reachable everywhere.

### A note on versions

Go, Bun, Rust, Flutter, the Android CLI and code-server resolve to the latest
release at build time, so rebuilding picks up newer versions automatically. Node
uses the **Active LTS** (currently v24) via NodeSource for stability; bump the
`setup_NN.x` line in the `Dockerfile` to track a different line (e.g. the Current
release). Dart now comes bundled with Flutter rather than being installed
separately.
