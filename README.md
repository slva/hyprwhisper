# hyprWhisper

Voice-to-text integration for Hyprland using OpenAI's Whisper with **native QML UI**.

## Features

- 🎤 One-key toggle to start/stop recording
- ⚡ Real-time transcription using whisper.cpp (C++)
- 📋 Automatic clipboard copy
- 🖥️ **Native QML UI** integrated with Quickshell (no external notifications)
- 🎨 Follows your Hyprland theme automatically
- 🔒 No cloud services - 100% local processing
- 🚀 GPU acceleration with Vulkan

## Requirements

- **OS**: Fedora Linux (or any Linux with Wayland)
- **Desktop**: Hyprland with **Quickshell**
- **Hardware**: Microphone
- **Optional**: NVIDIA/AMD/Intel GPU for faster transcription

## Quick Install

```bash
git clone <repository-url>
cd hyprWhisper
./install.sh
```

## Manual Installation

### 1. Install Dependencies (Fedora)

```bash
# Required dependencies
sudo dnf install git make gcc-c++ ffmpeg wl-clipboard

# Install Quickshell (if not already installed)
# See: https://github.com/quickshell-dev/quickshell
```

### 2. Compile whisper.cpp (CMake - Official Method)

```bash
mkdir -p ~/Apps
cd ~/Apps
git clone https://github.com/ggerganov/whisper.cpp.git
cd whisper.cpp

# Download model (small = fast, medium = balanced/best, large = most accurate)
bash ./models/download-ggml-model.sh medium

# Build with CMake
mkdir -p build && cd build

# For GPU (Vulkan - recommended):
cmake .. -DGGML_VULKAN=1

# For CPU only:
# cmake ..

# Compile with all CPU cores
cmake --build . -j$(nproc) --config Release
```

### 3. Install QML Components

Copy the QML files to your quickshell configuration:

```bash
# Create whisper module directory
mkdir -p ~/.config/quickshell/ii/modules/whisper

# Copy QML file
cp /path/to/hyprWhisper/qml/WhisperPopup.qml ~/.config/quickshell/ii/modules/whisper/

# Add to your shell.qml (see step 4)
```

### 4. Integrate with Quickshell

Add the Whisper popup to your quickshell configuration. Edit `~/.config/quickshell/ii/shell.qml`:

```qml
// Add import at the top
import "modules/whisper" as Whisper

// Add property to enable/disable
property bool enableWhisper: true

// Add LazyLoader inside ShellRoot
LazyLoader { active: enableWhisper; component: Whisper.WhisperPopup {} }
```

> **Note:** After modifying `shell.qml`, restart Quickshell (`qs -c ii`) for changes to take effect.

### 5. Install Script

```bash
mkdir -p ~/.local/bin
cp whisper-toggle.sh ~/.local/bin/
chmod +x ~/.local/bin/whisper-toggle.sh
```

### 6. Configure Hyprland

Add to `~/.config/hypr/hyprland.conf`:

```ini
# hyprWhisper voice-to-text
bind = $mainMod, D, exec, ~/.local/bin/whisper-toggle.sh
```

Reload Hyprland:
```bash
hyprctl reload
```

## Usage

1. Open any text editor or input field
2. Press `Super+D` to start recording
3. Speak clearly (popup shows "🎤 Gravant...")
4. Press `Super+D` again to stop
5. Wait for transcription (popup shows "⏳ Processant...")
6. **Native QML popup** appears with result (auto-closes after 5s)
7. Press **Ctrl+V** to paste the text

### UI Features

The native QML popup provides:

- **🎤 Recording phase**: Animated microphone icon with pulse effect
- **⏳ Processing phase**: Progress indicator with sliding animation
- **✓ Result phase**: Shows text preview (up to 5 lines), auto-closes in 5s
- **❌ Error phase**: Clear error messages
- **🎨 Theme integration**: Uses your Quickshell colors automatically
- **⌨️ Keyboard shortcuts**: Press `Esc` or `Enter` to close result popup

## How It Works

The script uses **Quickshell IPC** to communicate directly with the QML UI:

```
Script (whisper-toggle.sh)          QML (WhisperPopup.qml)
        |                                    |
        |   qs msg -c ii ipc call whisper    |
        |----------------------------------->|
        |                                    |
        |         Inicia ffmpeg              |
        |         Obre popup 🎤              |
        |                                    |
[segona crida]                               |
        |----------------------------------->|
        |                                    |
        |         Atura ffmpeg               |
        |         Inicia whisper-cli         |
        |         Mostra popup ⏳            |
        |                                    |
        |         Acaba whisper-cli          |
        |         Copia wl-copy              |
        |         Mostra popup ✓             |
        |                                    |
        |         Auto-tanca en 5s           |
```

This architecture completely manages its state natively within QML, eliminating the need for temporary state files or polling.

## Configuration

Environment variables (add to `~/.bashrc` or `~/.config/hypr/hyprland.conf` env):

```bash
# Path to whisper.cpp installation
export WHISPER_DIR="$HOME/Apps/whisper.cpp"

# Model to use
export WHISPER_MODEL="models/ggml-medium.bin"
```

Available models:
- `ggml-tiny.bin` - Fastest, least accurate
- `ggml-small.bin` - Fast, good accuracy
- `ggml-medium.bin` - Balanced/best (default)
- `ggml-large.bin` - Best accuracy, slowest

## Customization

### Change Popup Position

Edit `WhisperPopup.qml`:

```qml
// Center (default)
anchors.centerIn: parent

// Top center
anchors.horizontalCenter: parent.horizontalCenter
anchors.top: parent.top
anchors.topMargin: 50

// Bottom center
anchors.horizontalCenter: parent.horizontalCenter
anchors.bottom: parent.bottom
anchors.bottomMargin: 50
```

### Change Auto-close Time

Edit `WhisperPopup.qml`, line:

```qml
    // Auto-close timer for result/error
    Timer {
        id: autoCloseTimer
        interval: 5000  // Change this value (milliseconds)
    // ...
```

## Commands

```bash
# Toggle recording/transcription
whisper-toggle.sh

# Check if recording
whisper-toggle.sh --status

# Force stop if stuck
whisper-toggle.sh --stop

# Show help
whisper-toggle.sh --help
```

## Troubleshooting

### No popup appears

1. Check if Quickshell is running: `pgrep -f "qs -c"`
2. Restart Quickshell after installing/updating QML files: `qs -c ii`
3. Verify IPC works manually: `qs -c ii ipc call whisper toggle`
4. Check Quickshell output in the terminal where `qs -c ii` is running

### Popup doesn't auto-close

Check QML component is loaded correctly in your `shell.qml`

### Transcription is slow

- Use Vulkan: `cmake .. -DGGML_VULKAN=1`
- Use smaller model: `ggml-small.bin`
- Check GPU is being used: `vulkaninfo | grep deviceName`

### Check logs

```bash
tail -f /tmp/hyprwhisper.log
```

## Project Structure

```
hyprWhisper/
├── whisper-toggle.sh              # Main script (IPC sender)
├── qml/
│   └── WhisperPopup.qml           # UI popup + logic component
├── install.sh                     # Installation script
├── README.md                      # This file
└── AGENTS.md                      # Development guidelines
```

## License

MIT License - Feel free to use and modify!

## Credits

- [whisper.cpp](https://github.com/ggerganov/whisper.cpp) by Georgi Gerganov
- [Quickshell](https://github.com/quickshell-dev/quickshell) for the awesome shell framework
- OpenAI Whisper model
