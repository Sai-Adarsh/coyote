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
        case .microphone:
            return "Microphone"
        case .systemAudio:
            return "System Audio"
        case .unified:
            return "Live Audio"
        }
    }
}

struct TranscriptUpdate: Sendable {
    let source: CaptionSource
    let text: String
    let isFinal: Bool
}

final class AudioTranscriptionPipeline: @unchecked Sendable {
    private enum State {
        case idle
        case preparing
        case ready
        case failed
    }

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

    // Transcription chunking
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
        source: CaptionSource,
        locale: Locale,
        onTranscript: @escaping @MainActor (TranscriptUpdate) -> Void,
        onLevel: @escaping @MainActor (CaptionSource, Double) -> Void,
        onStatus: @escaping @MainActor (String) -> Void,
        onError: @escaping @MainActor (Error) -> Void
    ) {
        self.source = source
        self.locale = locale
        self.onTranscript = onTranscript
        self.onLevel = onLevel
        self.onStatus = onStatus
        self.onError = onError
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
            Task { @MainActor in
                self.onLevel(src, level)
            }
        } catch { }
    }

    func stop() {
        queue.async {
            self.silenceTimer?.cancel()
            self.silenceTimer = nil
            // Flush any remaining audio
            if !self.pcmAccumulator.isEmpty {
                self.flushChunk()
            }
            self.pendingSamples.removeAll()
            self.pcmAccumulator.removeAll()
            self.overlapBuffer.removeAll()
            self.accumulatedFrames = 0
            self.targetFormat = nil
            self.sourceFormat = nil
            self.converter = nil
            self.lastPartialText = ""
            self.state = .idle
        }
    }

    private func configure(using sampleBuffer: CMSampleBuffer) {
        do {
            let naturalBuffer = try sampleBuffer.makePCMBuffer()

            // gpt-4o-transcribe needs 16kHz mono float32
            let targetFmt = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 16000,
                channels: 1,
                interleaved: false
            )!

            self.targetFormat = targetFmt
            self.sampleRate = 16000
            self.sourceFormat = naturalBuffer.format
            if !Self.formatsMatch(naturalBuffer.format, targetFmt) {
                self.converter = AVAudioConverter(from: naturalBuffer.format, to: targetFmt)
            }

            diag("[\(self.source.rawValue)] configure: \(Self.transcriptionModel) mode, naturalFmt=\(naturalBuffer.format) targetFmt=\(targetFmt) frames=\(naturalBuffer.frameLength)")
            self.state = .ready

            let queued = self.pendingSamples
            self.pendingSamples.removeAll()
            queued.forEach(self.processReady)

            let src = self.source
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.onStatus("\(src.displayName): live transcription ready.")
            }
        } catch {
            state = .failed
            pendingSamples.removeAll()
            Task { @MainActor in
                onError(error)
            }
        }
    }

    private func processReady(_ sampleBuffer: CMSampleBuffer) {
        do {
            let naturalBuffer = try sampleBuffer.makePCMBuffer()
            guard let targetFormat else { return }

            let preparedBuffer = try convertIfNeeded(buffer: naturalBuffer, to: targetFormat)
            let level = preparedBuffer.normalizedPowerLevel()

            // Accumulate PCM samples
            if let channelData = preparedBuffer.floatChannelData {
                let frameCount = Int(preparedBuffer.frameLength)
                let ptr = channelData[0]
                for i in 0..<frameCount {
                    pcmAccumulator.append(ptr[i])
                }
                accumulatedFrames += preparedBuffer.frameLength
            }

            // Reset silence timer
            silenceTimer?.cancel()
            let timer = DispatchWorkItem { [weak self] in
                guard let self else { return }
                // Silence detected — flush whatever we have
                if !self.pcmAccumulator.isEmpty {
                    diag("[\(self.source.rawValue)] silence timer fired, flushing \(self.accumulatedFrames) frames")
                    self.flushChunk()
                }
            }
            silenceTimer = timer
            queue.asyncAfter(deadline: .now() + silenceTimeout, execute: timer)

            // Check if we've accumulated enough audio for a chunk
            let accumulatedDuration = Double(accumulatedFrames) / sampleRate
            if accumulatedDuration >= chunkDuration {
                flushChunk()
            }

            // Emit partial update (show "listening..." indicator)
            if accumulatedDuration > 0.5 && !isTranscribing {
                let src = self.source
                let partialText = lastPartialText.isEmpty ? "Listening..." : lastPartialText
                Task { @MainActor in
                    self.onTranscript(.init(source: src, text: partialText, isFinal: false))
                }
            }

            Task { @MainActor in
                self.onLevel(self.source, level)
            }
        } catch {
            Task { @MainActor in
                self.onError(error)
            }
        }
    }

    private func flushChunk() {
        guard !pcmAccumulator.isEmpty, !isTranscribing else { return }

        // Prepend overlap from previous chunk to avoid losing boundary words
        let samples = overlapBuffer + pcmAccumulator
        // Save the tail as overlap for next chunk
        let overlapFrames = Int(overlapDuration * sampleRate)
        if pcmAccumulator.count > overlapFrames {
            overlapBuffer = Array(pcmAccumulator.suffix(overlapFrames))
        } else {
            overlapBuffer = pcmAccumulator
        }
        pcmAccumulator.removeAll()
        accumulatedFrames = 0
        isTranscribing = true

        let sr = sampleRate
        let src = self.source

        diag("[\(src.rawValue)] flushing \(samples.count) samples (\(String(format: "%.1f", Double(samples.count) / sr))s) to \(Self.transcriptionModel)")

        Task {
            defer {
                self.queue.async { self.isTranscribing = false }
            }

            let wavData = Self.encodeWAV(samples: samples, sampleRate: Int(sr))
            guard let text = await self.transcribeAudio(wavData: wavData) else {
                diag("[\(src.rawValue)] \(Self.transcriptionModel) returned nil")
                return
            }

            let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else {
                diag("[\(src.rawValue)] \(Self.transcriptionModel) returned empty text")
                return
            }

            // Skip hallucinated filler and prompt echo
            let lowerCleaned = cleaned.lowercased()
            let hallucinations = ["thank you", "thanks for watching", "please subscribe", "you", "bye"]
            if hallucinations.contains(where: { lowerCleaned == $0 || lowerCleaned.hasPrefix($0 + ".") || lowerCleaned.hasPrefix($0 + "!") }) {
                diag("[\(src.rawValue)] hallucination filtered: \"\(cleaned)\"")
                return
            }
            // Filter out prompt echo (model repeating back the prompt during silence)
            if lowerCleaned.hasPrefix("this is a business meeting") || lowerCleaned.hasPrefix("accurately transcribe") {
                diag("[\(src.rawValue)] prompt echo filtered: \"\(cleaned.prefix(80))\"")
                return
            }

            diag("[\(src.rawValue)] \(Self.transcriptionModel) result: \"\(cleaned.prefix(120))\"")

            self.queue.async {
                self.lastPartialText = cleaned
            }

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
        // model field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(Self.transcriptionModel)\r\n".data(using: .utf8)!)
        // language field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"language\"\r\n\r\n".data(using: .utf8)!)
        body.append("en\r\n".data(using: .utf8)!)
        // response_format
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"response_format\"\r\n\r\n".data(using: .utf8)!)
        body.append("text\r\n".data(using: .utf8)!)
        // file field
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

            // response_format=text returns plain text
            return String(data: data, encoding: .utf8)
        } catch {
            diag("[\(source.rawValue)] \(Self.transcriptionModel) error: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - WAV Encoding

    private static func encodeWAV(samples: [Float], sampleRate: Int) -> Data {
        let numChannels: Int = 1
        let bitsPerSample: Int = 16
        let byteRate = sampleRate * numChannels * bitsPerSample / 8
        let blockAlign = numChannels * bitsPerSample / 8
        let dataSize = samples.count * 2 // 16-bit = 2 bytes per sample

        var data = Data()

        // RIFF header
        data.append(contentsOf: "RIFF".utf8)
        var chunkSize = UInt32(36 + dataSize).littleEndian
        data.append(Data(bytes: &chunkSize, count: 4))
        data.append(contentsOf: "WAVE".utf8)

        // fmt sub-chunk
        data.append(contentsOf: "fmt ".utf8)
        var subchunk1Size = UInt32(16).littleEndian
        data.append(Data(bytes: &subchunk1Size, count: 4))
        var audioFormat = UInt16(1).littleEndian // PCM
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

        // data sub-chunk
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

    // MARK: - Audio Conversion

    private func convertIfNeeded(buffer: AVAudioPCMBuffer, to outputFormat: AVAudioFormat) throws -> AVAudioPCMBuffer {
        guard !Self.formatsMatch(buffer.format, outputFormat) else {
            return buffer
        }

        if sourceFormat.map({ !Self.formatsMatch($0, buffer.format) }) ?? true {
            sourceFormat = buffer.format
            converter = AVAudioConverter(from: buffer.format, to: outputFormat)
        }

        guard let converter else {
            throw PipelineError.converterUnavailable
        }

        let ratio = outputFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(max(1, ceil(Double(buffer.frameLength) * ratio)))
        guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
            throw PipelineError.outputBufferCreation
        }

        var suppliedInput = false
        var conversionError: NSError?
        let status = converter.convert(to: convertedBuffer, error: &conversionError) { _, outStatus in
            if suppliedInput {
                outStatus.pointee = .noDataNow
                return nil
            }

            suppliedInput = true
            outStatus.pointee = .haveData
            return buffer
        }

        if let conversionError {
            throw conversionError
        }

        guard convertedBuffer.frameLength > 0 else {
            throw PipelineError.emptyConversion(status.rawValue)
        }

        return convertedBuffer
    }

    private static func formatsMatch(_ lhs: AVAudioFormat, _ rhs: AVAudioFormat) -> Bool {
        lhs.commonFormat == rhs.commonFormat &&
        lhs.sampleRate == rhs.sampleRate &&
        lhs.channelCount == rhs.channelCount &&
        lhs.isInterleaved == rhs.isInterleaved
    }
}

enum PipelineError: LocalizedError {
    case unsupportedLocale(String)
    case converterUnavailable
    case outputBufferCreation
    case emptyConversion(Int)

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
