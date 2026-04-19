import AppKit
import CoreGraphics
import Foundation
@preconcurrency import ScreenCaptureKit

final class LiveMeetingCapture: NSObject {
    var onTranscript: @MainActor (TranscriptUpdate) -> Void = { _ in }
    var onLevel: @MainActor (CaptionSource, Double) -> Void = { _, _ in }
    var onStatus: @MainActor (String) -> Void = { _ in }
    var onError: @MainActor (Error) -> Void = { _ in }

    private let sampleQueue = DispatchQueue(label: "Coyote.capture.samples")
    private var stream: SCStream?
    private var pipeline: AudioTranscriptionPipeline?
    private var isRunning = false

    func start(locale: Locale) async throws {
        guard !isRunning else { return }

        let pipeline = AudioTranscriptionPipeline(
            source: .unified,
            locale: locale,
            onTranscript: { [weak self] in self?.onTranscript($0) },
            onLevel: { [weak self] in self?.onLevel($0, $1) },
            onStatus: { [weak self] in self?.onStatus($0) },
            onError: { [weak self] in self?.onError($0) }
        )

        do {
            let shareableContent: SCShareableContent
            do {
                shareableContent = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            } catch {
                let nsErr = error as NSError
                if nsErr.domain == SCStreamErrorDomain, nsErr.code == -3801 {
                    // Trigger the system permission prompt and retry once
                    CGRequestScreenCaptureAccess()
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                    shareableContent = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                } else {
                    throw error
                }
            }
            guard let display = preferredDisplay(from: shareableContent) else {
                throw CaptureError.noAvailableDisplay
            }

            let ownBundleIdentifier = Bundle.main.bundleIdentifier
            let excludedApplications = shareableContent.applications.filter { app in
                app.bundleIdentifier == ownBundleIdentifier
            }

            let filter = SCContentFilter(
                display: display,
                excludingApplications: excludedApplications,
                exceptingWindows: []
            )

            let configuration = SCStreamConfiguration()
            configuration.width = 2
            configuration.height = 2
            configuration.queueDepth = 3
            configuration.capturesAudio = true
            configuration.captureMicrophone = true
            configuration.excludesCurrentProcessAudio = true
            configuration.sampleRate = 48_000
            configuration.channelCount = 1

            let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleQueue)
            try stream.addStreamOutput(self, type: .microphone, sampleHandlerQueue: sampleQueue)

            self.stream = stream
            self.pipeline = pipeline

            try await stream.startCapture()
            isRunning = true

            await MainActor.run {
                onStatus("Listening to mic + system audio.")
            }
        } catch {
            self.stream = nil
            self.pipeline = nil
            throw mapCaptureError(error)
        }
    }

    func stop() async {
        guard isRunning else { return }

        if let stream {
            try? await stream.stopCapture()
        }

        pipeline?.stop()

        self.stream = nil
        self.pipeline = nil
        self.isRunning = false
    }

    private func preferredDisplay(from shareableContent: SCShareableContent) -> SCDisplay? {
        let activeDisplayID = NSScreen.main?.displayID ?? CGMainDisplayID()
        return shareableContent.displays.first(where: { $0.displayID == activeDisplayID }) ?? shareableContent.displays.first
    }

    private func mapCaptureError(_ error: Error) -> Error {
        let nsError = error as NSError

        guard nsError.domain == SCStreamErrorDomain else {
            return error
        }

        switch nsError.code {
        case -3801:
            if CGPreflightScreenCaptureAccess() {
                return CaptureError.screenRecordingPermissionOutOfSync
            }
            return PermissionError.screenRecording
        case -3803:
            return CaptureError.missingScreenCaptureEntitlements
        case -3818:
            return CaptureError.failedToStartSystemAudio
        case -3820:
            return CaptureError.failedToStartMicrophone
        default:
            return error
        }
    }
}

extension LiveMeetingCapture: SCStreamOutput, SCStreamDelegate {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard CMSampleBufferDataIsReady(sampleBuffer) else { return }

        switch type {
        case .microphone:
            pipeline?.append(sampleBuffer: sampleBuffer)
        case .audio:
            pipeline?.appendLevelOnly(sampleBuffer: sampleBuffer)
        case .screen:
            break
        @unknown default:
            break
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor in
            onError(error)
        }
    }
}

enum CaptureError: LocalizedError {
    case noAvailableDisplay
    case screenRecordingPermissionOutOfSync
    case missingScreenCaptureEntitlements
    case failedToStartSystemAudio
    case failedToStartMicrophone

    var errorDescription: String? {
        switch self {
        case .noAvailableDisplay:
            return "No display was available for ScreenCaptureKit. Connect a display and try again."
        case .screenRecordingPermissionOutOfSync:
            return "Screen & System Audio Recording is enabled, but ScreenCaptureKit still returned `userDeclined` for this app identity. This is usually a stale macOS TCC grant for an older build. Remove `Coyote` from System Settings > Privacy & Security > Screen & System Audio Recording, relaunch once, and enable it again."
        case .missingScreenCaptureEntitlements:
            return "ScreenCaptureKit reported missing entitlements for this build. The app needs to be launched from a properly signed bundle."
        case .failedToStartSystemAudio:
            return "ScreenCaptureKit started, but macOS output audio failed to start. Check that system audio capture is allowed and no other policy is blocking it."
        case .failedToStartMicrophone:
            return "ScreenCaptureKit started, but microphone capture failed to start. Check the app's microphone access in System Settings."
        }
    }
}
