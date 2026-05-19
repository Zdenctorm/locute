import AVFoundation
import Foundation

enum AudioLevelAnalyzer {
    /// Peak RMS z WAV souboru — spolehlivější než měření za běhu tapu.
    static func peakRMS(url: URL) -> Float {
        do {
            let file = try AVAudioFile(forReading: url)
            guard let format = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: file.processingFormat.sampleRate,
                channels: 1,
                interleaved: false
            ) else {
                return 0
            }

            let frameCount = AVAudioFrameCount(file.length)
            guard frameCount > 0,
                  let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: min(frameCount, 16_000 * 30)) else {
                return 0
            }

            var peak: Float = 0
            var framesRead: AVAudioFramePosition = 0

            while framesRead < file.length {
                buffer.frameLength = 0
                try file.read(into: buffer)
                guard buffer.frameLength > 0 else { break }
                peak = max(peak, rms(of: buffer))
                framesRead += AVAudioFramePosition(buffer.frameLength)
            }

            return peak
        } catch {
            DiagnosticsLogger.log("AudioLevelAnalyzer failed: \(error.localizedDescription)")
            return 0
        }
    }

    private static func rms(of buffer: AVAudioPCMBuffer) -> Float {
        guard buffer.frameLength > 0 else { return 0 }
        let frameLength = Int(buffer.frameLength)
        let channels = Int(buffer.format.channelCount)
        var peak: Float = 0

        for channel in 0..<channels {
            if let floats = buffer.floatChannelData?[channel] {
                var sum: Float = 0
                for index in 0..<frameLength {
                    let sample = floats[index]
                    sum += sample * sample
                }
                peak = max(peak, sqrt(sum / Float(frameLength)))
            } else if let ints = buffer.int16ChannelData?[channel] {
                var sum: Float = 0
                for index in 0..<frameLength {
                    let sample = Float(ints[index]) / Float(Int16.max)
                    sum += sample * sample
                }
                peak = max(peak, sqrt(sum / Float(frameLength)))
            }
        }

        return peak
    }
}
