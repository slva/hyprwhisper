#!/bin/bash
#
# hyprWhisper Installation Script
# Installs bash script and QML components for Quickshell
#

set -euo pipefail

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/bin}"
readonly WHISPER_APPS_DIR="$HOME/Apps"
readonly QUICKSHELL_MODULE_PATH="$HOME/.config/quickshell/ii/modules/whisper"

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

check_fedora() {
    if [[ ! -f /etc/fedora-release ]]; then
        log_warn "This script is optimized for Fedora. Continuing anyway..."
    fi
}

install_dependencies() {
    log_step "Installing system dependencies..."
    
    local deps=("git" "make" "gcc-c++" "ffmpeg" "wl-clipboard")
    
    if command -v dnf &> /dev/null; then
        sudo dnf install -y "${deps[@]}"
    else
        log_error "Unsupported package manager. Please install manually:"
        echo "  git make gcc-c++ ffmpeg wl-clipboard"
        exit 1
    fi
    
    log_info "Dependencies installed"
}

compile_whisper() {
    log_step "Setting up whisper.cpp..."
    
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
    
    # Compile with CMake
    log_info "Compiling whisper.cpp with CMake..."
    mkdir -p build && cd build
    
    if command -v vulkaninfo &> /dev/null; then
        log_info "Vulkan detected - compiling with GPU support"
        cmake .. -DGGML_VULKAN=1
    else
        log_info "Compiling for CPU only"
        cmake ..
    fi
    
    cmake --build . -j$(nproc) --config Release
    
    log_info "whisper.cpp compiled successfully!"
    log_info "Executables are in: $WHISPER_APPS_DIR/whisper.cpp/build/bin/"
}

install_script() {
    log_step "Installing whisper-toggle.sh..."
    
    mkdir -p "$INSTALL_DIR"
    
    if [[ -f "$SCRIPT_DIR/whisper-toggle.sh" ]]; then
        cp "$SCRIPT_DIR/whisper-toggle.sh" "$INSTALL_DIR/"
        chmod +x "$INSTALL_DIR/whisper-toggle.sh"
        log_info "Script installed to $INSTALL_DIR/whisper-toggle.sh"
    else
        log_error "whisper-toggle.sh not found in $SCRIPT_DIR"
        exit 1
    fi
}

install_qml_components() {
    log_step "Installing QML components..."
    
    # Create directory
    mkdir -p "$QUICKSHELL_MODULE_PATH"
    
    # Check if QML files exist in repo
    if [[ -f "$SCRIPT_DIR/qml/WhisperState.qml" && -f "$SCRIPT_DIR/qml/WhisperPopup.qml" ]]; then
        cp "$SCRIPT_DIR/qml/"*.qml "$QUICKSHELL_MODULE_PATH/"
        log_info "QML components installed to $QUICKSHELL_MODULE_PATH"
    elif [[ -f "$SCRIPT_DIR/WhisperState.qml" && -f "$SCRIPT_DIR/WhisperPopup.qml" ]]; then
        # Files in root directory
        cp "$SCRIPT_DIR/"Whisper*.qml "$QUICKSHELL_MODULE_PATH/"
        log_info "QML components installed to $QUICKSHELL_MODULE_PATH"
    else
        log_warn "QML files not found in repository"
        log_warn "You need to manually copy them:"
        echo "  mkdir -p $QUICKSHELL_MODULE_PATH"
        echo "  cp WhisperState.qml WhisperPopup.qml $QUICKSHELL_MODULE_PATH/"
    fi
}

show_quickshell_integration() {
    cat << 'EOF'

================================================================================
Quickshell Integration Required
================================================================================

You need to add the Whisper popup to your quickshell configuration.

Edit ~/.config/quickshell/ii/shell.qml and add:

  1. Import at the top:
     import "modules/whisper" as Whisper

  2. Add component inside your main Shell:
     Whisper.WhisperPopup {
         // Auto-shows based on state
     }

Example:

  Shell {
      // ... your existing config ...
      
      // Add this:
      Whisper.WhisperPopup {}
  }

================================================================================
EOF
}

show_hyprland_config() {
    cat << 'EOF'

================================================================================
Hyprland Configuration
================================================================================

Add to ~/.config/hypr/hyprland.conf:

    # hyprWhisper voice-to-text
    bind = $mainMod, D, exec, ~/.local/bin/whisper-toggle.sh

Reload Hyprland:

    hyprctl reload

================================================================================
EOF
}

show_next_steps() {
    cat << EOF

================================================================================
Installation Complete!
================================================================================

Next steps:
1. Add WhisperPopup to your shell.qml (see instructions above)
2. Restart Quickshell or reload configuration
3. Reload Hyprland: hyprctl reload
4. Test: Press Super+D and speak

Troubleshooting:
- Check logs: tail -f /tmp/hyprwhisper.log
- Test script: ~/.local/bin/whisper-toggle.sh --help
- Check state file: cat /tmp/whisper_state.json
- Verify QML: ls -la $QUICKSHELL_MODULE_PATH/

Model location: $WHISPER_APPS_DIR/whisper.cpp/models/ggml-medium.bin

UI Features:
- Native QML popup integrated with your theme
- Shows recording/processing/result phases
- Auto-closes after 5 seconds
- Press Ctrl+V to paste text

================================================================================
EOF
}

main() {
    echo "========================================"
    echo "  hyprWhisper Installer"
    echo "  Native QML UI for Quickshell"
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
    install_qml_components
    
    show_quickshell_integration
    show_hyprland_config
    show_next_steps
}

main "$@"
