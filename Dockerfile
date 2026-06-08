# code-server (VS Code in the browser) on a PHP 8.4 base, bundled with a shared,
# system-wide polyglot toolchain: Node.js, Python, Bun, Go, Rust, Java (JDK 17),
# and Flutter (which bundles its own Dart). Android development is supported via
# Google's `android` CLI; the Android SDK is pulled on demand (see README) to
# keep the image lean.
#
# The code-server terminal and PHP CLI use the SAME binaries — everything is
# installed to system paths (/usr/local/*, /usr/lib) and exported on PATH below,
# and the same PATH is written to /etc/profile.d so interactive editor terminals
# inherit it too.
#
# Reference: https://github.com/EscuelaTecnicaHenryFord/code-server-docker
#
# Workspace files live in /workspace — code-server's workspace — mounted in at
# runtime via docker-compose.yml.

FROM php:8.4-apache

# ---------------------------------------------------------------------------
# System packages: C/C++ build toolchain, Python, supervisor, utilities.
# ---------------------------------------------------------------------------
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates curl wget git gnupg unzip zip xz-utils xclip \
        supervisor \
        build-essential gdb valgrind clang cmake ninja-build \
        python3 python3-pip python3-venv \
        openjdk-17-jdk-headless libglu1-mesa \
        apt-transport-https \
    && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# PHP extensions: Imagick + GD (with Freetype/JPEG/PNG/WebP support).
# ---------------------------------------------------------------------------
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        libmagickwand-dev \
        libfreetype6-dev libjpeg62-turbo-dev libpng-dev libwebp-dev \
        libonig-dev libxml2-dev libfontconfig1-dev \
    && pecl install imagick \
    && docker-php-ext-enable imagick \
    && docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp \
    && docker-php-ext-install -j"$(nproc)" gd \
    && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# System-wide language toolchains (shared by PHP and code-server).
# Installed under /usr/local/* and /usr/lib, all exported on PATH.
# ---------------------------------------------------------------------------
ENV CARGO_HOME=/usr/local/cargo \
    RUSTUP_HOME=/usr/local/rustup \
    BUN_INSTALL=/usr/local/bun \
    GOROOT=/usr/local/go \
    GOPATH=/usr/local/gopath \
    JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 \
    FLUTTER_HOME=/usr/local/flutter \
    ANDROID_HOME=/usr/local/android-sdk \
    ANDROID_SDK_ROOT=/usr/local/android-sdk \
    PATH=/usr/local/go/bin:/usr/local/gopath/bin:/usr/local/cargo/bin:/usr/local/bun/bin:/usr/local/flutter/bin:/usr/local/android-sdk/cmdline-tools/latest/bin:/usr/local/android-sdk/platform-tools:/usr/local/bin:$PATH

# Node.js (Active LTS) + sharp, installed system-wide via NodeSource.
RUN curl -fsSL https://deb.nodesource.com/setup_24.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/* \
    && npm install -g sharp

# Bun (latest) into BUN_INSTALL, made readable/executable for all users.
RUN curl -fsSL https://bun.sh/install | bash \
    && chmod -R a+rX /usr/local/bun

# Rust (latest stable) via rustup, world-readable so any user can use it.
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
        | sh -s -- -y --no-modify-path --default-toolchain stable \
    && chmod -R a+rwX /usr/local/cargo /usr/local/rustup

# Go (latest) — resolve the current version from the official endpoint so it
# stays up to date on rebuild rather than pinning a stale tarball.
RUN GO_VERSION="$(curl -fsSL https://go.dev/VERSION?m=text | head -n1)" \
    && curl -fsSL "https://go.dev/dl/${GO_VERSION}.linux-amd64.tar.gz" -o /tmp/go.tar.gz \
    && tar -C /usr/local -xzf /tmp/go.tar.gz \
    && rm /tmp/go.tar.gz \
    && mkdir -p "$GOPATH"

# Flutter (latest stable) via the official git channel; bundles its own Dart, so
# `dart` and `flutter` both land on PATH. World-readable so any user can run it.
# A single `flutter --version` bootstraps the bundled Dart SDK at build time.
RUN git clone --depth 1 -b stable https://github.com/flutter/flutter.git "$FLUTTER_HOME" \
    && git config --system --add safe.directory "$FLUTTER_HOME" \
    && "$FLUTTER_HOME/bin/flutter" --suppress-analytics config --android-sdk "$ANDROID_HOME" \
    && "$FLUTTER_HOME/bin/flutter" --suppress-analytics --version \
    && chmod -R a+rwX "$FLUTTER_HOME"

# Android CLI (latest) via Google's apt repository — the agent-centric tool for
# managing the SDK, projects and devices. The SDK itself is NOT baked in (it is
# multi-GB); provision it on demand with `android sdk install ...` — it persists
# in the android-sdk volume. See README. ANDROID_HOME is created as the mount
# point so Flutter's --android-sdk path resolves.
RUN wget -qO- https://dl.google.com/linux/linux_signing_key.pub \
        | gpg --dearmor -o /usr/share/keyrings/google-android.gpg \
    && echo 'deb [signed-by=/usr/share/keyrings/google-android.gpg arch=amd64] http://dl.google.com/android/cli/latest/debian/ stable main' \
        > /etc/apt/sources.list.d/android-cli.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends android-cli \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p "$ANDROID_HOME"

# Make the shared toolchain visible to interactive (login) shells in the
# code-server terminal, mirroring the ENV PATH above.
RUN printf 'export CARGO_HOME=%s\nexport RUSTUP_HOME=%s\nexport BUN_INSTALL=%s\nexport GOROOT=%s\nexport GOPATH=%s\nexport JAVA_HOME=%s\nexport FLUTTER_HOME=%s\nexport ANDROID_HOME=%s\nexport ANDROID_SDK_ROOT=%s\nexport PATH=%s\n' \
        "$CARGO_HOME" "$RUSTUP_HOME" "$BUN_INSTALL" "$GOROOT" "$GOPATH" \
        "$JAVA_HOME" "$FLUTTER_HOME" "$ANDROID_HOME" "$ANDROID_SDK_ROOT" "$PATH" \
        > /etc/profile.d/dev-toolchain.sh

# ---------------------------------------------------------------------------
# code-server (latest) + editor extensions for the bundled languages.
# Extensions install under $HOME so they are found at runtime (HOME=/root).
# ---------------------------------------------------------------------------
ENV HOME=/root
RUN curl -fsSL https://code-server.dev/install.sh | sh

RUN for ext in \
        DEVSENSE.phptools-vscode \
        junstyle.php-cs-fixer \
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

COPY supervisord.conf /etc/supervisord.conf

# 8081 code-server (VS Code web UI, HTTP)
EXPOSE 8081

ENTRYPOINT ["supervisord", "-c", "/etc/supervisord.conf"]
