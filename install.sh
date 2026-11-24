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
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/bin}"
readonly WHISPER_APPS_DIR="$HOME/Apps"
readonly QS_CONFIG="${QS_CONFIG:-ii}"
readonly WHISPER_BACKEND="${WHISPER_BACKEND:-auto}"   # auto, cuda, vulkan, cpu
readonly QUICKSHELL_MODULE_PATH="$HOME/.config/quickshell/$QS_CONFIG/modules/whisper"

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

check_os() {
    if [[ -f /etc/os-release ]]; then
        local id
        id=$(. /etc/os-release && echo "${ID:-unknown}")
        log_info "Detected OS: $id"
    fi
}

install_dependencies() {
    log_step "Installing system dependencies..."
    
    local deps
    if command -v dnf &> /dev/null; then
        deps=("git" "make" "cmake" "gcc-c++" "ffmpeg" "wl-clipboard")
        if command -v vulkaninfo &> /dev/null; then
            deps+=("vulkan-headers" "vulkan-loader-devel" "glslc" "spirv-headers-devel")
        fi
        sudo dnf install -y "${deps[@]}"
    elif command -v pacman &> /dev/null; then
        deps=("git" "make" "cmake" "gcc" "ffmpeg" "wl-clipboard")
        if command -v vulkaninfo &> /dev/null; then
            deps+=("vulkan-headers" "vulkan-icd-loader" "shaderc" "spirv-headers")
        fi
        sudo pacman -S --needed --noconfirm "${deps[@]}"
    else
        log_error "Unsupported package manager. Please install manually:"
        echo "  Fedora: git make cmake gcc-c++ ffmpeg wl-clipboard"
        echo "          (Vulkan build: vulkan-headers vulkan-loader-devel glslc spirv-headers-devel)"
        echo "  Arch:   git make cmake gcc ffmpeg wl-clipboard"
        echo "          (Vulkan build: vulkan-headers vulkan-icd-loader shaderc spirv-headers)"
        exit 1
    fi
    
    log_info "Dependencies installed"
}

has_spirv_headers() {
    compgen -G "/usr/share/cmake/SPIRV-Headers*/SPIRV-HeadersConfig.cmake" > /dev/null \
        || compgen -G "/usr/lib*/cmake/SPIRV-Headers*/SPIRV-HeadersConfig.cmake" > /dev/null
}

find_nvcc() {
    local candidate
    for candidate in "$(command -v nvcc 2>/dev/null)" /opt/cuda/bin/nvcc /usr/local/cuda/bin/nvcc; do
        if [[ -n "$candidate" && -x "$candidate" ]]; then
            echo "$candidate"
            return 0
        fi
    done
    return 1
}

has_cuda() {
    command -v nvidia-smi &> /dev/null && find_nvcc > /dev/null
}

has_vulkan_build_deps() {
    command -v vulkaninfo &> /dev/null && command -v glslc &> /dev/null \
        && [[ -f /usr/include/vulkan/vulkan.h ]] && has_spirv_headers
}

# nvcc only supports a limited range of GCC versions (e.g. CUDA 13.x doesn't
# accept GCC 16), so reuse the host compiler the distro configures for it
cuda_host_compiler() {
    if [[ -n "${NVCC_CCBIN:-}" ]]; then
        echo "$NVCC_CCBIN"
    elif [[ -f /etc/profile.d/cuda.sh ]]; then
        sed -n "s/^export NVCC_CCBIN=['\"]\?\([^'\"]*\)['\"]\?$/\1/p" /etc/profile.d/cuda.sh
    fi
}

