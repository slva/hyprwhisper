#!/bin/bash
#
# hyprWhisper Installation Script
#

set -euo pipefail

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m' # No Color

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/bin}"
readonly WHISPER_APPS_DIR="$HOME/Apps"

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_fedora() {
    if [[ ! -f /etc/fedora-release ]]; then
        log_warn "This script is optimized for Fedora. Continuing anyway..."
    fi
}

install_dependencies() {
    log_info "Installing system dependencies..."
    
    local deps=("git" "make" "gcc-c++" "ffmpeg" "wl-clipboard" "libnotify" "ydotool")
    
    if command -v dnf &> /dev/null; then
        sudo dnf install -y "${deps[@]}"
    elif command -v apt &> /dev/null; then
        log_warn "APT detected. Package names may differ on Debian/Ubuntu."
        sudo apt update
        sudo apt install -y git make g++ ffmpeg wl-clipboard libnotify-bin ydotool
    else
        log_error "Unsupported package manager. Please install manually:"
        echo "  git make gcc-c++ ffmpeg wl-clipboard libnotify ydotool"
        exit 1
    fi
    
    # Enable ydotool service
    log_info "Enabling ydotool service..."
    sudo systemctl enable --now ydotool || {
        log_warn "Failed to enable ydotool service. You may need to do this manually."
    }
    
    # Add user to input group
    if ! groups "$USER" | grep -q '\binput\b'; then
        log_info "Adding user to 'input' group for ydotool..."
        sudo usermod -aG input "$USER"
        log_warn "Please log out and back in for group changes to take effect!"
    fi
}

compile_whisper() {
    log_info "Setting up whisper.cpp..."
    
    if [[ -d "$WHISPER_APPS_DIR/whisper.cpp" ]]; then
        log_warn "whisper.cpp already exists at $WHISPER_APPS_DIR/whisper.cpp"
        read -p "Recompile? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            return 0
        fi
        cd "$WHISPER_APPS_DIR/whisper.cpp"
    else
        mkdir -p "$WHISPER_APPS_DIR"
        cd "$WHISPER_APPS_DIR"
        git clone https://github.com/ggerganov/whisper.cpp.git
        cd whisper.cpp
    fi
    
    # Download model
    log_info "Downloading medium model..."
    bash ./models/download-ggml-model.sh medium
    
    # Compile with CMake (official method)
    log_info "Compiling whisper.cpp with CMake..."
    mkdir -p build && cd build
    
    # Check for GPU support
    if command -v vulkaninfo &> /dev/null; then
        log_info "Vulkan detected - compiling with GPU support (recommended for Fedora 43+)"
        cmake .. -DGGML_VULKAN=1
    elif command -v nvcc &> /dev/null; then
        log_warn "CUDA detected but may have compatibility issues with GCC 14+"
        log_warn "Consider using Vulkan instead: sudo dnf install vulkan-tools vulkan-loader-devel"
        read -p "Compile with CUDA anyway? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            cmake .. -DGGML_CUDA=1
        else
            log_info "Compiling for CPU only"
            cmake ..
        fi
    else
        log_info "Compiling for CPU only"
        cmake ..
    fi
    
    cmake --build . -j$(nproc) --config Release
    
    log_info "whisper.cpp compiled successfully!"
    log_info "Executables are in: $WHISPER_APPS_DIR/whisper.cpp/build/bin/"
}

install_script() {
    log_info "Installing whisper-toggle.sh..."
    
    mkdir -p "$INSTALL_DIR"
    
    if [[ -f "$SCRIPT_DIR/whisper-toggle.sh" ]]; then
        cp "$SCRIPT_DIR/whisper-toggle.sh" "$INSTALL_DIR/"
        chmod +x "$INSTALL_DIR/whisper-toggle.sh"
        log_info "Script installed to $INSTALL_DIR/whisper-toggle.sh"
    else
        log_error "whisper-toggle.sh not found in $SCRIPT_DIR"
        exit 1
    fi
    
    # Check if INSTALL_DIR is in PATH
    if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
        log_warn "$INSTALL_DIR is not in your PATH"
        echo "Add this to your ~/.bashrc or ~/.zshrc:"
        echo "  export PATH=\"$INSTALL_DIR:\$PATH\""
    fi
}

show_hyprland_config() {
    cat << 'EOF'

================================================================================
Hyprland Configuration
================================================================================

Add this to your ~/.config/hypr/hyprland.conf:

# hyprWhisper voice-to-text
# IMPORTANT: $mainMod must be defined at the top of your config!
# Example: $mainMod = SUPER
bind = $mainMod, D, exec, ~/.local/bin/whisper-toggle.sh

Or use SUPER directly (no variable needed):
  bind = SUPER, D, exec, ~/.local/bin/whisper-toggle.sh

Other options:
  bind = ALT, D, exec, ~/.local/bin/whisper-toggle.sh
  bind = SHIFT SUPER, R, exec, ~/.local/bin/whisper-toggle.sh
  bind = ,XF86AudioMicMute, exec, ~/.local/bin/whisper-toggle.sh

================================================================================
EOF
}

show_next_steps() {
    cat << EOF

================================================================================
Installation Complete!
================================================================================

Next steps:
1. Log out and back in (for ydotool group permissions)
2. Add the keybinding to your Hyprland config (shown above)
3. Reload Hyprland: hyprctl reload
4. Test: Open a text editor and press Super+D (or your chosen keybind)

Troubleshooting:
- Check logs: tail -f /tmp/hyprwhisper.log
- Test manually: ~/.local/bin/whisper-toggle.sh --help
- Check status: ~/.local/bin/whisper-toggle.sh --status

Model location: $WHISPER_APPS_DIR/whisper.cpp/models/ggml-medium.bin

For better accuracy, download the medium model:
  cd $WHISPER_APPS_DIR/whisper.cpp
  bash ./models/download-ggml-model.sh medium

Then set in your environment:
  export WHISPER_MODEL=models/ggml-medium.bin

================================================================================
EOF
}

main() {
    echo "========================================"
    echo "  hyprWhisper Installer"
    echo "========================================"
    echo
    
    check_fedora
    
    read -p "Install system dependencies? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        install_dependencies
    fi
    
    read -p "Compile whisper.cpp? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        compile_whisper
    fi
    
    install_script
    
    show_hyprland_config
    show_next_steps
}

main "$@"
