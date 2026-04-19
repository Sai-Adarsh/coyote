import AppKit
import AVFAudio
import Combine
import CoreGraphics
@preconcurrency import ScreenCaptureKit
import Speech
import SwiftUI

struct CaptionEntry: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let timestamp = Date()
}

struct TranscriptPanelState {
    let title: String
    let icon: String
    let placeholder: String
    var liveText = ""
    var finalized: [CaptionEntry] = []
    var level: Double = 0.02
}

@MainActor
final class CaptionBarViewModel: ObservableObject {
    @Published var captionPanel = TranscriptPanelState(
        title: "Live Captions",
        icon: "waveform.badge.mic",
        placeholder: "Mic + system audio captions appear here…"
    )
    @Published var statusMessage = "Ready for live captions"
    @Published var detailMessage = "Grant permissions, then start the live microphone + system-audio transcript."
    @Published var isRunning = false
    let intelligenceEngine = IntelligenceEngine(
        apiToken: Env.crustdataToken
    )

    private let captureController = LiveMeetingCapture()
    private weak var window: NSWindow?
    private var levelDecayTask: Task<Void, Never>?
    private var screenObserver: NSObjectProtocol?
    private var requiresScreenCaptureRegrant = false
    private var intelCancellable: Any?
    private var hasPositioned = false

    init() {
        bindCaptureCallbacks()
        intelCancellable = intelligenceEngine.objectWillChange.sink { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.objectWillChange.send()
            }
        }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { _ in
            // Window stays where the user placed it
        }

        levelDecayTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000)
                decayLevels()
            }
        }
    }

    deinit {
        levelDecayTask?.cancel()

        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
    }

    func toggleCapture() {
        Task {
            if isRunning {
                await stopCapture()
            } else {
                await startCapture()
            }
        }
    }

    func stopCapture() async {
        await captureController.stop()
        isRunning = false
        statusMessage = "Live captions stopped"
        detailMessage = "Start again any time you want the overlay back."
    }

    func terminateApp() {
        Task {
            await stopCapture()
            NSApp.terminate(nil)
        }
    }

    func startCapture() async {
        guard !isRunning else { return }

        resetPanels()
        statusMessage = "Checking permissions"
        detailMessage = "Verifying microphone, speech recognition, and Screen & System Audio Recording state."

        do {
            let permissions = try await requestPermissions()
            statusMessage = "Starting live transcription"
            detailMessage = permissions.readyDescription

            try await captureController.start(locale: .autoupdatingCurrent)
            isRunning = true
            requiresScreenCaptureRegrant = false
            statusMessage = "Live captions running"
            detailMessage = "Microphone and system output are being transcribed in parallel."
        } catch {
            isRunning = false
            statusMessage = "Unable to start"
            detailMessage = Self.describe(error)
        }
    }

    func configure(window: NSWindow) {
        let firstConfiguration = self.window !== window
        self.window = window

        guard firstConfiguration else {
            return
        }

        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .floating
        window.isMovableByWindowBackground = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenNone, .ignoresCycle]
        window.styleMask.insert(.titled)
        window.styleMask.insert(.fullSizeContentView)
        window.styleMask.insert(.closable)
        window.styleMask.insert(.miniaturizable)
        window.styleMask.insert(.resizable)

        if !hasPositioned {
            positionWindowAtBottom(window)
            hasPositioned = true
        }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    private func positionWindowAtBottom(_ window: NSWindow) {
        guard let screen = window.screen ?? NSScreen.main ?? NSScreen.screens.first else { return }

        let visibleFrame = screen.visibleFrame
        let width = min(max(visibleFrame.width * 0.68, 860), 1080)
        let height: CGFloat = min(680, visibleFrame.height - 80)
        let origin = CGPoint(
            x: visibleFrame.midX - (width / 2),
            y: visibleFrame.minY + 60
        )

        window.setFrame(CGRect(origin: origin, size: CGSize(width: width, height: height)), display: true, animate: false)
    }

    private func bindCaptureCallbacks() {
        captureController.onTranscript = { [weak self] update in
            self?.applyTranscript(update)
        }

        captureController.onLevel = { [weak self] source, level in
            self?.applyLevel(level, for: source)
        }

        captureController.onStatus = { [weak self] message in
            self?.detailMessage = message
        }

        captureController.onError = { [weak self] error in
            self?.statusMessage = "Capture error"
            self?.detailMessage = Self.describe(error)
            self?.isRunning = false
        }
    }

    func resetAll() {
        captionPanel.liveText = ""
        captionPanel.finalized.removeAll()
        captionPanel.level = 0.02
        intelligenceEngine.reset()
    }

    private func resetPanels() {
        captionPanel.liveText = ""
        captionPanel.finalized.removeAll()
        captionPanel.level = 0.02
        intelligenceEngine.reset()
    }

    func removeEntityChip(_ entry: CaptionEntry) {
        intelligenceEngine.removeEntity(named: entry.text)
    }

    func editEntityChip(_ entry: CaptionEntry, newText: String) {
        intelligenceEngine.editEntity(oldName: entry.text, newName: newText)
    }

    private func applyTranscript(_ update: TranscriptUpdate) {
        let cleaned = update.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }

        Self.logCaption(isFinal: update.isFinal, text: cleaned)

        if update.isFinal {
            captionPanel.liveText = ""
            intelligenceEngine.processFinalizedCaption(cleaned)
        } else {
            // Only show the tail of long partials so it doesn't overflow
            if cleaned.count > 150, let idx = cleaned.index(cleaned.endIndex, offsetBy: -150, limitedBy: cleaned.startIndex) {
                let trimmed = cleaned[idx...]
                let wordStart = trimmed.firstIndex(of: " ").map(trimmed.index(after:)) ?? trimmed.startIndex
                captionPanel.liveText = "…" + String(trimmed[wordStart...])
            } else {
                captionPanel.liveText = cleaned
            }
        }
    }

    private static let captionLogURL: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("Coyote-Captions.log")
    }()

    private static func logCaption(isFinal: Bool, text: String) {
        let ts = ISO8601DateFormatter().string(from: Date())
        let tag = isFinal ? "FINAL" : "PARTIAL"
        let line = "[\(ts)] [\(tag)] \(text)\n"
        if let data = line.data(using: .utf8) {
            if let handle = try? FileHandle(forWritingTo: captionLogURL) {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            } else {
                try? data.write(to: captionLogURL)
            }
        }
    }

    private func applyLevel(_ level: Double, for source: CaptionSource) {
        captionPanel.level = max(captionPanel.level, min(max(level, 0.02), 1.0))
    }

    private func decayLevels() {
        captionPanel.level = max(captionPanel.level * 0.82, 0.02)
    }

    private func requestPermissions() async throws -> PermissionSnapshot {
        let speechStatus = await Self.requestSpeechAuthorization()
        guard speechStatus == .authorized else {
            throw PermissionError.speechRecognition
        }

        let microphoneAllowed = await Self.requestMicrophoneAccess()
        guard microphoneAllowed else {
            throw PermissionError.microphone
        }

        return PermissionSnapshot(
            speechAuthorized: true,
            microphoneAuthorized: true,
            screenCaptureAuthorized: Self.screenCaptureAccessStatus()
        )
    }

    private static func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized, .denied, .restricted:
            return SFSpeechRecognizer.authorizationStatus()
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status)
                }
            }
        @unknown default:
            return .denied
        }
    }

    private static func requestMicrophoneAccess() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return true
        case .undetermined:
            return await AVAudioApplication.requestRecordPermission()
        case .denied:
            return false
        default:
            return false
        }
    }

    private static func screenCaptureAccessStatus() -> Bool {
        CGPreflightScreenCaptureAccess()
    }
}

