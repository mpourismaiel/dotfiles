#!/usr/bin/env python3
# diskrules.py — the rule tables behind the pill's Disk window (diskbridge.py /
# diskscan.py). Data only: what counts as a dependency or build directory, which
# lockfile brings it back, which file extensions are video / archive / …, where
# every known tool keeps its cache and how that cache is cleaned properly.
#
# Nothing here is specific to one machine: paths are resolved at scan time from
# the tool itself, then its environment variable, then the XDG default. To teach
# the scanner a new ecosystem, add a row here — no code changes needed.
#
# Risk tiers used everywhere (the Disk window groups a cleanup plan by them):
#   free   comes back by itself, nothing to do (caches, build output)
#   cost   comes back, but costs a download or build (dependencies, images)
#   state  holds state that is not in any lockfile (volumes, profiles, saves)
#   data   your files — gone means gone

TIERS = ("free", "cost", "state", "data")

# ---- projects -----------------------------------------------------------------
# A project root is the top-most directory holding `.git` or one of these.
MANIFESTS = {
    "package.json": "node",
    "Cargo.toml": "rust",
    "go.mod": "go",
    "pyproject.toml": "python",
    "requirements.txt": "python",
    "setup.py": "python",
    "Pipfile": "python",
    "build.gradle": "gradle",
    "build.gradle.kts": "gradle",
    "settings.gradle": "gradle",
    "settings.gradle.kts": "gradle",
    "pom.xml": "maven",
    "project.godot": "godot",
    "CMakeLists.txt": "cmake",
    "Makefile": "make",
    "meson.build": "meson",
    "composer.json": "php",
    "Gemfile": "ruby",
    "pubspec.yaml": "dart",
    "mix.exs": "elixir",
    "deno.json": "deno",
    "build.zig": "zig",
    "flake.nix": "nix",
    "Package.swift": "swift",
}
MANIFEST_SUFFIXES = {
    ".sln": "dotnet",
    ".csproj": "dotnet",
    ".fsproj": "dotnet",
    ".tf": "terraform",
}

# lockfile → the command that restores what it pins
LOCKFILES = {
    "pnpm-lock.yaml": "pnpm install --frozen-lockfile",
    "package-lock.json": "npm ci",
    "npm-shrinkwrap.json": "npm ci",
    "yarn.lock": "yarn install --frozen-lockfile",
    "bun.lockb": "bun install --frozen-lockfile",
    "bun.lock": "bun install --frozen-lockfile",
    "deno.lock": "deno install",
    "Cargo.lock": "cargo build",
    "uv.lock": "uv sync",
    "poetry.lock": "poetry install",
    "Pipfile.lock": "pipenv sync",
    "requirements.txt": "python -m venv .venv && .venv/bin/pip install -r requirements.txt",
    "go.sum": "go mod download",
    "composer.lock": "composer install",
    "Gemfile.lock": "bundle install",
    "mix.lock": "mix deps.get",
    "pubspec.lock": "dart pub get",
    ".terraform.lock.hcl": "terraform init",
    "gradle.lockfile": "./gradlew build",
    "Podfile.lock": "pod install",
}

# which lockfiles vouch for which dependency directory
DEP_LOCKS = {
    "node_modules": (
        "pnpm-lock.yaml",
        "package-lock.json",
        "npm-shrinkwrap.json",
        "yarn.lock",
        "bun.lockb",
        "bun.lock",
        "deno.lock",
    ),
    ".pnpm-store": ("pnpm-lock.yaml",),
    "bower_components": ("bower.json",),
    ".venv": ("uv.lock", "poetry.lock", "Pipfile.lock", "requirements.txt"),
    "venv": ("uv.lock", "poetry.lock", "Pipfile.lock", "requirements.txt"),
    "env": ("uv.lock", "poetry.lock", "Pipfile.lock", "requirements.txt"),
    "__pypackages__": ("pdm.lock",),
    "vendor": ("composer.lock", "go.sum", "Gemfile.lock"),
    ".terraform": (".terraform.lock.hcl",),
    "deps": ("mix.lock",),
    "Pods": ("Podfile.lock",),
    ".dart_tool": ("pubspec.lock",),
}

