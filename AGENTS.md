# AGENTS.md

## Project Overview

hyprWhisper is a voice-to-text tool for Hyprland (Wayland compositor) that uses:
- **whisper.cpp** (C++) for speech recognition
- **ffmpeg** for audio recording
- **wl-clipboard** for clipboard operations
- **Quickshell** with QML for native UI integration

## Build Commands

### Dependencies Installation
```bash
# Fedora
sudo dnf install git make cmake gcc-c++ ffmpeg wl-clipboard
# Vulkan build: vulkan-headers vulkan-loader-devel glslc spirv-headers-devel

# Arch Linux / CachyOS
sudo pacman -S --needed git make cmake gcc ffmpeg wl-clipboard
# Vulkan build: vulkan-headers vulkan-icd-loader shaderc spirv-headers
```

### Compile whisper.cpp (CMake - Official Method)
```bash
# Clone whisper.cpp
mkdir -p ~/Apps
cd ~/Apps
git clone https://github.com/ggml-org/whisper.cpp.git
cd whisper.cpp

# Download model (small = fast, medium = balanced/best, large = most accurate)
bash ./models/download-ggml-model.sh medium

# Build with CMake (official method)
mkdir -p build && cd build

# For NVIDIA GPU (CUDA - fastest on NVIDIA, avoids picking an integrated GPU):
# nvcc doesn't accept the newest GCC, so pass a supported host compiler
# (Arch sets it in /etc/profile.d/cuda.sh as NVCC_CCBIN). 89 = RTX 40xx
cmake .. -DGGML_CUDA=1 \
  -DCMAKE_CUDA_COMPILER=/opt/cuda/bin/nvcc \
  -DCMAKE_CUDA_HOST_COMPILER=/usr/bin/g++-15 \
  -DCMAKE_CUDA_ARCHITECTURES=89

# For GPU (Vulkan - supports NVIDIA/AMD/Intel). With hybrid graphics it uses
# device 0, which may be the integrated GPU:
# cmake .. -DGGML_VULKAN=1

# For CPU only:
# cmake ..

# Compile with all CPU cores
cmake --build . -j$(nproc) --config Release

# Executables location: ./build/bin/
# - whisper-cli (main executable)
# - whisper-server (HTTP API)
# - whisper-stream (real-time)
```

**Note:** The old `make -j` method still works but CMake is the officially supported build system.

### Install Script
```bash
# Option 1: Use the installer (recommended)
# Backend is auto-detected (CUDA > Vulkan > CPU); force it with WHISPER_BACKEND
./install.sh
WHISPER_BACKEND=cuda ./install.sh

# Option 2: Manual installation
mkdir -p ~/.local/bin
cp whisper-toggle.sh ~/.local/bin/
chmod +x ~/.local/bin/whisper-toggle.sh

# Install QML components
mkdir -p ~/.config/quickshell/ii/modules/whisper
cp qml/*.qml ~/.config/quickshell/ii/modules/whisper/
```

### Quickshell Integration
Add to your `~/.config/quickshell/ii/shell.qml`:

```qml
import "modules/whisper" as Whisper

ShellRoot {
    // ... your existing config ...
    property bool enableWhisper: true

    LazyLoader { active: enableWhisper; component: Whisper.WhisperPopup {} }
}
```

`WhisperPopup.qml` imports `qs.modules.common` (for `Appearance`), so it must live inside a config that provides it (e.g. `ii`).

## Test Commands

### Manual Testing
```bash
# Test audio recording
ffmpeg -f pulse -i default -t 5 -ar 16000 -ac 1 /tmp/test.wav

# Test transcription
~/Apps/whisper.cpp/build/bin/whisper-cli -m ~/Apps/whisper.cpp/models/ggml-medium.bin -f /tmp/test.wav -l auto -nt

# Test clipboard
echo "test" | wl-copy
wl-paste
```

### Lint Scripts
```bash
# Check bash syntax
bash -n whisper-toggle.sh

# Lint with shellcheck (if available)
shellcheck whisper-toggle.sh install.sh
```

### QML Testing
```bash
# IPC round trip (requires the module loaded in the running config)
whisper-toggle.sh --status          # prints the current phase
qs -c ii ipc show | grep -x "target whisper"

# Errors are logged with the [hyprWhisper] prefix
qs log -c ii | grep hyprWhisper
```

## Code Style Guidelines

### Shell Scripts
- Use `#!/bin/bash` shebang
- Quote all variables: `"$VAR"` not `$VAR`
- Use `[[ ]]` for conditionals, not `[ ]`
- Functions: `snake_case`
- Constants: `UPPER_CASE`
- Local variables: `local var_name`
- Exit codes: `0` success, `1` general error, specific codes for debugging

### Imports/Dependencies
- Check for required tools before execution
- Provide clear error messages for missing deps
- Use absolute paths for config files

### Error Handling
```bash
set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Or manual checks
if ! command -v wl-copy &> /dev/null; then
    echo "Error: wl-clipboard not installed"
    exit 1
fi
```