configure_cuda() {
    local nvcc host_cxx compute_cap
    local args=(-DGGML_CUDA=1)

    nvcc=$(find_nvcc)
    args+=("-DCMAKE_CUDA_COMPILER=$nvcc")

    host_cxx=$(cuda_host_compiler)
    if [[ -n "$host_cxx" ]]; then
        args+=("-DCMAKE_CUDA_HOST_COMPILER=$host_cxx")
    fi

    # Build kernels only for the installed GPU (e.g. "8.9" -> 89): much faster
    compute_cap=$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>/dev/null | head -1 | tr -d '. ')
    if [[ "$compute_cap" =~ ^[0-9]+$ ]]; then
        args+=("-DCMAKE_CUDA_ARCHITECTURES=$compute_cap")
    fi

    log_info "CUDA detected - compiling with NVIDIA GPU support (${args[*]})"
    cmake .. "${args[@]}"
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
        git clone https://github.com/ggml-org/whisper.cpp.git
        cd whisper.cpp
    fi
    
    # Download model
    log_info "Downloading medium model..."
    bash ./models/download-ggml-model.sh medium
    
    # Compile with CMake
    log_info "Compiling whisper.cpp with CMake..."
    mkdir -p build && cd build

    # A stale cache (e.g. from another distro) can point to tools that no longer
    # exist, like /usr/bin/gmake, so always configure from scratch
    rm -rf CMakeCache.txt CMakeFiles
    
    case "$WHISPER_BACKEND" in
        cuda)
            if ! has_cuda; then
                log_error "WHISPER_BACKEND=cuda but nvidia-smi or nvcc (CUDA toolkit) was not found"
                exit 1
            fi
            configure_cuda
            ;;
        vulkan)
            if ! has_vulkan_build_deps; then
                log_error "WHISPER_BACKEND=vulkan but build deps are missing (vulkan headers / glslc / spirv-headers)"
                exit 1
            fi
            log_info "Compiling with Vulkan GPU support"
            cmake .. -DGGML_VULKAN=1
            ;;
        cpu)
            log_info "Compiling for CPU only"
            cmake ..
            ;;
        auto)
            if has_cuda; then
                configure_cuda
            elif has_vulkan_build_deps; then
                log_info "Vulkan detected - compiling with GPU support"
                cmake .. -DGGML_VULKAN=1
            else
                if command -v nvidia-smi &> /dev/null; then
                    log_warn "NVIDIA GPU found but no CUDA toolkit (Arch: cuda, Fedora: cuda from NVIDIA's repo)"
                fi
                if command -v vulkaninfo &> /dev/null; then
                    log_warn "Vulkan runtime found but build deps are missing (vulkan headers / glslc / spirv-headers)"
                fi
                log_warn "Compiling for CPU only. Install GPU build deps and recompile for GPU support"
                cmake ..
            fi
            ;;
        *)
            log_error "Invalid WHISPER_BACKEND '$WHISPER_BACKEND' (use auto, cuda, vulkan or cpu)"
            exit 1
            ;;
    esac
    
    cmake --build . -j"$(nproc)" --config Release
    
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
    if [[ -f "$SCRIPT_DIR/qml/WhisperPopup.qml" ]]; then
        cp "$SCRIPT_DIR/qml/"*.qml "$QUICKSHELL_MODULE_PATH/"
        log_info "QML components installed to $QUICKSHELL_MODULE_PATH"
    elif [[ -f "$SCRIPT_DIR/WhisperPopup.qml" ]]; then
        # Files in root directory
        cp "$SCRIPT_DIR/"Whisper*.qml "$QUICKSHELL_MODULE_PATH/"
        log_info "QML components installed to $QUICKSHELL_MODULE_PATH"
    else
        log_warn "QML files not found in repository"
        log_warn "You need to manually copy them:"
        echo "  mkdir -p $QUICKSHELL_MODULE_PATH"
        echo "  cp WhisperPopup.qml $QUICKSHELL_MODULE_PATH/"
    fi
}

show_quickshell_integration() {
    cat << 'EOF'

================================================================================
Quickshell Integration Required
================================================================================

You need to add the Whisper popup to your quickshell configuration.

Edit your Quickshell shell.qml (e.g. ~/.config/quickshell/ii/shell.qml) and add:

  1. Import at the top:
     import "modules/whisper" as Whisper

  2. Inside ShellRoot, add a property to enable/disable it:
     property bool enableWhisper: true

  3. Also inside ShellRoot, add a LazyLoader:
     LazyLoader { active: enableWhisper; component: Whisper.WhisperPopup {} }

IMPORTANT: After installing, you must restart Quickshell for changes
to take effect. The popup communicates via IPC, so it responds instantly
to toggle commands without polling.

================================================================================
EOF
}

show_hyprland_config() {
    cat << 'EOF'

================================================================================
Hyprland Configuration
================================================================================

Add a keybind (SUPER+D is already "Window: Maximize" in the ii config).
Skip this if you already have one.

  Lua config (e.g. ~/.config/hypr/custom/keybinds.lua):
    hl.bind("SUPER+ALT+D", hl.dsp.exec_cmd("$HOME/.local/bin/whisper-toggle.sh"), {description = "Whisper: toggle dictation"})

  Classic config (~/.config/hypr/hyprland.conf):
    bind = SUPER ALT, D, exec, ~/.local/bin/whisper-toggle.sh

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
2. Restart Quickshell: qs kill -c $QS_CONFIG && qs -c $QS_CONFIG -d
3. Add the keybind if you don't have one yet (see instructions above)
4. Check: ~/.local/bin/whisper-toggle.sh --status  (should print: idle)
5. Test: press Super+Alt+D, speak, press it again and paste with Ctrl+V

Troubleshooting:
- Check the module is loaded: ~/.local/bin/whisper-toggle.sh --status
- Check logs: qs log -c $QS_CONFIG
- Verify QML: ls -la $QUICKSHELL_MODULE_PATH/
- If popup doesn't appear, restart Quickshell (required after install)

Model location: $WHISPER_APPS_DIR/whisper.cpp/models/ggml-medium.bin

UI Features:
- Native QML popup integrated with your theme
- Waveform while recording, progress bar while transcribing
- Auto-closes 3 seconds after the result (red bar on error)
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
    
    check_os
    
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