# Directory names that are dependencies / build output wherever they appear.
DEP_NAMES = {
    "node_modules",
    ".venv",
    ".pnpm-store",
    "bower_components",
    "__pypackages__",
    ".cxx",
    ".terraform",
    ".dart_tool",
}
BUILD_NAMES = {
    ".next",
    ".nuxt",
    ".svelte-kit",
    ".turbo",
    ".parcel-cache",
    ".output",
    ".vite",
    ".angular",
    ".expo",
    ".tanstack",
    ".kotlin",
    ".gocache",
    ".godot",
    ".import",
    "__pycache__",
    ".pytest_cache",
    ".mypy_cache",
    ".ruff_cache",
    ".tox",
    ".nox",
    ".eggs",
    ".elixir_ls",
    "storybook-static",
    ".docusaurus",
    ".astro",
    ".vercel",
    ".netlify",
    ".serverless",
    ".nyc_output",
    ".zig-cache",
    "zig-out",
    "DerivedData",
    ".ccls-cache",
    ".clangd",
    ".stack-work",
    "dist-newstyle",
}
# Names that only count next to (sibling) or holding (inside) a marker file.
#   name: (kind, sibling markers, inside markers)   — "*x" matches a suffix
MARKED_NAMES = {
    "venv": ("deps", (), ("pyvenv.cfg",)),
    "env": ("deps", (), ("pyvenv.cfg",)),
    "virtualenv": ("deps", (), ("pyvenv.cfg",)),
    "vendor": ("deps", ("composer.json", "go.mod", "Gemfile"), ()),
    "Pods": ("deps", ("Podfile",), ()),
    # ~/.gradle is Gradle's own home, not a project's dependency folder
    ".gradle": ("deps", ("build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts", "gradlew"), ()),
    ".bundle": ("deps", ("Gemfile",), ()),
    "deps": ("deps", ("mix.exs",), ()),
    "target": ("build", ("Cargo.toml", "pom.xml", "build.sbt"), ("CACHEDIR.TAG",)),
    "_build": ("build", ("mix.exs", "dune-project", "conf.py"), ()),
    "bin": ("build", ("*.csproj", "*.fsproj", "*.sln"), ()),
    "obj": ("build", ("*.csproj", "*.fsproj", "*.sln"), ()),
    "coverage": ("build", ("package.json", "pyproject.toml"), ()),
    "htmlcov": (
        "build",
        ("pyproject.toml", "setup.py", "requirements.txt", ".coveragerc"),
        (),
    ),
}
# build / dist / out are source in plenty of repos: they need a manifest or a
# lockfile right beside them.
for _n in ("build", "dist", "out"):
    MARKED_NAMES[_n] = ("build", tuple(MANIFESTS) + tuple(LOCKFILES), ())
BUILD_SUFFIXES = (".egg-info",)
# never guessed from the name: tmp, temp, logs, generated, data, cache

# Inside a candidate these make it "look before you delete".
STATEFUL_NAMES = (".env",)
STATEFUL_SUFFIXES = (".db", ".sqlite", ".sqlite3")

# Agent / scratch directories: shown, never offered for removal.
SCRATCH_NAMES = {
    "__ignore__",
    ".mystical",
    ".claude",
    ".agent-shell",
    "graphify-out",
    ".idea",
    ".vscode",
}

# ---- file kinds ---------------------------------------------------------------
EXT_KINDS = {
    "video": "mkv mp4 webm avi mov m4v wmv flv mpg mpeg ts m2ts vob ogv 3gp",
    "audio": "mp3 flac wav ogg opus m4a aac wma aiff alac",
    "image": "jpg jpeg png gif webp bmp tiff tif heic avif svg raw cr2 nef arw psd xcf kra",
    "archive": "zip tar gz tgz bz2 xz zst 7z rar tbz2 txz lz4 cab",
    "installer": "appimage deb rpm exe msi dmg pkg apk flatpak flatpakref snap run bin",
    "diskimage": "iso img qcow2 vdi vmdk vhd vhdx",
    "document": "pdf epub mobi djvu doc docx xls xlsx ppt pptx odt ods odp txt md csv",
    "model": "gguf safetensors ckpt pt pth onnx",
    "dump": "sql dump bak",
}
EXT_KIND = {}
for _k, _v in EXT_KINDS.items():
    for _e in _v.split():
        EXT_KIND[_e] = _k