### Configuration
- Store in variables at top of script
- Use `$HOME` not `~` in variables
- Default values: `VAR=${VAR:-default}`
- Config files in `~/.config/hyprwhisper/`

### Naming Conventions
- Scripts: `kebab-case.sh`
- Functions: `snake_case`
- Variables: `UPPER_CASE` for constants, `snake_case` for local
- Temp files: `$XDG_RUNTIME_DIR/hyprwhisper_*` (private to the user, unlike `/tmp`)

### Documentation
- Header comment with description
- Comment complex logic
- Usage function for `--help`

### QML-Native UI System with IPC
The tool uses a **QML-native UI** integrated with Quickshell, fully managing its state internally.

```bash
# Bash script triggers IPC call to Quickshell
qs -c ii ipc call whisper toggle
```

**Architecture:**
- The bash script (`whisper-toggle.sh`) acts as a simple IPC client, sending commands to Quickshell via `qs ipc call`.
  - `qs ipc call` exits 0 even when the target doesn't exist, so the script first checks `qs ipc show` for `target whisper`.
- `WhisperPopup.qml` handles all logic:
  - Exposes an `IpcHandler` (target `"whisper"`) with `toggle()`, `stop()` and `status(): string`.
  - Manages internal state (`idle`, `recording`, `processing`, `result`, `error`).
  - Uses `Process` components to asynchronously execute `ffmpeg` (recording), `whisper-cli` (transcription), `wl-copy` (clipboard) and `rm` (audio cleanup).
  - Uses `StdioCollector` to read transcription output directly from stdout.
  - Reads `WHISPER_DIR` / `WHISPER_MODEL` from Quickshell's environment via `Quickshell.env()`.
- Fully integrated with Quickshell theme (`Appearance.colors`).

**Process lifecycle (Quickshell `Process`):**
- Normal exit emits `stdout.streamFinished` → `exited` → `runningChanged`.
- If the binary can't be started, **only** `runningChanged` is emitted (no `exited`).
- So phase transitions are driven by `onRunningChanged: if (!running)`, and `onExited` only records the exit code.
- `processingTimeout` (5 min) is a safety net in case `whisper-cli` hangs.

**Phases:**
1. **recording**: Animated waveform. ffmpeg is running.
2. **processing**: Sliding indeterminate progress bar. ffmpeg stopped, whisper-cli running.
3. **result**: Progress bar fills as a countdown. Text copied with wl-copy. Auto-closes in 3s (`autoCloseMs`).
4. **error**: Same countdown in red. The reason is logged with `console.warn("[hyprWhisper] ...")`. Auto-closes in 3s.

**Key design decisions:**
- True native QML app: No temporary state files, no polling, no external state management.
- Pure IPC architecture matching Quickshell's design patterns.
- Minimal popup: no text preview, the result goes straight to the clipboard.
- Transcript cleanup: segments joined into one line, non-speech tags like `[BLANK_AUDIO]` dropped.
- Audio lives in `$XDG_RUNTIME_DIR` and is deleted after transcription or stop.
- Requires Quickshell restart after installation to load the QML components properly.

## Project Structure

```
hyprWhisper/
├── whisper-toggle.sh      # Main toggle script (IPC sender)
├── install.sh             # Installation script
├── README.md              # User documentation
├── AGENTS.md              # This file
├── qml/
│   └── WhisperPopup.qml   # Main popup window and logic controller
├── config/
│   └── hyprland.conf      # Example Hyprland binding
└── docs/
    └── ffmpeg_streaming_research.md  # Notes for a possible streaming mode
```

## Script Options

```bash
whisper-toggle.sh [OPTIONS]

Options:
  -h, --help      Show help message
  -s, --stop      Force stop recording/transcription if stuck
  --status        Print the current phase (idle, recording, processing, result, error)

Environment Variables (script):
  QS_CONFIG       Quickshell config name (default: ii)

Environment Variables (Quickshell process, e.g. `env =` in hyprland.conf):
  WHISPER_DIR     Path to whisper.cpp directory (default: ~/Apps/whisper.cpp)
  WHISPER_MODEL   Model path relative to WHISPER_DIR (default: models/ggml-medium.bin)
```

## Hyprland Integration

`SUPER+D` is already "Window: Maximize" in the `ii` config, so the default key is `SUPER+ALT+D`.

Classic config (`~/.config/hypr/hyprland.conf`):
```ini
bind = SUPER ALT, D, exec, ~/.local/bin/whisper-toggle.sh
```

Lua config (`~/.config/hypr/custom/keybinds.lua` in dots-hyprland):
```lua
hl.bind("SUPER+ALT+D", hl.dsp.exec_cmd("$HOME/.local/bin/whisper-toggle.sh"), {description = "Whisper: toggle dictation"})
```

## Security Notes

- Never log sensitive audio data
- Clean up temp files on exit
- Validate file permissions
- Use `trap` for cleanup on script interruption
