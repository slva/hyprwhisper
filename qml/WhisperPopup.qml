import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import qs.modules.common

Scope {
    id: scope

    // ========================================================================
    // STATE
    // ========================================================================
    property string phase: "idle"       // idle, recording, processing, result, error
    property string resultText: ""

    // Raw transcription output, collected while whisper-cli runs
    property string transcriptOutput: ""
    property bool transcribeExited: false
    property int transcribeExitCode: -1

    // ========================================================================
    // CONFIG
    // ========================================================================
    // Read from Quickshell's environment (e.g. `env = WHISPER_DIR,...` in hyprland.conf)
    readonly property string whisperDir: Quickshell.env("WHISPER_DIR") || (Quickshell.env("HOME") + "/Apps/whisper.cpp")
    readonly property string whisperModel: Quickshell.env("WHISPER_MODEL") || "models/ggml-medium.bin"
    // XDG_RUNTIME_DIR is private to the user (0700), unlike /tmp
    readonly property string audioFile: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/hyprwhisper_audio.wav"

    readonly property int autoCloseMs: 3000
    readonly property int bottomMargin: 20    // distance from the bottom edge of the screen
    readonly property int processingTimeoutMs: 5 * 60 * 1000

    // ========================================================================
    // IPC HANDLER - receives toggle/stop/status from the keybind script
    // ========================================================================
    IpcHandler {
        target: "whisper"

        function toggle(): void {
            if (scope.phase === "idle") {
                scope.startRecording();
            } else if (scope.phase === "recording") {
                scope.stopRecordingAndTranscribe();
            } else if (scope.phase === "result" || scope.phase === "error") {
                scope.reset();
            }
        }

        function stop(): void {
            scope.reset();
            if (recordProcess.running) recordProcess.signal(15); // SIGTERM
            if (transcribeProcess.running) transcribeProcess.signal(15);
        }

        function status(): string {
            return scope.phase;
        }
    }

    // ========================================================================
    // FUNCTIONS
    // ========================================================================
    function startRecording() {
        // A previous ffmpeg/whisper-cli may still be shutting down after a stop
        if (recordProcess.running || transcribeProcess.running) {
            console.warn("[hyprWhisper] Previous process still running, ignoring toggle");
            return;
        }

        phase = "recording";
        resultText = "";

        // ffmpeg overwrites the old audio file thanks to -y
        recordProcess.running = true;
    }

    function stopRecordingAndTranscribe() {
        phase = "processing";
        processingTimeout.restart();

        // Stop ffmpeg via SIGTERM (INT doesn't work well with ffmpeg)
        recordProcess.signal(15);
    }

    // Called whenever ffmpeg stops running, including when it failed to start
    function recordingEnded() {
        if (phase === "processing") {
            transcriptOutput = "";
            transcribeExited = false;
            transcribeExitCode = -1;
            transcribeProcess.running = true;
            return;
        }

        if (phase === "recording") {
            showError("No s'ha pogut gravar l'àudio (ffmpeg ha fallat)");
        }
        deleteAudio();
    }

    // Called whenever whisper-cli stops running, including when it failed to start
    function transcriptionEnded() {
        deleteAudio();
        if (phase !== "processing") return; // stopped or timed out

        processingTimeout.stop();

        if (!transcribeExited) {
            showError("No s'ha pogut executar " + transcribeProcess.whisperBin);
        } else if (transcribeExitCode !== 0) {
            showError("Transcripció fallida (codi " + transcribeExitCode + ")");
        } else {
            handleTranscriptionResult(transcriptOutput);
        }
    }

    function handleTranscriptionResult(text) {
        const cleaned = cleanTranscript(text);
        if (cleaned.length === 0) {
            showError("No s'ha detectat veu");
            return;
        }

        resultText = cleaned;
        phase = "result";

        clipboardProcess.running = true;
        autoCloseTimer.restart();
    }

    function showError(message) {
        console.warn("[hyprWhisper] " + message);
        processingTimeout.stop();
        phase = "error";
        autoCloseTimer.restart();
    }

    function reset() {
        phase = "idle";
        resultText = "";
        autoCloseTimer.stop();
        processingTimeout.stop();
    }

    function deleteAudio() {
        cleanProcess.running = true;
    }

    // Joins whisper segments into one line and drops non-speech tags
    // such as [BLANK_AUDIO], [ Silence ] or (music)
    function cleanTranscript(text) {
        return (text || "")
            .split("\n")
            .map(line => line.trim())
            .filter(line => line.length > 0 && !/^[\[(][^\])]*[\])]$/.test(line))
            .join(" ");
    }

    // ========================================================================
    // PROCESSES
    // ========================================================================

    // Remove the recorded audio once it is no longer needed
    Process {
        id: cleanProcess
        running: false
        command: ["rm", "-f", scope.audioFile]
    }

    // FFmpeg recording
    Process {
        id: recordProcess
        running: false
        command: [
            "ffmpeg", "-f", "pulse", "-i", "default",
            "-y", "-ar", "16000", "-ac", "1", "-c:a", "pcm_s16le",
            scope.audioFile
        ]
        onRunningChanged: if (!running) scope.recordingEnded()
    }

    // Whisper transcription
    // Signal order on a normal exit: streamFinished -> exited -> runningChanged.
    // If the binary can't be started only runningChanged is emitted.
    Process {
        id: transcribeProcess
        running: false
        property string whisperBin: scope.whisperDir + "/build/bin/whisper-cli"
        command: [
            transcribeProcess.whisperBin,
            "-m", scope.whisperDir + "/" + scope.whisperModel,
            "-f", scope.audioFile,
            "-l", "auto",
            "-nt"
        ]
        stdout: StdioCollector {
            onStreamFinished: scope.transcriptOutput = this.text
        }
        onExited: (exitCode, exitStatus) => {
            scope.transcribeExited = true;
            scope.transcribeExitCode = exitCode;
        }
        onRunningChanged: if (!running) scope.transcriptionEnded()
    }

    // Clipboard copy ("--" so text starting with "-" isn't parsed as an option)
    Process {
        id: clipboardProcess
        running: false
        command: ["wl-copy", "--", scope.resultText]
    }

    // ========================================================================
    // POPUP WINDOW
    // ========================================================================
    PanelWindow {
        id: root

        visible: scope.phase !== "idle"

        WlrLayershell.layer: WlrLayer.Overlay
        exclusiveZone: 0

        // Only anchored to the bottom edge: horizontally centered, at the bottom
        anchors.bottom: true
        margins.bottom: scope.bottomMargin

        implicitWidth: 250
        implicitHeight: 50

        color: "transparent"

        Rectangle {
            anchors.fill: parent
            color: Appearance.colors.colLayer0 || "#1e1e1e"
            radius: 12
            border.color: Appearance.colors.colPrimary || "#cccccc"
            border.width: 2

            // Waveform for recording: pill-shaped bars mirrored around the
            // horizontal center line, short at the edges and tall in the middle
            Row {
                id: waveformContainer

                readonly property int barCount: 27
                readonly property int barWidth: 4
                readonly property real minBarHeight: barWidth * 2   // keeps the pill shape
                readonly property real maxBarHeight: 34

                spacing: barWidth
                height: maxBarHeight
                visible: scope.phase === "recording"
                anchors.centerIn: parent

                // 0..1 bell curve: ~0.1 at the edges, 1 in the center
                function envelope(index) {
                    const t = (index + 0.5) / barCount;
                    return 0.1 + 0.9 * Math.pow(Math.sin(Math.PI * t), 1.5);
                }

                function randomHeight(index) {
                    const level = envelope(index) * (0.2 + 0.8 * Math.random());
                    return minBarHeight + (maxBarHeight - minBarHeight) * level;
                }

                Repeater {
                    model: waveformContainer.barCount
                    Rectangle {
                        id: bar
                        required property int index

                        width: waveformContainer.barWidth
                        height: waveformContainer.randomHeight(index)
                        radius: width / 2
                        color: Appearance.colors.colPrimary || "#cbc4cb"
                        anchors.verticalCenter: parent.verticalCenter

                        Behavior on height {
                            NumberAnimation {
                                duration: 140
                                easing.type: Easing.InOutQuad
                            }
                        }

                        // New random height on every tick, only while recording
                        Timer {
                            interval: 110 + Math.random() * 140
                            running: waveformContainer.visible
                            repeat: true
                            onTriggered: bar.height = waveformContainer.randomHeight(bar.index)
                        }
                    }
                }
            }

            // Progress bar (indeterminate for processing, filling for result/error)
            Rectangle {
                id: progressBarBg
                width: parent.width - 40
                height: 4
                color: Appearance.colors.colLayer2 || "#333333"
                radius: 2
                visible: scope.phase === "processing" || scope.phase === "result" || scope.phase === "error"
                anchors.centerIn: parent

                Rectangle {
                    id: progressIndicator
                    height: parent.height
                    color: scope.phase === "error"
                        ? (Appearance.colors.colError || "#ff5555")
                        : (Appearance.colors.colSecondary || "#cac5c8")
                    radius: parent.radius
                    width: 0

                    states: [
                        State {
                            name: "processing"
                            when: scope.phase === "processing"
                            PropertyChanges {
                                target: progressIndicator
                                width: progressBarBg.width * 0.3
                                x: 0
                            }
                        },
                        State {
                            name: "filling"
                            when: scope.phase === "result" || scope.phase === "error"
                            PropertyChanges {
                                target: progressIndicator
                                width: progressBarBg.width
                                x: 0
                            }
                        }
                    ]

                    // Visual countdown only; autoCloseTimer closes the popup
                    transitions: [
                        Transition {
                            to: "filling"
                            SequentialAnimation {
                                // Reset position and width first
                                PropertyAction { property: "x"; value: 0 }
                                PropertyAction { property: "width"; value: 0 }
                                // Then animate filling from left to right
                                NumberAnimation {
                                    property: "width"
                                    duration: scope.autoCloseMs
                                    easing.type: Easing.InOutQuad
                                }
                            }
                        }
                    ]

                    // Indeterminate animation for processing
                    SequentialAnimation on x {
                        id: progressAnimation
                        running: scope.phase === "processing"
                        loops: Animation.Infinite
                        NumberAnimation {
                            from: 0
                            to: progressBarBg.width - progressIndicator.width
                            duration: 1000
                            easing.type: Easing.InOutQuad
                        }
                        NumberAnimation {
                            from: progressBarBg.width - progressIndicator.width
                            to: 0
                            duration: 1000
                            easing.type: Easing.InOutQuad
                        }
                    }
                }
            }

            // Click to close
            MouseArea {
                anchors.fill: parent
                enabled: scope.phase === "result" || scope.phase === "error"
                onClicked: scope.reset()
            }
        }
    }

    // ========================================================================
    // TIMERS
    // ========================================================================

    // Auto-close timer for result/error
    Timer {
        id: autoCloseTimer
        interval: scope.autoCloseMs
        running: false
        onTriggered: scope.reset()
    }

    // Safety net in case whisper-cli hangs
    Timer {
        id: processingTimeout
        interval: scope.processingTimeoutMs
        running: false
        onTriggered: {
            if (scope.phase !== "processing") return;
            scope.showError("Temps d'espera esgotat");
            if (recordProcess.running) recordProcess.signal(15);
            if (transcribeProcess.running) transcribeProcess.signal(15);
        }
    }
}