KIND_LABEL = {
    "video": "Videos",
    "audio": "Audio",
    "image": "Images",
    "archive": "Archives",
    "installer": "Installers & packages",
    "diskimage": "Disk images",
    "document": "Documents",
    "model": "Model weights",
    "dump": "Database dumps",
    "other": "Everything else",
}


def ext_kind(name):
    low = name.lower()
    if low.endswith((".pkg.tar.zst", ".pkg.tar.xz")):
        return "installer"
    i = low.rfind(".")
    return EXT_KIND.get(low[i + 1 :], "other") if i > 0 else "other"


# ---- caches -------------------------------------------------------------------
# One row per known cache. Path resolution order: `ask` (argv, first line of its
# stdout) → `env` (variables, optional "/sub") → `paths` ("~" = home,
# "$CACHE"/"$DATA"/"$CONFIG" = the XDG dirs). `clean` is the tool's own cleaner,
# used when its binary exists; otherwise the directory's contents are removed.
#   tier free/cost as above; `note` says what coming back costs.
CACHES = [
    dict(
        key="go-build",
        label="Go build cache",
        ask=["go", "env", "GOCACHE"],
        env=["GOCACHE"],
        paths=["$CACHE/go-build"],
        clean=["go", "clean", "-cache"],
        tier="free",
        note="Rebuilt on the next go build; costs CPU only.",
    ),
    dict(
        key="go-mod",
        label="Go module cache",
        ask=["go", "env", "GOMODCACHE"],
        env=["GOMODCACHE", "GOPATH:/pkg/mod"],
        paths=["~/go/pkg/mod"],
        clean=["go", "clean", "-modcache"],
        tier="cost",
        note="Modules download again when a build needs them.",
    ),
    dict(
        key="npm",
        label="npm cache",
        ask=["npm", "config", "get", "cache"],
        env=["npm_config_cache"],
        paths=["~/.npm"],
        sub="_cacache",
        clean=["npm", "cache", "clean", "--force"],
        tier="cost",
        note="Packages download again on the next install.",
    ),
    dict(
        key="npx",
        label="npx cache",
        paths=["~/.npm/_npx"],
        tier="cost",
        note="npx downloads the tool again when you run it.",
    ),
    dict(
        key="yarn",
        label="Yarn cache",
        ask=["yarn", "cache", "dir"],
        env=["YARN_CACHE_FOLDER"],
        paths=["$CACHE/yarn"],
        clean=["yarn", "cache", "clean"],
        tier="cost",
        note="Packages download again on the next install.",
    ),
    dict(
        key="pnpm",
        label="pnpm store",
        ask=["pnpm", "store", "path"],
        paths=["$DATA/pnpm/store", "~/.pnpm-store"],
        clean=["pnpm", "store", "prune"],
        tier="cost",
        note="Prune only drops packages no project links to any more.",
        hardlinked=True,
    ),
    dict(
        key="bun",
        label="Bun cache",
        ask=["bun", "pm", "cache"],
        env=["BUN_INSTALL_CACHE_DIR"],
        paths=["~/.bun/install/cache"],
        clean=["bun", "pm", "cache", "rm"],
        tier="cost",
        note="Packages download again on the next install.",
        hardlinked=True,
    ),
    dict(
        key="deno",
        label="Deno cache",
        env=["DENO_DIR"],
        paths=["$CACHE/deno"],
        tier="cost",
        note="Modules download again when a script needs them.",
    ),
    dict(
        key="pip",
        label="pip cache",
        ask=["pip", "cache", "dir"],
        env=["PIP_CACHE_DIR"],
        paths=["$CACHE/pip"],
        clean=["pip", "cache", "purge"],
        tier="cost",
        note="Wheels download (or build) again on the next install.",
    ),
    dict(
        key="uv",
        label="uv cache",
        ask=["uv", "cache", "dir"],
        env=["UV_CACHE_DIR"],
        paths=["$CACHE/uv"],
        clean=["uv", "cache", "prune"],
        tier="cost",
        note="Prune drops unused entries; venvs hardlink into this cache.",
        hardlinked=True,
    ),
    dict(
        key="poetry",
        label="Poetry cache",
        env=["POETRY_CACHE_DIR"],
        paths=["$CACHE/pypoetry"],
        clean=["poetry", "cache", "clear", "--all", ".", "--no-interaction"],
        tier="cost",
        note="Packages download again on the next install.",
    ),
    dict(
        key="pre-commit",
        label="pre-commit environments",
        env=["PRE_COMMIT_HOME"],
        paths=["$CACHE/pre-commit"],
        clean=["pre-commit", "clean"],
        tier="cost",
        note="Hook environments are rebuilt on the next commit.",
    ),
    dict(
        key="cargo-registry",
        label="Cargo registry",
        env=["CARGO_HOME:/registry"],
        paths=["~/.cargo/registry"],
        tier="cost",
        note="Crates download again on the next build.",
    ),
    dict(
        key="cargo-git",
        label="Cargo git checkouts",
        env=["CARGO_HOME:/git"],
        paths=["~/.cargo/git"],
        tier="cost",
        note="Git dependencies are cloned again on the next build.",
    ),
    dict(
        key="gradle",
        label="Gradle caches",
        env=["GRADLE_USER_HOME:/caches"],
        paths=["~/.gradle/caches"],
        tier="cost",
        note="Stop the daemon first (gradle --stop). Dependencies download again.",
        pre=["gradle", "--stop"],
    ),
    dict(
        key="gradle-wrapper",
        label="Gradle wrapper distributions",
        env=["GRADLE_USER_HOME:/wrapper"],
        paths=["~/.gradle/wrapper"],
        tier="cost",
        note="Each project downloads its Gradle version again.",
    ),
    dict(
        key="maven",
        label="Maven repository",
        paths=["~/.m2/repository"],
        tier="cost",
        note="Artifacts download again on the next build.",
    ),
    dict(
        key="nuget",
        label="NuGet packages",
        env=["NUGET_PACKAGES"],
        paths=["~/.nuget/packages"],
        clean=["dotnet", "nuget", "locals", "all", "--clear"],
        tier="cost",
        note="Packages restore again on the next build.",
    ),
    dict(
        key="composer",
        label="Composer cache",
        env=["COMPOSER_CACHE_DIR"],
        paths=["$CACHE/composer"],
        clean=["composer", "clear-cache"],
        tier="cost",
        note="Packages download again on the next install.",
    ),
    dict(
        key="ccache",
        label="ccache",
        env=["CCACHE_DIR"],
        paths=["$CACHE/ccache", "~/.ccache"],
        clean=["ccache", "-C"],
        tier="free",
        note="Compiler output; rebuilt as you compile.",
    ),
    dict(
        key="sccache",
        label="sccache",
        env=["SCCACHE_DIR"],
        paths=["$CACHE/sccache"],
        tier="free",
        note="Compiler output; rebuilt as you compile.",
    ),
    dict(
        key="zig",
        label="Zig cache",
        paths=["$CACHE/zig"],
        tier="free",
        note="Rebuilt on the next zig build.",
    ),
    dict(
        key="bazel",
        label="Bazel cache",
        paths=["$CACHE/bazel"],
        tier="free",
        note="Rebuilt on the next bazel build.",
    ),
    dict(
        key="node-gyp",
        label="node-gyp headers",
        paths=["$CACHE/node-gyp"],
        tier="cost",
        note="Headers download again when a native module builds.",
    ),
    dict(
        key="electron",
        label="Electron downloads",
        paths=["$CACHE/electron", "$CACHE/electron-builder"],
        tier="cost",
        note="Electron downloads again when a project installs it.",
    ),
    dict(
        key="playwright",
        label="Playwright browsers",
        env=["PLAYWRIGHT_BROWSERS_PATH"],
        paths=["$CACHE/ms-playwright"],
        tier="cost",
        note="Browsers download again with `npx playwright install`.",
    ),
    dict(
        key="puppeteer",
        label="Puppeteer browsers",
        env=["PUPPETEER_CACHE_DIR"],
        paths=["$CACHE/puppeteer"],
        tier="cost",
        note="Chrome downloads again on the next install.",
    ),
    dict(
        key="cypress",
        label="Cypress binaries",
        env=["CYPRESS_CACHE_FOLDER"],
        paths=["$CACHE/Cypress"],
        tier="cost",
        note="Cypress downloads again on the next install.",
    ),
    dict(
        key="huggingface",
        label="Hugging Face models",
        env=["HF_HOME", "HUGGINGFACE_HUB_CACHE"],
        paths=["$CACHE/huggingface"],
        tier="cost",
        note="Model weights download again — these can be many GB each.",
        heavy=True,
    ),
    dict(
        key="torch",
        label="PyTorch hub",
        env=["TORCH_HOME"],
        paths=["$CACHE/torch"],
        tier="cost",
        note="Model weights download again.",
        heavy=True,
    ),
    dict(
        key="whisper",
        label="Whisper models",
        paths=["$CACHE/whisper"],
        tier="cost",
        note="Model weights download again.",
        heavy=True,
    ),
    dict(
        key="mesa",
        label="Mesa shader cache",
        env=["MESA_SHADER_CACHE_DIR"],
        paths=["$CACHE/mesa_shader_cache", "$CACHE/mesa_shader_cache_db"],
        tier="free",
        note="Shaders recompile; games may stutter once.",
    ),
    dict(
        key="nvidia",
        label="NVIDIA shader cache",
        paths=["$CACHE/nvidia", "~/.nv"],
        tier="free",
        note="Shaders recompile; games may stutter once.",
    ),
    dict(
        key="firefox",
        label="Firefox cache",
        paths=["$CACHE/mozilla"],
        tier="free",
        note="Close Firefox first. Pages load from the network again.",
        closed="firefox",
    ),
    dict(
        key="chrome",
        label="Chrome cache",
        paths=["$CACHE/google-chrome"],
        tier="free",
        note="Close Chrome first. Pages load from the network again.",
        closed="chrome",
    ),
    dict(
        key="chromium",
        label="Chromium cache",
        paths=["$CACHE/chromium"],
        tier="free",
        note="Close Chromium first. Pages load from the network again.",
        closed="chromium",
    ),
    dict(
        key="jetbrains",
        label="JetBrains caches",
        paths=["$CACHE/JetBrains"],
        tier="free",
        note="IDEs re-index projects on the next start.",
    ),
    dict(
        key="fontconfig",
        label="Font cache",
        paths=["$CACHE/fontconfig"],
        clean=["fc-cache", "-r"],
        tier="free",
        note="Rebuilt automatically.",
    ),
    dict(
        key="kioexec",
        label="KDE opened-remote-file copies",
        paths=["$CACHE/kioexec"],
        tier="free",
        note="Temporary copies of files opened from remote locations.",
    ),
    dict(
        key="yay",
        label="yay build cache",
        paths=["$CACHE/yay"],
        clean=["yay", "-Sc", "--aur", "--noconfirm"],
        tier="cost",
        note="AUR packages are cloned and built again on reinstall.",
        section="packages",
    ),
    dict(
        key="paru",
        label="paru build cache",
        paths=["$CACHE/paru"],
        clean=["paru", "-Sc", "--aur", "--noconfirm"],
        tier="cost",
        note="AUR packages are cloned and built again on reinstall.",
        section="packages",
    ),
]

