# SKILL.md — Complete Code Specification

This document contains the **exact source code** for every file in the Coyote project. A coding agent must reproduce each file verbatim. The smaller files are embedded inline below. The four largest files (CrustdataClient, IntelligenceEngine, CaptionBarViewModel, ContentView) are too large to embed in Markdown — copy them verbatim from `Coyote/` in this repository.

> **Security**: All API keys must be supplied by the developer at build time via a `.env` file. No real keys appear in this document. All file paths are project-relative — adjust the hardcoded fallback path in `EnvLoader.swift` to match your own environment.

---

## Table of Contents

1. [Project Structure](#project-structure)
2. [.gitignore](#gitignore)
3. [.env (template)](#env-template)
4. [README.md](#readmemd)
5. [Info.plist](#infoplist)
6. [Coyote.entitlements](#coyoteentitlements)
7. [Asset Catalog](#asset-catalog)
8. [CoyoteApp.swift](#coyoteappswift)
9. [EnvLoader.swift](#envloaderswift)
10. [AudioUtilities.swift](#audioutilitiesswift)
11. [AudioTranscriptionPipeline.swift](#audiotranscriptionpipelineswift)
12. [LiveMeetingCapture.swift](#livemeetingcaptureswift)
13. [EntityExtractor.swift](#entityextractorswift)
14. [CrustdataClient.swift](#crustdataclientswift) — copy from repo
15. [IntelligenceEngine.swift](#intelligenceengineswift) — copy from repo
16. [CaptionBarViewModel.swift](#captionbarviewmodelswift) — copy from repo
17. [ContentView.swift](#contentviewswift) — copy from repo
18. [Xcode Project Settings](#xcode-project-settings)

---

## Project Structure

```
coyote/
├── .gitignore
├── .env                          # NOT committed — gitignored
├── README.md
├── Coyote/
│   ├── Assets.xcassets/          # AppIcon + slack/discord/teams/salesforce/hubspot SVGs
│   ├── Info.plist
│   ├── Coyote.entitlements
│   ├── CoyoteApp.swift           (29 lines)
│   ├── EnvLoader.swift           (52 lines)
│   ├── AudioUtilities.swift      (118 lines)
│   ├── AudioTranscriptionPipeline.swift (478 lines)
│   ├── LiveMeetingCapture.swift  (178 lines)
│   ├── EntityExtractor.swift     (212 lines)
│   ├── CrustdataClient.swift     (1040 lines)
│   ├── IntelligenceEngine.swift  (684 lines)
│   ├── CaptionBarViewModel.swift (368 lines)
│   └── ContentView.swift         (688 lines)
└── Coyote.xcodeproj/
```

## Xcode Project Settings

- **Product Name**: Coyote
- **Bundle Identifier**: `com.coyote.app`
- **Deployment Target**: macOS 14.0
- **Swift Version**: 5.0
- **Marketing Version**: 1.0

---

## .gitignore

```gitignore
.DS_Store
build/
DerivedData/
*.xcuserstate
xcuserdata/
*.log
.env
```

## .env (template)

> This file is gitignored. Create it at the project root with your own keys.

```
OPENAI_API_KEY=<YOUR_OPENAI_KEY>
CLAUDE_API_KEY=<YOUR_CLAUDE_KEY>
CRUSTDATA_API_TOKEN=<YOUR_CRUSTDATA_TOKEN>
```

## README.md

```markdown
# Coyote — Real-Time In-Meeting Intelligence

> **YC Spring 2026 RFS**: AI-Native Agencies · AI-Native Hedge Funds

A native macOS overlay that delivers live business intelligence during sales calls and investor meetings — powered by Crustdata's Person and Company APIs.

## The Problem

Sales reps and investors sit through calls where dozens of names fly by — prospects, founders, portfolio companies, competitors. There's no way to research them without breaking the flow of conversation. You miss the signal that closes a deal or flags a red flag in a pitch, and spend hours after the meeting catching up on context you should have had live.

## The Solution

**Coyote** is an always-on-top macOS overlay that transcribes your meeting audio in real time, extracts every person and company mentioned, and enriches them on the fly with Crustdata's Person Search, Company Enrich, and Web Search APIs. By the time a founder finishes their pitch or a prospect names a competitor, you already have their funding history, headcount trends, LinkedIn, and latest news on screen.
```

## Info.plist

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>$(DEVELOPMENT_LANGUAGE)</string>
	<key>CFBundleDisplayName</key>
	<string>Coyote</string>
	<key>CFBundleExecutable</key>
	<string>$(EXECUTABLE_NAME)</string>
	<key>CFBundleIdentifier</key>
	<string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>$(PRODUCT_NAME)</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>$(MARKETING_VERSION)</string>
	<key>CFBundleVersion</key>
	<string>$(CURRENT_PROJECT_VERSION)</string>
	<key>LSApplicationCategoryType</key>
	<string>public.app-category.productivity</string>
	<key>LSMinimumSystemVersion</key>
	<string>$(MACOSX_DEPLOYMENT_TARGET)</string>
	<key>LSUIElement</key>
	<false/>
	<key>NSAudioCaptureUsageDescription</key>
	<string>Coyote needs access to macOS output audio so it can caption what other people say in your meetings.</string>
	<key>NSMicrophoneUsageDescription</key>
	<string>Coyote needs microphone access to transcribe what you say in real time.</string>
	<key>NSSpeechRecognitionUsageDescription</key>
	<string>Coyote uses Apple Speech to turn live meeting audio into captions.</string>
</dict>
</plist>
```

## Coyote.entitlements

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.device.audio-input</key>
	<true/>
</dict>
</plist>
```

## Asset Catalog

- `Assets.xcassets/Contents.json` — standard `{"info":{"author":"xcode","version":1}}`.
- `AppIcon.appiconset/` — standard macOS icon set (16×16 through 512×512, @1x and @2x).
- Integration icons: `slack.imageset/`, `discord.imageset/`, `teams.imageset/`, `salesforce.imageset/`, `hubspot.imageset/` — each contains an SVG logo + `Contents.json` with `"template-rendering-intent":"template"` and `"preserves-vector-representation":true`. Source SVGs from official brand asset pages.

---

## CoyoteApp.swift

```swift
import AppKit
import SwiftUI

@main
struct CoyoteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var viewModel = CaptionBarViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 860, height: 500)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
    }
}
```

## EnvLoader.swift

> **Note**: The third candidate path is a hardcoded fallback. Update it to match your own project location.

```swift
import Foundation

enum Env {
    private static let values: [String: String] = {
        let candidates = [
            Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent(".env"),
            Bundle.main.bundleURL
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent(".env"),
            URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("<YOUR_PROJECT_PATH>/coyote/.env")
        ]
        for url in candidates {
            if let contents = try? String(contentsOf: url, encoding: .utf8) {
                return parse(contents)
            }
        }
        return [:]
    }()

    private static func parse(_ contents: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in contents.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            let parts = trimmed.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = String(parts[0]).trimmingCharacters(in: .whitespaces)
            let value = String(parts[1]).trimmingCharacters(in: .whitespaces)
            result[key] = value
        }
        return result
    }

    static var openAIKey: String { values["OPENAI_API_KEY"] ?? "" }
    static var claudeAPIKey: String { values["CLAUDE_API_KEY"] ?? "" }
    static var crustdataToken: String { values["CRUSTDATA_API_TOKEN"] ?? "" }
}
```

## AudioUtilities.swift

```swift
import AppKit
import AVFoundation
import CoreMedia

enum AudioBufferConversionError: LocalizedError {
    case missingFormatDescription
    case missingStreamDescription
    case unsupportedAudioFormat
    case pcmBufferAllocation
    case copyFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .missingFormatDescription:
            return "The audio sample buffer was missing its format description."
        case .missingStreamDescription:
            return "The audio sample buffer was missing its stream description."
        case .unsupportedAudioFormat:
            return "The captured audio format couldn't be represented as AVAudioFormat."
        case .pcmBufferAllocation:
            return "Unable to allocate an AVAudioPCMBuffer for transcription."
        case .copyFailed(let status):
            return "Copying PCM audio from the capture buffer failed with status \(status)."
        }
    }
}

extension CMSampleBuffer {
    func makePCMBuffer() throws -> AVAudioPCMBuffer {
        guard let formatDescription = CMSampleBufferGetFormatDescription(self) else {
            throw AudioBufferConversionError.missingFormatDescription
        }
        guard let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) else {
            throw AudioBufferConversionError.missingStreamDescription
        }
        guard let audioFormat = AVAudioFormat(streamDescription: streamDescription) else {
            throw AudioBufferConversionError.unsupportedAudioFormat
        }
        let frameCount = AVAudioFrameCount(CMSampleBufferGetNumSamples(self))
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: frameCount) else {
            throw AudioBufferConversionError.pcmBufferAllocation
        }
        pcmBuffer.frameLength = frameCount
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            self, at: 0, frameCount: Int32(frameCount), into: pcmBuffer.mutableAudioBufferList
        )
        guard status == noErr else {
            throw AudioBufferConversionError.copyFailed(status)
        }
        return pcmBuffer
    }
}

extension AVAudioPCMBuffer {
    func normalizedPowerLevel() -> Double {
        let frameCount = Int(frameLength)
        guard frameCount > 0 else { return 0.02 }
        let channelCount = Int(format.channelCount)
        var accumulator = 0.0
        var sampleCounter = 0
        switch format.commonFormat {
        case .pcmFormatFloat32:
            guard let channelData = floatChannelData else { return 0.05 }
            for channel in 0..<channelCount {
                let samples = UnsafeBufferPointer(start: channelData[channel], count: frameCount)
                for sample in samples { accumulator += Double(abs(sample)) }
                sampleCounter += samples.count
            }
        case .pcmFormatInt16:
            guard let channelData = int16ChannelData else { return 0.05 }
            for channel in 0..<channelCount {
                let samples = UnsafeBufferPointer(start: channelData[channel], count: frameCount)
                for sample in samples {
                    let magnitude = min(Double(Int64(sample).magnitude) / Double(Int16.max), 1.0)
                    accumulator += magnitude
                }
                sampleCounter += samples.count
            }
        case .pcmFormatInt32:
            guard let channelData = int32ChannelData else { return 0.05 }
            for channel in 0..<channelCount {
                let samples = UnsafeBufferPointer(start: channelData[channel], count: frameCount)
                for sample in samples {
                    let magnitude = min(Double(Int64(sample).magnitude) / Double(Int32.max), 1.0)
                    accumulator += magnitude
                }
                sampleCounter += samples.count
            }
        default:
            return 0.05
        }
        guard sampleCounter > 0 else { return 0.02 }
        let average = accumulator / Double(sampleCounter)
        return min(max(average * 2.8, 0.02), 1.0)
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
```

## AudioTranscriptionPipeline.swift

> Full code for this 478-line file. Handles audio chunking, WAV encoding, OpenAI transcription, and hallucination filtering.

```swift
@preconcurrency import AVFoundation
import CoreMedia
import Foundation

private let _diagPath = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("CoyoteDiag.log")
private func diag(_ msg: String) {
    let line = "\(Date()) \(msg)\n"
    guard let data = line.data(using: .utf8) else { return }
    if let fh = try? FileHandle(forWritingTo: _diagPath) {
        fh.seekToEndOfFile(); fh.write(data); fh.closeFile()
    } else {
        try? data.write(to: _diagPath)
    }
}

enum CaptionSource: String, Sendable {
    case microphone
    case systemAudio
    case unified

    var displayName: String {
        switch self {
        case .microphone: return "Microphone"
        case .systemAudio: return "System Audio"
        case .unified: return "Live Audio"
        }
    }
}

struct TranscriptUpdate: Sendable {
    let source: CaptionSource
    let text: String
    let isFinal: Bool
}

final class AudioTranscriptionPipeline: @unchecked Sendable {
    private enum State { case idle, preparing, ready, failed }

    private let source: CaptionSource
    private let locale: Locale
    private let queue: DispatchQueue
    private let onTranscript: @MainActor (TranscriptUpdate) -> Void
    private let onLevel: @MainActor (CaptionSource, Double) -> Void
    private let onStatus: @MainActor (String) -> Void
    private let onError: @MainActor (Error) -> Void

    private var state: State = .idle
    private var pendingSamples: [CMSampleBuffer] = []
    private var targetFormat: AVAudioFormat?
    private var sourceFormat: AVAudioFormat?
    private var converter: AVAudioConverter?

    private static let openAIKey = Env.openAIKey
    private static let transcriptionModel = "gpt-4o-transcribe"
    private let chunkDuration: TimeInterval = 8.0
    private let overlapDuration: TimeInterval = 1.0
    private var pcmAccumulator: [Float] = []
    private var overlapBuffer: [Float] = []
    private var accumulatedFrames: UInt32 = 0
    private var sampleRate: Double = 16000
    private var isTranscribing = false
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        return URLSession(configuration: config)
    }()
    private var silenceTimer: DispatchWorkItem?
    private let silenceTimeout: TimeInterval = 2.0
    private var lastPartialText = ""

    init(
        source: CaptionSource, locale: Locale,
        onTranscript: @escaping @MainActor (TranscriptUpdate) -> Void,
        onLevel: @escaping @MainActor (CaptionSource, Double) -> Void,
        onStatus: @escaping @MainActor (String) -> Void,
        onError: @escaping @MainActor (Error) -> Void
    ) {
        self.source = source; self.locale = locale
        self.onTranscript = onTranscript; self.onLevel = onLevel
        self.onStatus = onStatus; self.onError = onError
        self.queue = DispatchQueue(label: "Coyote.pipeline.\(source.rawValue)")
    }

    func append(sampleBuffer: CMSampleBuffer) {
        queue.async {
            guard CMSampleBufferDataIsReady(sampleBuffer) else { return }
            switch self.state {
            case .idle:
                self.state = .preparing
                self.pendingSamples = [sampleBuffer]
                self.configure(using: sampleBuffer)
            case .preparing:
                self.pendingSamples.append(sampleBuffer)
            case .ready:
                self.processReady(sampleBuffer)
            case .failed:
                break
            }
        }
    }

    func appendLevelOnly(sampleBuffer: CMSampleBuffer) {
        guard CMSampleBufferDataIsReady(sampleBuffer) else { return }
        do {
            let pcm = try sampleBuffer.makePCMBuffer()
            let level = pcm.normalizedPowerLevel()
            let src = self.source
            Task { @MainActor in self.onLevel(src, level) }
        } catch { }
    }

    func stop() {
        queue.async {
            self.silenceTimer?.cancel(); self.silenceTimer = nil
            if !self.pcmAccumulator.isEmpty { self.flushChunk() }
            self.pendingSamples.removeAll(); self.pcmAccumulator.removeAll()
            self.overlapBuffer.removeAll(); self.accumulatedFrames = 0
            self.targetFormat = nil; self.sourceFormat = nil; self.converter = nil
            self.lastPartialText = ""; self.state = .idle
        }
    }

    private func configure(using sampleBuffer: CMSampleBuffer) {
        do {
            let naturalBuffer = try sampleBuffer.makePCMBuffer()
            let targetFmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
            self.targetFormat = targetFmt; self.sampleRate = 16000
            self.sourceFormat = naturalBuffer.format
            if !Self.formatsMatch(naturalBuffer.format, targetFmt) {
                self.converter = AVAudioConverter(from: naturalBuffer.format, to: targetFmt)
            }
            diag("[\(self.source.rawValue)] configure: \(Self.transcriptionModel) mode, naturalFmt=\(naturalBuffer.format) targetFmt=\(targetFmt) frames=\(naturalBuffer.frameLength)")
            self.state = .ready
            let queued = self.pendingSamples; self.pendingSamples.removeAll()
            queued.forEach(self.processReady)
            let src = self.source
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.onStatus("\(src.displayName): live transcription ready.")
            }
        } catch {
            state = .failed; pendingSamples.removeAll()
            Task { @MainActor in onError(error) }
        }
    }

    private func processReady(_ sampleBuffer: CMSampleBuffer) {
        do {
            let naturalBuffer = try sampleBuffer.makePCMBuffer()
            guard let targetFormat else { return }
            let preparedBuffer = try convertIfNeeded(buffer: naturalBuffer, to: targetFormat)
            let level = preparedBuffer.normalizedPowerLevel()
            if let channelData = preparedBuffer.floatChannelData {
                let frameCount = Int(preparedBuffer.frameLength)
                let ptr = channelData[0]
                for i in 0..<frameCount { pcmAccumulator.append(ptr[i]) }
                accumulatedFrames += preparedBuffer.frameLength
            }
            silenceTimer?.cancel()
            let timer = DispatchWorkItem { [weak self] in
                guard let self else { return }
                if !self.pcmAccumulator.isEmpty {
                    diag("[\(self.source.rawValue)] silence timer fired, flushing \(self.accumulatedFrames) frames")
                    self.flushChunk()
                }
            }
            silenceTimer = timer
            queue.asyncAfter(deadline: .now() + silenceTimeout, execute: timer)
            let accumulatedDuration = Double(accumulatedFrames) / sampleRate
            if accumulatedDuration >= chunkDuration { flushChunk() }
            if accumulatedDuration > 0.5 && !isTranscribing {
                let src = self.source
                let partialText = lastPartialText.isEmpty ? "Listening..." : lastPartialText
                Task { @MainActor in
                    self.onTranscript(.init(source: src, text: partialText, isFinal: false))
                }
            }
            Task { @MainActor in self.onLevel(self.source, level) }
        } catch {
            Task { @MainActor in self.onError(error) }
        }
    }

    private func flushChunk() {
        guard !pcmAccumulator.isEmpty, !isTranscribing else { return }
        let samples = overlapBuffer + pcmAccumulator
        let overlapFrames = Int(overlapDuration * sampleRate)
        if pcmAccumulator.count > overlapFrames {
            overlapBuffer = Array(pcmAccumulator.suffix(overlapFrames))
        } else { overlapBuffer = pcmAccumulator }
        pcmAccumulator.removeAll(); accumulatedFrames = 0; isTranscribing = true
        let sr = sampleRate; let src = self.source
        diag("[\(src.rawValue)] flushing \(samples.count) samples (\(String(format: "%.1f", Double(samples.count) / sr))s) to \(Self.transcriptionModel)")
        Task {
            defer { self.queue.async { self.isTranscribing = false } }
            let wavData = Self.encodeWAV(samples: samples, sampleRate: Int(sr))
            guard let text = await self.transcribeAudio(wavData: wavData) else {
                diag("[\(src.rawValue)] \(Self.transcriptionModel) returned nil"); return
            }
            let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else {
                diag("[\(src.rawValue)] \(Self.transcriptionModel) returned empty text"); return
            }
            let lowerCleaned = cleaned.lowercased()
            let hallucinations = ["thank you", "thanks for watching", "please subscribe", "you", "bye"]
            if hallucinations.contains(where: { lowerCleaned == $0 || lowerCleaned.hasPrefix($0 + ".") || lowerCleaned.hasPrefix($0 + "!") }) {
                diag("[\(src.rawValue)] hallucination filtered: \"\(cleaned)\""); return
            }
            if lowerCleaned.hasPrefix("this is a business meeting") || lowerCleaned.hasPrefix("accurately transcribe") {
                diag("[\(src.rawValue)] prompt echo filtered: \"\(cleaned.prefix(80))\""); return
            }
            diag("[\(src.rawValue)] \(Self.transcriptionModel) result: \"\(cleaned.prefix(120))\"")
            self.queue.async { self.lastPartialText = cleaned }
            Task { @MainActor in
                self.onTranscript(.init(source: src, text: cleaned, isFinal: true))
            }
        }
    }

    private func transcribeAudio(wavData: Data) async -> String? {
        guard let url = URL(string: "https://api.openai.com/v1/audio/transcriptions") else { return nil }
        let boundary = UUID().uuidString
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(Self.openAIKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(Self.transcriptionModel)\r\n".data(using: .utf8)!)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"language\"\r\n\r\n".data(using: .utf8)!)
        body.append("en\r\n".data(using: .utf8)!)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"response_format\"\r\n\r\n".data(using: .utf8)!)
        body.append("text\r\n".data(using: .utf8)!)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(wavData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body
        do {
            let (data, response) = try await session.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            if !(200...299).contains(statusCode) {
                let respStr = String(data: data, encoding: .utf8) ?? "?"
                diag("[\(source.rawValue)] \(Self.transcriptionModel) HTTP \(statusCode): \(respStr.prefix(300))")
                return nil
            }
            return String(data: data, encoding: .utf8)
        } catch {
            diag("[\(source.rawValue)] \(Self.transcriptionModel) error: \(error.localizedDescription)")
            return nil
        }
    }

    private static func encodeWAV(samples: [Float], sampleRate: Int) -> Data {
        let numChannels: Int = 1; let bitsPerSample: Int = 16
        let byteRate = sampleRate * numChannels * bitsPerSample / 8
        let blockAlign = numChannels * bitsPerSample / 8
        let dataSize = samples.count * 2
        var data = Data()
        data.append(contentsOf: "RIFF".utf8)
        var chunkSize = UInt32(36 + dataSize).littleEndian
        data.append(Data(bytes: &chunkSize, count: 4))
        data.append(contentsOf: "WAVE".utf8)
        data.append(contentsOf: "fmt ".utf8)
        var subchunk1Size = UInt32(16).littleEndian
        data.append(Data(bytes: &subchunk1Size, count: 4))
        var audioFormat = UInt16(1).littleEndian
        data.append(Data(bytes: &audioFormat, count: 2))
        var channels = UInt16(numChannels).littleEndian
        data.append(Data(bytes: &channels, count: 2))
        var sr = UInt32(sampleRate).littleEndian
        data.append(Data(bytes: &sr, count: 4))
        var br = UInt32(byteRate).littleEndian
        data.append(Data(bytes: &br, count: 4))
        var ba = UInt16(blockAlign).littleEndian
        data.append(Data(bytes: &ba, count: 2))
        var bps = UInt16(bitsPerSample).littleEndian
        data.append(Data(bytes: &bps, count: 2))
        data.append(contentsOf: "data".utf8)
        var ds = UInt32(dataSize).littleEndian
        data.append(Data(bytes: &ds, count: 4))
        for sample in samples {
            let clamped = max(-1.0, min(1.0, sample))
            var int16 = Int16(clamped * 32767.0).littleEndian
            data.append(Data(bytes: &int16, count: 2))
        }
        return data
    }

    private func convertIfNeeded(buffer: AVAudioPCMBuffer, to outputFormat: AVAudioFormat) throws -> AVAudioPCMBuffer {
        guard !Self.formatsMatch(buffer.format, outputFormat) else { return buffer }
        if sourceFormat.map({ !Self.formatsMatch($0, buffer.format) }) ?? true {
            sourceFormat = buffer.format
            converter = AVAudioConverter(from: buffer.format, to: outputFormat)
        }
        guard let converter else { throw PipelineError.converterUnavailable }
        let ratio = outputFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(max(1, ceil(Double(buffer.frameLength) * ratio)))
        guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
            throw PipelineError.outputBufferCreation
        }
        var suppliedInput = false; var conversionError: NSError?
        let status = converter.convert(to: convertedBuffer, error: &conversionError) { _, outStatus in
            if suppliedInput { outStatus.pointee = .noDataNow; return nil }
            suppliedInput = true; outStatus.pointee = .haveData; return buffer
        }
        if let conversionError { throw conversionError }
        guard convertedBuffer.frameLength > 0 else { throw PipelineError.emptyConversion(status.rawValue) }
        return convertedBuffer
    }

    private static func formatsMatch(_ lhs: AVAudioFormat, _ rhs: AVAudioFormat) -> Bool {
        lhs.commonFormat == rhs.commonFormat && lhs.sampleRate == rhs.sampleRate &&
        lhs.channelCount == rhs.channelCount && lhs.isInterleaved == rhs.isInterleaved
    }
}

enum PipelineError: LocalizedError {
    case unsupportedLocale(String), converterUnavailable, outputBufferCreation, emptyConversion(Int)
    var errorDescription: String? {
        switch self {
        case .unsupportedLocale(let identifier):
            return "Speech doesn't support the locale \(identifier) on this Mac."
        case .converterUnavailable:
            return "Unable to create the audio converter required for live transcription."
        case .outputBufferCreation:
            return "Unable to allocate the converted audio buffer."
        case .emptyConversion:
            return "The speech pipeline received an empty converted buffer."
        }
    }
}
```

## LiveMeetingCapture.swift

> Full code for this 178-line file. Wraps ScreenCaptureKit for dual audio capture.

```swift
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
            source: .unified, locale: locale,
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
                    CGRequestScreenCaptureAccess()
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                    shareableContent = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                } else { throw error }
            }
            guard let display = preferredDisplay(from: shareableContent) else {
                throw CaptureError.noAvailableDisplay
            }
            let ownBundleIdentifier = Bundle.main.bundleIdentifier
            let excludedApplications = shareableContent.applications.filter { app in
                app.bundleIdentifier == ownBundleIdentifier
            }
            let filter = SCContentFilter(display: display, excludingApplications: excludedApplications, exceptingWindows: [])
            let configuration = SCStreamConfiguration()
            configuration.width = 2; configuration.height = 2; configuration.queueDepth = 3
            configuration.capturesAudio = true; configuration.captureMicrophone = true
            configuration.excludesCurrentProcessAudio = true
            configuration.sampleRate = 48_000; configuration.channelCount = 1
            let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleQueue)
            try stream.addStreamOutput(self, type: .microphone, sampleHandlerQueue: sampleQueue)
            self.stream = stream; self.pipeline = pipeline
            try await stream.startCapture()
            isRunning = true
            await MainActor.run { onStatus("Listening to mic + system audio.") }
        } catch {
            self.stream = nil; self.pipeline = nil
            throw mapCaptureError(error)
        }
    }

    func stop() async {
        guard isRunning else { return }
        if let stream { try? await stream.stopCapture() }
        pipeline?.stop()
        self.stream = nil; self.pipeline = nil; self.isRunning = false
    }

    private func preferredDisplay(from shareableContent: SCShareableContent) -> SCDisplay? {
        let activeDisplayID = NSScreen.main?.displayID ?? CGMainDisplayID()
        return shareableContent.displays.first(where: { $0.displayID == activeDisplayID }) ?? shareableContent.displays.first
    }

    private func mapCaptureError(_ error: Error) -> Error {
        let nsError = error as NSError
        guard nsError.domain == SCStreamErrorDomain else { return error }
        switch nsError.code {
        case -3801:
            if CGPreflightScreenCaptureAccess() { return CaptureError.screenRecordingPermissionOutOfSync }
            return PermissionError.screenRecording
        case -3803: return CaptureError.missingScreenCaptureEntitlements
        case -3818: return CaptureError.failedToStartSystemAudio
        case -3820: return CaptureError.failedToStartMicrophone
        default: return error
        }
    }
}

extension LiveMeetingCapture: SCStreamOutput, SCStreamDelegate {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard CMSampleBufferDataIsReady(sampleBuffer) else { return }
        switch type {
        case .microphone: pipeline?.append(sampleBuffer: sampleBuffer)
        case .audio: pipeline?.appendLevelOnly(sampleBuffer: sampleBuffer)
        case .screen: break
        @unknown default: break
        }
    }
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor in onError(error) }
    }
}

enum CaptureError: LocalizedError {
    case noAvailableDisplay, screenRecordingPermissionOutOfSync
    case missingScreenCaptureEntitlements, failedToStartSystemAudio, failedToStartMicrophone
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
```

## EntityExtractor.swift

> Full code for this 212-line file. Uses Claude API for entity extraction from transcribed text.

```swift
import Foundation

private func entityLog(_ msg: String) {
    let line = "\(Date()) [Entity] \(msg)\n"
    guard let data = line.data(using: .utf8) else { return }
    let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Coyote-Entity.log")
    if let fh = try? FileHandle(forWritingTo: url) {
        fh.seekToEndOfFile(); fh.write(data); fh.closeFile()
    } else {
        try? data.write(to: url)
    }
}

enum EntityKind: String, Sendable, Hashable, Codable {
    case person
    case company
}

struct ExtractedEntity: Sendable, Hashable {
    let kind: EntityKind
    let name: String
    let associatedCompany: String?
    let timestamp: Date
}

final class EntityExtractor: @unchecked Sendable {
    private let queue = DispatchQueue(label: "Coyote.entityExtractor")
    private var recentEntities: [String: Date] = [:]
    private let cooldown: TimeInterval = 15
    private let claudeAPIKey: String
    private let session: URLSession
    private var recentCaptions: [String] = []
    private let maxContextCaptions = 5

    init(claudeAPIKey: String = Env.claudeAPIKey) {
        self.claudeAPIKey = claudeAPIKey
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        self.session = URLSession(configuration: config)
    }

    func extract(from text: String, completion: @escaping @Sendable ([ExtractedEntity]) -> Void) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3 else { completion([]); return }
        let context: String = queue.sync {
            let ctx = recentCaptions.joined(separator: " | ")
            recentCaptions.append(trimmed)
            if recentCaptions.count > maxContextCaptions { recentCaptions.removeFirst() }
            return ctx
        }
        Task {
            let entities = await self.callClaude(text: trimmed, context: context)
            completion(entities)
        }
    }

    private func callClaude(text: String, context: String) async -> [ExtractedEntity] {
        entityLog("Claude extraction for: \(text.prefix(120))")
        let now = Date()
        let systemPrompt = """
        You are an entity extractor for a live meeting intelligence tool. The input is from speech-to-text and MAY contain transcription errors. You will receive RECENT CONTEXT (previous captions) and a NEW SEGMENT to extract from.

        Extract BOTH persons and companies/organizations:

        PERSON:
        - Any person mentioned by name. Always use their FULL name including all parts (first, middle, last). Never drop any part of a multi-part name.
        - When a person is associated with a company (via title, role, or context), include the "company" field.
        - Use BOTH the new segment AND recent context to determine associations. If a company was mentioned in context and a person is discussed in the new segment in relation to it, associate them.

        COMPANY:
        - Any company, startup, brand, product, organization, university, or business entity.
        - When you recognize a product name, also extract its parent company as a separate entity.
        - When a well-known person is mentioned, also extract their known associated companies.

        COMPOUND NAMES:
        - If two or more words together form a single product or company name, keep them as ONE entity. Do not split them.
        - When in doubt, keep words together rather than splitting them.

        SPEECH-TO-TEXT CORRECTION:
        - The input frequently garbles proper nouns. Use your world knowledge to fix them.
        - For person names: if a title/role and company are mentioned, use your knowledge of that company's actual leadership to correct garbled names to the real person who holds that role.
        - For company names: fix phonetic errors, word-splits, and misspellings to the correct official spelling.
        - Always output the correct official real-world spelling.

        Rules:
        - Do NOT extract generic words, verbs, adjectives, conversation filler, or URLs/domains.
        - Ignore speech-to-text artifacts and filler phrases.
        - Be aggressive — if something MIGHT be an entity worth looking up, include it.
        - Return ONLY valid JSON. No markdown fences, no explanation.
        - If nothing found: {"entities":[]}

        Format: {"entities":[{"kind":"person","name":"Full Name","company":"Company Name or null"},{"kind":"company","name":"Company Name"}]}
        For persons, "company" is OPTIONAL — include it ONLY when the conversation clearly ties the person to a company.
        """

        let body: [String: Any] = [
            "model": "claude-sonnet-4-20250514",
            "max_tokens": 256,
            "system": systemPrompt,
            "messages": [
                ["role": "user", "content": context.isEmpty ? "Extract entities from this meeting transcript segment:\n\"\(text)\"" : "Recent context: \(context)\n\nExtract entities from this NEW segment (use context for associations):\n\"\(text)\""]
            ]
        ]

        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else { return [] }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue(claudeAPIKey, forHTTPHeaderField: "x-api-key")

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await session.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            guard (200...299).contains(statusCode) else {
                let respStr = String(data: data, encoding: .utf8) ?? "?"
                entityLog("Claude HTTP \(statusCode): \(respStr.prefix(200))")
                return []
            }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let content = json["content"] as? [[String: Any]],
                  let firstBlock = content.first,
                  let textContent = firstBlock["text"] as? String else {
                entityLog("Claude response parse failed"); return []
            }
            entityLog("Claude raw: \(textContent.prefix(300))")
            var jsonText = textContent.trimmingCharacters(in: .whitespacesAndNewlines)
            if jsonText.hasPrefix("```") {
                if let firstNewline = jsonText.firstIndex(of: "\n") {
                    jsonText = String(jsonText[jsonText.index(after: firstNewline)...])
                }
                if jsonText.hasSuffix("```") {
                    jsonText = String(jsonText.dropLast(3)).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
            guard let jsonData = jsonText.data(using: .utf8),
                  let parsed = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                  let entityList = parsed["entities"] as? [[String: Any]] else {
                entityLog("Claude JSON parse failed from: \(jsonText.prefix(200))"); return []
            }
            var results: [ExtractedEntity] = []; var seen = Set<String>()
            for item in entityList {
                guard let kindStr = item["kind"] as? String,
                      let kind = EntityKind(rawValue: kindStr),
                      let name = item["name"] as? String, !name.isEmpty else { continue }
                let key = "\(kind.rawValue):\(name.lowercased())"
                guard !seen.contains(key) else { continue }
                if let last = recentEntities[key], now.timeIntervalSince(last) < cooldown {
                    entityLog("Cooldown skip: \(key)"); continue
                }
                seen.insert(key); recentEntities[key] = now
                let associatedCompany = (kind == .person) ? (item["company"] as? String) : nil
                results.append(ExtractedEntity(kind: kind, name: name, associatedCompany: associatedCompany, timestamp: now))
            }
            pruneOldEntities(now: now)
            entityLog("Extraction complete: \(results.count) entities — \(results.map { "\($0.kind.rawValue):\($0.name)" }.joined(separator: ", "))")
            return results
        } catch {
            entityLog("Claude error: \(error.localizedDescription)"); return []
        }
    }

    private func pruneOldEntities(now: Date) {
        let cutoff = now.addingTimeInterval(-cooldown * 3)
        recentEntities = recentEntities.filter { $0.value > cutoff }
    }

    func clearCooldown(for lowerName: String) {
        queue.async { [weak self] in
            self?.recentEntities = self?.recentEntities.filter { !$0.key.hasSuffix(":\(lowerName)") } ?? [:]
        }
    }

    func reset() {
        queue.async { [weak self] in
            self?.recentEntities.removeAll()
            self?.recentCaptions.removeAll()
        }
    }
}
```

---

## CrustdataClient.swift

> **1040 lines** — the largest file. Copy verbatim from `Coyote/CrustdataClient.swift` in this repository. Contains the `CrustdataClient` actor (company/person search, enrich, full enrich, web search, throttling, caching), all public result models (`CrustdataPersonResult`, `PersonEducationEntry`, `PersonEmploymentEntry`, `CrustdataCompanyResult`, `CrustdataWebResult`), and all private `Decodable` API response models.

## IntelligenceEngine.swift

> **684 lines** — the orchestration layer. Copy verbatim from `Coyote/IntelligenceEngine.swift`. Defines `IntelChip`, `IntelligenceInsight`, `CompanyNewsItem`, and the `IntelligenceEngine` class that coordinates entity extraction → Crustdata lookup → insight building → news fetching → full enrich.

## CaptionBarViewModel.swift

> **368 lines** — the central ViewModel. Copy verbatim from `Coyote/CaptionBarViewModel.swift`. Defines `CaptionEntry`, `TranscriptPanelState`, `CaptionBarViewModel`, `PermissionSnapshot`, and `PermissionError`.

## ContentView.swift

> **688 lines** — the complete SwiftUI UI. Copy verbatim from `Coyote/ContentView.swift`. Defines `ContentView` and all private sub-views: `NewsItemRow`, `InsightRow`, `IntelChipRowView`, `EditableCaptionChip`, `TypewriterCaptionView`, `AudioLevelView`, `AnimatedBackdrop`, `PillButtonStyle`, `WindowAccessor`.

---

## File Integrity Summary

| File | Lines | Key Declaration |
|------|-------|-----------------|
| CoyoteApp.swift | 29 | `@main struct CoyoteApp: App` |
| EnvLoader.swift | 52 | `enum Env` |
| AudioUtilities.swift | 118 | `extension CMSampleBuffer` |
| AudioTranscriptionPipeline.swift | 478 | `final class AudioTranscriptionPipeline: @unchecked Sendable` |
| LiveMeetingCapture.swift | 178 | `final class LiveMeetingCapture: NSObject` |
| EntityExtractor.swift | 212 | `final class EntityExtractor: @unchecked Sendable` |
| CrustdataClient.swift | 1040 | `actor CrustdataClient` |
| IntelligenceEngine.swift | 684 | `@MainActor final class IntelligenceEngine: ObservableObject` |
| CaptionBarViewModel.swift | 368 | `@MainActor final class CaptionBarViewModel: ObservableObject` |
| ContentView.swift | 688 | `struct ContentView: View` |
