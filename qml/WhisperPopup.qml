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
    property string errorMessage: ""

    // ========================================================================
    // COMPUTED PROPERTIES (for use in PanelWindow)
    // ========================================================================
    property string currentIcon: {
        switch(phase) {
            case "recording": return "\ue029"; // mic
            case "processing": return "\ue88c"; // hourglass
            case "result": return "\ue86c"; // check_circle
            case "error": return "\ue000"; // error
            default: return "";
        }
    }

    property color currentPhaseColor: {
        switch(phase) {
            case "recording": return Appearance.colors.colPrimary || "#ff5555";
            case "processing": return Appearance.colors.colSecondary || "#ffff55";
            case "result": return "#55ff55";
            case "error": return "#ff5555";
            default: return Appearance.colors.colText || "#ffffff";
        }
    }

    property string displayText: {
        switch(phase) {
            case "recording": return "Gravant...";
            case "processing": return "Processant...";
            case "result": return truncateText(resultText, 5);
            case "error": return errorMessage || "Error";
            default: return "";
        }
    }

    // Whisper config (same defaults as the old script)
    readonly property string whisperDir: "/home/slva/Apps/whisper.cpp"
    readonly property string whisperModel: "models/ggml-medium.bin"
    readonly property string audioFile: "/tmp/hyprwhisper_audio.wav"
    readonly property string logFile: "/tmp/hyprwhisper.log"

    // ========================================================================
    // IPC HANDLER - receives toggle/stop from keybind
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
            if (scope.phase === "recording") {
                recordProcess.signal(15); // SIGTERM
            }
            scope.reset();
        }
    }

    // ========================================================================
    // FUNCTIONS
    // ========================================================================
    function startRecording() {
        // Clean old audio
        cleanProcess.running = true;

        phase = "recording";
        resultText = "";
        errorMessage = "";

        // Start ffmpeg recording
        recordProcess.running = true;
    }

    function stopRecordingAndTranscribe() {
        phase = "processing";

        // Stop ffmpeg via SIGTERM (INT doesn't work well with ffmpeg)
        recordProcess.signal(15);
    }

    function handleTranscriptionResult(text) {
        const trimmed = text.replace(/^\s+|\s+$/g, '');
        if (trimmed.length === 0) {
            phase = "error";
            errorMessage = "No s'ha detectat veu";
            autoCloseTimer.start();
            return;
        }

        resultText = trimmed;
        phase = "result";

        // Copy to clipboard
        clipboardProcess.running = true;

        // Start auto-close countdown
        autoCloseTimer.start();
    }

    function reset() {
        phase = "idle";
        resultText = "";
        errorMessage = "";
        autoCloseTimer.stop();
        countdownTimer.stop();
    }

    // ========================================================================
    // PROCESSES
    // ========================================================================

    // Clean old audio file
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
        onExited: (exitCode, exitStatus) => {
            if (scope.phase === "processing") {
                // Recording was stopped intentionally, start transcription
                transcribeProcess.running = true;
            }
        }
    }

    // Whisper transcription
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
            onStreamFinished: {
                scope.handleTranscriptionResult(this.text);
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0 && scope.phase === "processing") {
                scope.phase = "error";
                scope.errorMessage = "Transcripció fallida";
                scope.autoCloseTimer.start();
            }
        }
    }

    // Clipboard copy
    Process {
        id: clipboardProcess
        running: false
        command: ["wl-copy", scope.resultText]
    }

    // ========================================================================
    // POPUP WINDOW
    // ========================================================================
    PanelWindow {
        id: root

        visible: scope.phase !== "idle"

        WlrLayershell.layer: WlrLayer.Overlay
        exclusiveZone: 0

        implicitWidth: 250
        implicitHeight: 50

        color: "transparent"

        Rectangle {
            width: 250
            height: 50
            x: 0
            y: 0
            color: Appearance.colors.colLayer0 || "#1e1e1e"
            radius: 12
            border.color: Appearance.colors.colPrimary || "#cccccc"
            border.width: 2

            // Shadow
            Rectangle {
                width: parent.width
                height: parent.height
                x: -4
                y: -4
                color: "#000000"
                opacity: 0.3
                radius: parent.radius + 2
                z: -1
            }

            // Waveform for recording (35 bars, fills width)
            Row {
                id: waveformContainer
                spacing: 2
                visible: scope.phase === "recording"
                anchors.centerIn: parent

                Repeater {
                    model: 35
                    Rectangle {
                        width: 4
                        height: 30
                        color: Appearance.colors.colPrimary || "#cbc4cb"
                        radius: 2
                        anchors.bottom: parent.bottom

                        SequentialAnimation on height {
                            loops: Animation.Infinite
                            NumberAnimation {
                                to: 5 + Math.random() * 25
                                duration: 100 + Math.random() * 150
                                easing.type: Easing.InOutQuad
                            }
                            NumberAnimation {
                                to: 10 + Math.random() * 20
                                duration: 100 + Math.random() * 150
                                easing.type: Easing.InOutQuad
                            }
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
                                width: parent.width * 0.3
                            }
                        },
                        State {
                            name: "filling"
                            when: scope.phase === "result" || scope.phase === "error"
                            PropertyChanges {
                                target: progressIndicator
                                width: parent.width
                            }
                        }
                    ]

                    transitions: [
                        Transition {
                            from: "processing"
                            to: "filling"
                            SequentialAnimation {
                                NumberAnimation { 
                                    property: "width"
                                    duration: 3000
                                    easing.type: Easing.InOutQuad
                                }
                                ScriptAction {
                                    script: scope.reset()
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
                width: parent.width
                height: parent.height
                enabled: scope.phase === "result" || scope.phase === "error"
                onClicked: {
                    scope.reset();
                }
            }
        }
    }

    // ========================================================================
    // TIMERS
    // ========================================================================

    // Auto-close timer for result/error
    Timer {
        id: autoCloseTimer
        interval: 5000
        running: false
        onTriggered: {
            scope.reset();
        }

        property int remainingTime: interval
        onRunningChanged: if (running) remainingTime = interval
    }

    // Countdown display timer
    Timer {
        id: countdownTimer
        interval: 1000
        running: autoCloseTimer.running
        repeat: true
        onTriggered: {
            if (autoCloseTimer.remainingTime > 0) {
                autoCloseTimer.remainingTime -= 1000;
            }
        }
    }

    // ========================================================================
    // HELPER FUNCTIONS
    // ========================================================================
    function getIcon() {
        switch(scope.phase) {
            case "recording": return "\ue029";    // mic
            case "processing": return "\ue88c";  // hourglass
            case "result": return "\ue86c";      // check_circle
            case "error": return "\ue000";       // error
            default: return "";
        }
    }

    function getPhaseColor() {
        switch(scope.phase) {
            case "recording": return Appearance.colors.colPrimary || "#ff5555";
            case "processing": return Appearance.colors.colSecondary || "#ffff55";
            case "result": return "#55ff55";
            case "error": return "#ff5555";
            default: return Appearance.colors.colText || "#ffffff";
        }
    }

    function getDisplayText() {
        switch(scope.phase) {
            case "recording":
                return "Gravant...";
            case "processing":
                return "Processant...";
            case "result":
                return truncateText(scope.resultText, 5);
            case "error":
                return scope.errorMessage || "Error";
            default:
                return "";
        }
    }

    function truncateText(text, maxLines) {
        if (!text) return "";
        const lines = text.split('\n');
        if (lines.length <= maxLines) return text;
        return lines.slice(0, maxLines).join('\n') + "...";
    }
}