# Not caches — large tool data worth seeing, never offered automatically.
TOOL_DATA = [
    dict(
        key="lmstudio",
        label="LM Studio models",
        paths=["~/.lmstudio", "$CACHE/lm-studio"],
        note="Model weights you chose to download.",
    ),
    dict(
        key="ollama",
        label="Ollama models",
        env=["OLLAMA_MODELS"],
        paths=["~/.ollama", "/var/lib/ollama"],
        note="Remove single models with `ollama rm <name>`.",
    ),
    dict(
        key="android-sdk",
        label="Android SDK",
        env=["ANDROID_HOME", "ANDROID_SDK_ROOT"],
        paths=["~/Android/Sdk"],
        note="Platforms and build-tools; manage with sdkmanager.",
    ),
    dict(
        key="android-avd",
        label="Android emulators",
        env=["ANDROID_AVD_HOME"],
        paths=["~/.android/avd"],
        note="Each emulator holds its own state.",
    ),
    dict(
        key="rustup",
        label="Rust toolchains",
        env=["RUSTUP_HOME:/toolchains"],
        paths=["~/.rustup/toolchains"],
        note="Remove single ones with `rustup toolchain uninstall`.",
    ),
    dict(
        key="nvm",
        label="Node versions (nvm)",
        env=["NVM_DIR:/versions"],
        paths=["~/.nvm/versions"],
        note="Remove single ones with `nvm uninstall <version>`.",
    ),
    dict(
        key="vscode-ws",
        label="VS Code workspace storage",
        paths=["$CONFIG/Code/User/workspaceStorage"],
        note="Per-workspace editor state and extension data.",
    ),
    dict(
        key="libvirt",
        label="Virtual machine images",
        paths=["$DATA/libvirt/images", "/var/lib/libvirt/images"],
        note="Disks of your virtual machines.",
    ),
]

