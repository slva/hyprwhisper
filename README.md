# hyprWhisper

Voice-to-text integration for Hyprland using OpenAI's Whisper (via whisper.cpp) with a **native Quickshell QML UI**.

## Features

- 🎤 One-key toggle to start/stop recording
- ⚡ Fast local transcription with whisper.cpp (C++), language auto-detected
- 📋 Pastes the text straight into the focused window (and keeps it in the clipboard)
- 🖥️ **Native QML UI** integrated with Quickshell (no external notifications)
- 🎨 Follows your Quickshell (`ii`) theme colors automatically
- 🔒 No cloud services - 100% local processing; the recording is deleted after use
- 🚀 GPU acceleration with CUDA or Vulkan

## Requirements

- **OS**: Linux with Wayland. The installer supports Fedora and Arch Linux / CachyOS
- **Desktop**: Hyprland with **Quickshell** running the **`ii` config** from [end-4/dots-hyprland](https://github.com/end-4/dots-hyprland)
  (`WhisperPopup.qml` uses its `qs.modules.common` module for theme colors)
- **Audio**: PipeWire (with `pipewire-pulse`) or PulseAudio, and a microphone
- **Optional**: NVIDIA GPU + CUDA toolkit, or any Vulkan GPU, for faster transcription

## Quick Install

```bash
git clone <repository-url>
cd hyprWhisper
./install.sh
```

The installer asks whether to install system dependencies and whether to (re)compile whisper.cpp,
then installs `whisper-toggle.sh` and the QML component. The GPU backend is auto-detected
(CUDA > Vulkan > CPU); force it with `WHISPER_BACKEND=cuda|vulkan|cpu ./install.sh`.
Use `QS_CONFIG=<name>` if your Quickshell config isn't called `ii`.

It does **not** edit your `shell.qml` or your Hyprland keybinds: do steps 4 and 6 below by hand.

## Manual Installation

### 1. Install Dependencies

```bash
# Fedora
sudo dnf install git make cmake gcc-c++ ffmpeg wl-clipboard
# For the Vulkan build also: vulkan-headers vulkan-loader-devel glslc spirv-headers-devel

# Arch Linux / CachyOS
sudo pacman -S --needed git make cmake gcc ffmpeg wl-clipboard
# For the CUDA build also: cuda
# For the Vulkan build also: vulkan-headers vulkan-icd-loader shaderc spirv-headers

# Install Quickshell (if not already installed)
# See: https://quickshell.org
```

### 2. Compile whisper.cpp

```bash
mkdir -p ~/Apps
cd ~/Apps
git clone https://github.com/ggml-org/whisper.cpp.git
cd whisper.cpp

# Download model (small = fast, medium = balanced (default), large-v3 = most accurate)
bash ./models/download-ggml-model.sh medium

# Build with CMake
mkdir -p build && cd build
```

Then configure **one** backend:

```bash
# NVIDIA GPU (CUDA) - fastest on NVIDIA, never picks an integrated GPU.
# Paths below are for Arch. nvcc doesn't accept the newest GCC, so pass the host
# compiler your distro configures for it (Arch: NVCC_CCBIN in /etc/profile.d/cuda.sh).
# CMAKE_CUDA_ARCHITECTURES is your GPU's compute capability without the dot
# (nvidia-smi --query-gpu=compute_cap --format=csv,noheader), e.g. 89 = RTX 40xx.
cmake .. -DGGML_CUDA=1 \
  -DCMAKE_CUDA_COMPILER=/opt/cuda/bin/nvcc \
  -DCMAKE_CUDA_HOST_COMPILER=/usr/bin/g++-15 \
  -DCMAKE_CUDA_ARCHITECTURES=89

# Vulkan (NVIDIA/AMD/Intel). With hybrid graphics it uses device 0,
# which may be the integrated GPU:
cmake .. -DGGML_VULKAN=1

# CPU only:
cmake ..
```

And build:

```bash
cmake --build . -j"$(nproc)" --config Release
```

> If CMake fails with a missing tool from a previous build (e.g. `/usr/bin/gmake`),
> remove the stale cache first: `rm -rf CMakeCache.txt CMakeFiles`.

### 3. Install the QML Component

```bash
mkdir -p ~/.config/quickshell/ii/modules/whisper
cp /path/to/hyprWhisper/qml/WhisperPopup.qml ~/.config/quickshell/ii/modules/whisper/
```

### 4. Integrate with Quickshell

Edit `~/.config/quickshell/ii/shell.qml`. The import goes with the other imports; the property
and the `LazyLoader` go **inside** `ShellRoot`:

```qml
import "modules/whisper" as Whisper

ShellRoot {
    id: root
    property bool enableWhisper: true   // set to false to disable hyprWhisper

    LazyLoader { active: enableWhisper; component: Whisper.WhisperPopup {} }

    // ... the rest of your existing config ...
}
```

Then restart Quickshell:

```bash
qs kill -c ii && qs -c ii -d
```

> `shell.qml` belongs to dots-hyprland, so updating the dotfiles may overwrite this change.

### 5. Install the Script

```bash
mkdir -p ~/.local/bin
cp whisper-toggle.sh ~/.local/bin/
chmod +x ~/.local/bin/whisper-toggle.sh
```

### 6. Configure the Hyprland Keybind

`Super+D` is already used by `ii` (Window: Maximize), so the suggested key is **`Super+Alt+D`**.

Lua config (`~/.config/hypr/custom/keybinds.lua` in dots-hyprland):

```lua
hl.bind("SUPER+ALT+D", hl.dsp.exec_cmd("$HOME/.local/bin/whisper-toggle.sh"), {description = "Whisper: toggle dictation"})
```

Classic config (`~/.config/hypr/hyprland.conf`):

```ini
bind = SUPER ALT, D, exec, ~/.local/bin/whisper-toggle.sh
```

Reload Hyprland with `hyprctl reload`. See `config/hyprland.conf` for other key options.

### 7. Verify

```bash
whisper-toggle.sh --status   # should print: idle
```

## Usage

1. Open any text editor or input field
2. Press `Super+Alt+D` to start recording (the popup shows an animated waveform)
3. Speak
4. Press `Super+Alt+D` again to stop
5. Wait for the transcription (the popup shows a sliding progress bar)
6. The popup closes and the text is pasted into the focused window (and copied to the clipboard)

### Auto-paste

After copying with `wl-copy`, hyprWhisper sends the paste shortcut straight to the focused window
with Hyprland's `send_shortcut` dispatcher (no extra tools or permissions; works with both the Lua
and the classic config). Terminals (kitty, foot, Alacritty,
WezTerm, Ghostty, Konsole, GNOME Terminal, Ptyxis, Tilix, xterm) get **Ctrl+Shift+V**, every other
window **Ctrl+V**; the window class comes from `hyprctl activewindow -j`. If no window is focused,
the text just stays in the clipboard.