private extension CaptionBarViewModel {
    static func describe(_ error: Error) -> String {
        let nsError = error as NSError
        return "\(error.localizedDescription) [\(nsError.domain) \(nsError.code)]"
    }

    static func requiresScreenCaptureRegrant(for error: Error) -> Bool {
        if let captureError = error as? CaptureError {
            switch captureError {
            case .screenRecordingPermissionOutOfSync, .missingScreenCaptureEntitlements:
                return true
            default:
                return false
            }
        }

        if let permissionError = error as? PermissionError {
            return permissionError == .screenRecording
        }

        let nsError = error as NSError
        return nsError.domain == SCStreamErrorDomain && nsError.code == -3801
    }
}

private struct PermissionSnapshot {
    let speechAuthorized: Bool
    let microphoneAuthorized: Bool
    let screenCaptureAuthorized: Bool

    var readyDescription: String {
        let speech = speechAuthorized ? "Speech Recognition: enabled" : "Speech Recognition: unavailable"
        let microphone = microphoneAuthorized ? "Microphone: enabled" : "Microphone: unavailable"
        let screen = screenCaptureAuthorized
            ? "Screen & System Audio Recording: enabled"
            : "Screen & System Audio Recording: not confirmed yet"

        return [speech, microphone, screen].joined(separator: " • ")
    }
}

enum PermissionError: LocalizedError, Equatable {
    case speechRecognition
    case microphone
    case screenRecording

    var errorDescription: String? {
        switch self {
        case .speechRecognition:
            return "Speech recognition access was denied. Enable it for the app in System Settings > Privacy & Security > Speech Recognition."
        case .microphone:
            return "Microphone access is currently denied for this signed build. Open System Settings > Privacy & Security > Microphone and enable `Coyote`, or press Start again after a fresh microphone prompt appears."
        case .screenRecording:
            return "Screen & System Audio Recording access is required for macOS output capture. Enable it in System Settings > Privacy & Security > Screen & System Audio Recording, then relaunch the app."
        }
    }
}