# Electron-style apps keep these under ~/.config/<App>/
ELECTRON_CACHE_DIRS = (
    "Cache",
    "Code Cache",
    "GPUCache",
    "CachedData",
    "CachedExtensionVSIXs",
    "Service Worker/CacheStorage",
    "DawnCache",
    "DawnGraphiteCache",
)

# ---- games --------------------------------------------------------------------
STEAM_ROOTS = [
    "$DATA/Steam",
    "~/.steam/steam",
    "~/.var/app/com.valvesoftware.Steam/.local/share/Steam",
]
GAME_DIRS = [
    dict(key="lutris", label="Lutris", paths=["~/Games", "$DATA/lutris"]),
    dict(key="heroic", label="Heroic", paths=["~/Games/Heroic", "$CONFIG/heroic"]),
    dict(
        key="bottles",
        label="Bottles",
        paths=[
            "$DATA/bottles/bottles",
            "~/.var/app/com.usebottles.bottles/data/bottles/bottles",
        ],
    ),
    dict(key="wine", label="Wine prefix", paths=["~/.wine"]),
    dict(key="itch", label="itch", paths=["$CONFIG/itch/apps"]),
    dict(
        key="minecraft",
        label="Minecraft",
        paths=["~/.minecraft", "$DATA/PrismLauncher"],
    ),
    dict(
        key="godot",
        label="Godot export templates",
        paths=["$DATA/godot/export_templates"],
    ),
]

# ---- where things usually are ---------------------------------------------------
PROJECT_ROOT_GUESSES = [
    "~/Documents/projects",
    "~/projects",
    "~/Projects",
    "~/src",
    "~/code",
    "~/Code",
    "~/dev",
    "~/Developer",
    "~/work",
    "~/repos",
    "~/git",
    "~/workspace",
    "~/Documents/.worktrees",
]
BIN_DIRS = ["~/bin", "~/.local/bin", "~/Applications", "/opt", "/usr/local/bin"]

# rm is never pointed at one of these, whatever a plan says.
PROTECTED_NAMES = {
    ".git",
    ".ssh",
    ".gnupg",
    ".password-store",
    "Documents",
    "Pictures",
    "Music",
    "Videos",
    "Desktop",
    "Downloads",
    ".config",
    ".local",
    ".mozilla",
}
