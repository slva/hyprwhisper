# hyprWhisper

Voice-to-text integration for Hyprland using OpenAI's Whisper.

## Features

- 🎤 One-key toggle to start/stop recording
- ⚡ Real-time transcription using whisper.cpp (C++)
- 📋 Automatic clipboard copy and paste
- 🖥️ Native Wayland support (wl-clipboard)
- 🔔 Desktop notifications
- 🔒 No cloud services - 100% local processing

## Requirements

- **OS**: Fedora Linux (or any Linux with Wayland)
- **Desktop**: Hyprland (or any Wayland compositor)
- **Hardware**: Microphone
- **Optional**: NVIDIA GPU for faster transcription

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

# Recommended: wofi for result display (Hyprland native)
sudo dnf install wofi

# Optional: ydotool for automatic paste (requires additional setup)
# sudo dnf install ydotool
# sudo systemctl enable --now ydotool
# sudo usermod -aG input $USER
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

# For GPU (Vulkan - recommended, supports NVIDIA/AMD/Intel):
# Note: CUDA has compatibility issues with GCC 14+ on Fedora 43+
cmake .. -DGGML_VULKAN=1

# Alternative: For NVIDIA GPU (CUDA) - requires GCC 12/13:
# cmake .. -DGGML_CUDA=1

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

### 3. Install Script

```bash
mkdir -p ~/.local/bin
cp whisper-toggle.sh ~/.local/bin/
chmod +x ~/.local/bin/whisper-toggle.sh
```

### 4. Configure Hyprland

Add to `~/.config/hypr/hyprland.conf`:

```ini
# hyprWhisper voice-to-text
# Note: $mainMod must be defined at the top of your config (e.g., $mainMod = SUPER)
# Or use SUPER directly: bind = SUPER, D, exec, ~/.local/bin/whisper-toggle.sh
bind = $mainMod, D, exec, ~/.local/bin/whisper-toggle.sh
```

**Note:** `$mainMod` is a variable that must be defined. Most configs have `$mainMod = SUPER` at the top.
If it doesn't work, use `SUPER` directly: `bind = SUPER, D, exec, ~/.local/bin/whisper-toggle.sh`

Reload Hyprland:
```bash
hyprctl reload
```

## Usage

1. Open any text editor or input field
2. Press `Super+D` to start recording (no visual feedback - just speak)
3. Speak clearly
4. Press `Super+D` again to stop
5. **Wofi window appears** with the transcribed text (auto-closes after 5s)
6. Press **Ctrl+V** to paste the text where you want it

### Interface

- **During recording**: No window (speak naturally)
- **After transcription**: Wofi window shows the text
  - Displays the transcribed text
  - Auto-closes after 5 seconds
  - Or press Enter to close immediately
  - Text is already copied to clipboard

## Configuration

Environment variables (add to `~/.bashrc` or `~/.config/hypr/hyprland.conf` env):

```bash
# Path to whisper.cpp installation
export WHISPER_DIR="$HOME/Apps/whisper.cpp"

# Model to use (small, medium, large)
export WHISPER_MODEL="models/ggml-medium.bin"

```

Available models:
- `ggml-tiny.bin` - Fastest, least accurate
- `ggml-small.bin` - Fast, good accuracy
- `ggml-medium.bin` - Balanced/best (default)
- `ggml-large.bin` - Best accuracy, slowest

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

### Recording works but no text appears

Check logs:
```bash
tail -f /tmp/hyprwhisper.log
```

Test whisper.cpp directly:
```bash
ffmpeg -f pulse -i default -t 5 -ar 16000 -ac 1 /tmp/test.wav
~/Apps/whisper.cpp/build/bin/whisper-cli -m ~/Apps/whisper.cpp/models/ggml-medium.bin -f /tmp/test.wav -l auto -nt
```

### ydotool paste not working

1. Ensure service is running: `systemctl status ydotool`
2. Check you're in the `input` group: `groups $USER`
3. Log out and back in after group changes

### Poor transcription quality

1. Speak clearly and close to microphone
2. Try the medium model for better accuracy
3. Set specific language: Edit script and change `-l auto` to `-l ca` (Catalan) or `-l es` (Spanish)

## Project Structure

```
hyprWhisper/
├── whisper-toggle.sh    # Main toggle script
├── install.sh           # Installation script
├── README.md            # This file
└── AGENTS.md            # Development guidelines
```

## License

MIT License - Feel free to use and modify!

## Credits

- [whisper.cpp](https://github.com/ggerganov/whisper.cpp) by Georgi Gerganov
- OpenAI Whisper model
