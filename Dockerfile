# code-server (VS Code in the browser) on a Debian base, bundled with a shared,
# system-wide polyglot toolchain: Node.js, Python, Bun, Go, Rust, Java (JDK),
# and Flutter (which bundles its own Dart; web/desktop targets).
#
# Everything is installed to system paths (/usr/local/*, /usr/lib) and exported
# on PATH below, and the same PATH is written to /etc/profile.d so interactive
# editor terminals inherit it too.
#
# Reference: https://github.com/EscuelaTecnicaHenryFord/code-server-docker
#
# Workspace files live in /workspace — code-server's workspace — mounted in at
# runtime via docker-compose.yml.

FROM debian:trixie-slim

# ---------------------------------------------------------------------------
# System packages: C/C++ build toolchain, Python, JDK, utilities.
# ---------------------------------------------------------------------------
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates curl wget git gnupg unzip zip xz-utils xclip ripgrep \
        build-essential gdb valgrind clang cmake ninja-build \
        clang-format clang-tidy clangd lldb lld \
        gcc g++ make pkg-config ccache autoconf automake libtool \
        python3 python3-pip python3-venv \
        default-jdk-headless libglu1-mesa \
        apt-transport-https \
    && rm -rf /var/lib/apt/lists/*

# GitHub CLI (gh) from GitHub's official apt repository.
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends gh \
    && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# System-wide language toolchains. Installed under /usr/local/* and /usr/lib,
# all exported on PATH. JAVA_HOME uses Debian's version-agnostic default-java
# symlink so it tracks whatever JDK `default-jdk-headless` provides.
# ---------------------------------------------------------------------------
ENV CARGO_HOME=/usr/local/cargo \
    RUSTUP_HOME=/usr/local/rustup \
    BUN_INSTALL=/usr/local/bun \
    GOROOT=/usr/local/go \
    GOPATH=/usr/local/gopath \
    JAVA_HOME=/usr/lib/jvm/default-java \
    FLUTTER_HOME=/usr/local/flutter \
    PATH=/usr/local/go/bin:/usr/local/gopath/bin:/usr/local/cargo/bin:/usr/local/bun/bin:/usr/local/flutter/bin:/usr/local/bin:$PATH

# Node.js (Active LTS) + sharp, installed system-wide via NodeSource.
RUN curl -fsSL https://deb.nodesource.com/setup_24.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/* \
    && npm install -g sharp pnpm

# AI coding CLIs, installed system-wide via npm: Claude Code (Anthropic) and
# Codex (OpenAI). Both land on PATH as `claude` and `codex`.
RUN npm install -g @anthropic-ai/claude-code @openai/codex

# Bun (latest) into BUN_INSTALL, made readable/executable for all users.
RUN curl -fsSL https://bun.sh/install | bash \
    && chmod -R a+rX /usr/local/bun

# Rust (latest stable) via rustup, world-readable so any user can use it.
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
        | sh -s -- -y --no-modify-path --default-toolchain stable \
    && chmod -R a+rwX /usr/local/cargo /usr/local/rustup

# Go (latest) — resolve the current version from the official endpoint so it
# stays up to date on rebuild rather than pinning a stale tarball. The arch is
# detected (dpkg's amd64/arm64 names match Go's tarball naming) so it works on
# both x86_64 and arm64 hosts.
RUN GO_VERSION="$(curl -fsSL https://go.dev/VERSION?m=text | head -n1)" \
    && GO_ARCH="$(dpkg --print-architecture)" \
    && curl -fsSL "https://go.dev/dl/${GO_VERSION}.linux-${GO_ARCH}.tar.gz" -o /tmp/go.tar.gz \
    && tar -C /usr/local -xzf /tmp/go.tar.gz \
    && rm /tmp/go.tar.gz \
    && mkdir -p "$GOPATH"

# Flutter (latest stable) via the official git channel; bundles its own Dart, so
# `dart` and `flutter` both land on PATH. World-readable so any user can run it.
# A single `flutter --version` bootstraps the bundled Dart SDK at build time.
RUN git clone --depth 1 -b stable https://github.com/flutter/flutter.git "$FLUTTER_HOME" \
    && git config --system --add safe.directory "$FLUTTER_HOME" \
    && "$FLUTTER_HOME/bin/flutter" --suppress-analytics --version \
    && chmod -R a+rwX "$FLUTTER_HOME"

# Make the shared toolchain visible to interactive (login) shells in the
# code-server terminal, mirroring the ENV PATH above.
RUN printf 'export CARGO_HOME=%s\nexport RUSTUP_HOME=%s\nexport BUN_INSTALL=%s\nexport GOROOT=%s\nexport GOPATH=%s\nexport JAVA_HOME=%s\nexport FLUTTER_HOME=%s\nexport PATH=%s\n' \
        "$CARGO_HOME" "$RUSTUP_HOME" "$BUN_INSTALL" "$GOROOT" "$GOPATH" \
        "$JAVA_HOME" "$FLUTTER_HOME" "$PATH" \
        > /etc/profile.d/dev-toolchain.sh

# ---------------------------------------------------------------------------
# code-server (latest) + editor extensions for the bundled languages.
# Extensions install under $HOME so they are found at runtime (HOME=/root).
# ---------------------------------------------------------------------------
ENV HOME=/root
RUN curl -fsSL https://code-server.dev/install.sh | sh

RUN for ext in \
        ms-python.python \
        ms-vscode.cpptools \
        golang.go \
        rust-lang.rust-analyzer \
        Dart-Code.dart-code \
        Dart-Code.flutter \
        astro-build.astro-vscode \
        GitHub.copilot ; do \
        code-server --install-extension "$ext" || true ; \
    done

# 8081 code-server (VS Code web UI, HTTP)
EXPOSE 8081

# code-server reads its login password from the PASSWORD env var (passed in at
# runtime). Opens /workspace as the workspace, served over plain HTTP on 8081.
CMD ["code-server", "--bind-addr", "0.0.0.0:8081", "--auth", "password", "/workspace"]