Set `WHISPER_AUTOPASTE=0` (see [Configuration](#configuration)) to only copy to the clipboard.

### UI Features

The popup is a small bar at the bottom center of the screen that shows the current phase:

- **Recording**: Animated waveform
- **Processing**: Indeterminate sliding progress bar
- **Result**: The popup closes right away and the text is pasted
- **Error**: Red bar that fills up as a countdown, then the popup closes (3s); the reason is logged (see [Check logs](#check-logs))
- **Theme integration**: Uses your Quickshell theme colors automatically
- **Close an error early**: click the popup or press the keybind again

Whisper output is cleaned before copying: segments are joined into a single line and
non-speech tags such as `[BLANK_AUDIO]` are dropped. If nothing is left, it's treated as an error.

## How It Works

The script uses **Quickshell IPC** to talk to the QML component, which runs all the logic:

```
whisper-toggle.sh                     WhisperPopup.qml
        |                                    |
        | qs -c ii ipc call whisper toggle   |
        |----------------------------------->|  idle -> recording
        |                                    |  starts ffmpeg, shows waveform
        |                                    |
[second press]                               |
        |----------------------------------->|  recording -> processing
        |                                    |  stops ffmpeg, runs whisper-cli
        |                                    |
        |                                    |  processing -> result
        |                                    |  copies text with wl-copy
        |                                    |  pastes it with hyprctl (send_shortcut)
        |                                    |  deletes the audio file
        |                                    |
        |                                    |  hides the popup -> idle
```

State lives entirely in QML: no state files, no polling. Before calling, the script checks
`qs ipc show` so it can report when Quickshell isn't running or the module isn't loaded.

The recording is stored in `$XDG_RUNTIME_DIR/hyprwhisper_audio.wav` (private to your user) and deleted
as soon as the transcription finishes or is stopped. `whisper-cli` runs as a new process for each
transcription, so the model only uses (V)RAM while transcribing and is freed when it exits.

## Configuration

The QML component reads these environment variables **from Quickshell's own environment**, so set
them where Quickshell is started (in your Hyprland config, which launches `qs`) and restart Quickshell:

```lua
-- Lua config (e.g. ~/.config/hypr/custom/env.lua)
hl.env("WHISPER_DIR", os.getenv("HOME") .. "/Apps/whisper.cpp")  -- default: $HOME/Apps/whisper.cpp
hl.env("WHISPER_MODEL", "models/ggml-small.bin")                 -- default: models/ggml-medium.bin
hl.env("WHISPER_AUTOPASTE", "0")                                 -- default: 1 (paste into focused window)
```

```ini
# Classic config (hyprland.conf)
env = WHISPER_DIR,/home/you/Apps/whisper.cpp
env = WHISPER_MODEL,models/ggml-small.bin
env = WHISPER_AUTOPASTE,0
```

`WHISPER_MODEL` is relative to `WHISPER_DIR`. Download other models with
`bash ./models/download-ggml-model.sh <name>` inside the whisper.cpp directory:

- `tiny` - Fastest, least accurate
- `small` - Fast, good accuracy
- `medium` - Balanced (default)
- `large-v3-turbo` - Close to large-v3 accuracy, much faster
- `large-v3` - Best accuracy, slowest

Script and installer variables:

| Variable | Used by | Default | Description |
|---|---|---|---|
| `QS_CONFIG` | script, installer | `ii` | Quickshell config name |
| `WHISPER_BACKEND` | installer | `auto` | `auto`, `cuda`, `vulkan` or `cpu` |
| `INSTALL_DIR` | installer | `~/.local/bin` | Where `whisper-toggle.sh` is installed |

## Customization

All of these are in `qml/WhisperPopup.qml`. After editing, copy it again and restart Quickshell:

```bash
cp qml/WhisperPopup.qml ~/.config/quickshell/ii/modules/whisper/ && qs kill -c ii && qs -c ii -d
```

### Change Popup Position

The popup is a layer-shell `PanelWindow`, horizontally centered at the bottom of the screen.
It's centered in the free area, so space reserved by bars (e.g. the `ii` vertical bar) is excluded.

```qml
// Distance from the bottom edge
readonly property int bottomMargin: 20

// In the PanelWindow - bottom center (default)
anchors.bottom: true
margins.bottom: scope.bottomMargin

// Top center instead
anchors.top: true
margins.top: 50

// Screen center: remove the anchors and margins
```

### Change the Error Auto-close Time

```qml
readonly property int autoCloseMs: 3000  // milliseconds
```

### Change the Waveform

Properties of the waveform `Row`:

```qml
readonly property int barCount: 27
readonly property int barWidth: 4
readonly property real minBarHeight: barWidth * 2
readonly property real maxBarHeight: 34
```

### Force a Language

The language is auto-detected (`-l auto`). To force one, change it in the `transcribeProcess`
command, e.g. `"-l", "ca"`.

## Commands

```bash
# Toggle recording/transcription
whisper-toggle.sh

# Print current phase (idle, recording, processing, result, error)
whisper-toggle.sh --status

# Force stop recording/transcription if stuck
whisper-toggle.sh --stop

# Show help
whisper-toggle.sh --help
```

## Troubleshooting

### No popup appears

1. Run `whisper-toggle.sh --status`: it tells you if Quickshell isn't running or the module isn't loaded
2. Restart Quickshell after installing/updating QML files: `qs kill -c ii && qs -c ii -d`
3. Check that `target whisper` appears in `qs -c ii ipc show`
4. Check the Quickshell logs (see below)
5. Make sure the keybind doesn't collide with another one (same `modmask` on the same key):
   `hyprctl binds | grep -B3 -A3 "key: D$" | grep -E "modmask|description"`

### Popup stays in "processing"

Run `whisper-toggle.sh --stop`. There is also a 5 minute safety timeout, after which it shows an error.

### Transcription is slow

- Build with GPU support: `WHISPER_BACKEND=cuda ./install.sh` (or `vulkan`)
- Use a smaller model: `small` or `large-v3-turbo` instead of `large-v3`
- Check which GPU is used:
  ```bash
  ~/Apps/whisper.cpp/build/bin/whisper-cli -m ~/Apps/whisper.cpp/models/ggml-medium.bin \
    -f ~/Apps/whisper.cpp/samples/jfk.wav 2>&1 | grep -E "using (CUDA|Vulkan)|total time"
  ```
- On laptops with hybrid graphics, a Vulkan build uses device 0 (often the integrated GPU); prefer CUDA on NVIDIA
- The first transcription after boot is slower while the model is read from disk (and, with Vulkan, shaders are compiled)

### Errors after a CUDA update

The CUDA build links against a specific CUDA runtime (e.g. `libcudart.so.13`). After a major CUDA
upgrade, recompile: `WHISPER_BACKEND=cuda ./install.sh`.

### Check logs

Errors (ffmpeg failing, `whisper-cli` not found, transcription failures) are logged by Quickshell
with the `[hyprWhisper]` prefix:

```bash
qs log -c ii | grep hyprWhisper
```

## Project Structure

```
hyprWhisper/
├── whisper-toggle.sh              # Keybind script (IPC client)
├── install.sh                     # Installation script
├── qml/
│   └── WhisperPopup.qml           # UI popup + all the logic
├── config/
│   └── hyprland.conf              # Example Hyprland keybinds and env vars
├── docs/
│   └── ffmpeg_streaming_research.md  # Notes for a possible streaming mode
├── README.md                      # This file
└── AGENTS.md                      # Development guidelines
```

## License

MIT License - Feel free to use and modify!

## Credits

- [whisper.cpp](https://github.com/ggml-org/whisper.cpp) by Georgi Gerganov
- [Quickshell](https://quickshell.org) for the awesome shell framework
- [end-4/dots-hyprland](https://github.com/end-4/dots-hyprland) for the `ii` config
- OpenAI Whisper model
