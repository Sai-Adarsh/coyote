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
            return "The captured audio format couldn’t be represented as AVAudioFormat."
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
            self,
            at: 0,
            frameCount: Int32(frameCount),
            into: pcmBuffer.mutableAudioBufferList
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
                for sample in samples {
                    accumulator += Double(abs(sample))
                }
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
