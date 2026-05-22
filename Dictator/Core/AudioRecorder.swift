import AVFoundation
import CoreAudio
import CoreMedia
import Foundation
import os

/// Audio capture postavený na **AVCaptureSession** (ne AVAudioEngine).
///
/// Důvod: AVAudioEngine.inputNode.outputFormat je cached při init, `setDeviceID` na auAudioUnit
/// po init neprojde do tap streamu. Když má uživatel BlackHole / aggregate device, AVAudioEngine
/// čte jejich tiché kanály a peak je 0. AVCaptureSession explicitně bindí na konkrétní
/// AVCaptureDevice instanci a re-resolvuje device při každém startRunning.
actor AudioRecorder {
    private let captureController = AudioCaptureController()
    private let targetSampleRate: Double = 16_000
    private let minimumDuration: Double = 0.3

    private var session: RecordingSession?
    private var recordingStartedAt: Date?
    private var samplesUpdateHandler: (@Sendable () -> Void)?

    private let logger = Logger(subsystem: "com.example.dictator", category: "audio")

    func setSamplesUpdateHandler(_ handler: (@Sendable () -> Void)?) {
        samplesUpdateHandler = handler
    }

    func currentAudioSamples() async -> [Float] {
        guard let session else { return [] }
        return await session.audioSamplesSnapshot()
    }

    func startRecording() throws {
        guard session == nil else { return }

        // Preflight diagnostika — uvidíme co AVCaptureDevice vidí v systému.
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        )
        let devices = discovery.devices
        let summary = devices.map { "\($0.localizedName)#\($0.uniqueID.prefix(8))" }.joined(separator: ", ")
        DiagnosticsLogger.log("AudioRecorder: discovery \(devices.count) devices: [\(summary)]")

        guard let device = AVCaptureDevice.default(for: .audio) else {
            DiagnosticsLogger.log("AudioRecorder: no default audio capture device available")
            throw AudioRecorderError.noInputDevice
        }
        DiagnosticsLogger.log("AudioRecorder: default capture device = \(device.localizedName) (\(device.uniqueID))")

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dictator-\(UUID().uuidString)")
            .appendingPathExtension("wav")

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw AudioRecorderError.unableToCreateFormat
        }

        let file = try AVAudioFile(
            forWriting: url,
            settings: targetFormat.settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )

        let notifySamples = samplesUpdateHandler
        let newSession = RecordingSession(
            url: url,
            file: file,
            targetFormat: targetFormat,
            onSamplesAppended: {
                notifySamples?()
            }
        )

        do {
            try captureController.start(device: device, recordingSession: newSession)
        } catch {
            try? FileManager.default.removeItem(at: url)
            DiagnosticsLogger.log("AudioRecorder: capture start failed: \(error.localizedDescription)")
            throw error
        }

        session = newSession
        recordingStartedAt = Date()
        logger.info("Recording started")
    }

    func stopRecording() async -> RecordingCapture? {
        guard let session else { return nil }

        captureController.stop()
        self.session = nil

        let framesWritten = await session.finish()
        let duration = Double(framesWritten) / targetSampleRate
        recordingStartedAt = nil

        guard duration >= minimumDuration else {
            try? FileManager.default.removeItem(at: session.url)
            logger.info("Discarded short recording")
            DiagnosticsLogger.log("Recording discarded: too short (\(String(format: "%.2f", duration))s)")
            return nil
        }

        let tapPeakRMS = await session.peakRMS()
        let filePeakRMS = AudioLevelAnalyzer.peakRMS(url: session.url)
        DiagnosticsLogger.log(
            "Recording saved: duration=\(String(format: "%.2f", duration))s tapPeak=\(String(format: "%.4f", tapPeakRMS)) filePeak=\(String(format: "%.4f", filePeakRMS))"
        )

        logger.info("Recording stopped")
        // tapPeak is measured from converted PCM before write; filePeak is read back from disk.
        // After AVCaptureSession migration, filePeak is often 0 (WAV read timing/format) while tapPeak
        // is correct — using only filePeak made TranscriptionEngine reject every recording as "too quiet".
        let peakRMS = max(tapPeakRMS, filePeakRMS)
        let audioSamples = await session.audioSamplesSnapshot()
        return RecordingCapture(url: session.url, peakRMS: peakRMS, audioSamples: audioSamples)
    }

    func cancelRecording() async {
        guard let session else { return }

        captureController.stop()
        self.session = nil
        recordingStartedAt = nil

        _ = await session.finish()
        try? FileManager.default.removeItem(at: session.url)
        logger.info("Recording cancelled")
    }
}

enum AudioRecorderError: LocalizedError {
    case unableToCreateFormat
    case noInputDevice

    var errorDescription: String? {
        switch self {
        case .unableToCreateFormat: return "Nepodařilo se připravit formát pro nahrávání."
        case .noInputDevice: return "Žádný vstupní mikrofon nebyl nalezen."
        }
    }
}

// MARK: - Capture controller

/// Drží AVCaptureSession a zpracovává CMSampleBuffer delegate callbacky na vlastní queue.
/// Není actor, ale je thread-safe (stateLock + serial captureQueue).
private final class AudioCaptureController: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let captureSession = AVCaptureSession()
    private let audioOutput = AVCaptureAudioDataOutput()
    private let captureQueue = DispatchQueue(label: "com.example.dictator.capture", qos: .userInteractive)
    private var currentInput: AVCaptureDeviceInput?

    private let stateLock = NSLock()
    private var recordingSession: RecordingSession?
    private var didLogFirstSample = false

    func start(device: AVCaptureDevice, recordingSession: RecordingSession) throws {
        // Vyčisti potenciální předchozí stav (paranoid — actor by neměl volat start 2×).
        stopInternal()

        stateLock.lock()
        self.recordingSession = recordingSession
        self.didLogFirstSample = false
        stateLock.unlock()

        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: device)
        } catch {
            DiagnosticsLogger.log("AudioCaptureController: AVCaptureDeviceInput init failed: \(error.localizedDescription)")
            throw error
        }

        captureSession.beginConfiguration()
        captureSession.inputs.forEach { captureSession.removeInput($0) }
        captureSession.outputs.forEach { captureSession.removeOutput($0) }

        guard captureSession.canAddInput(input) else {
            captureSession.commitConfiguration()
            DiagnosticsLogger.log("AudioCaptureController: canAddInput=false for device \(device.localizedName)")
            throw AudioRecorderError.unableToCreateFormat
        }
        captureSession.addInput(input)
        currentInput = input

        guard captureSession.canAddOutput(audioOutput) else {
            captureSession.commitConfiguration()
            DiagnosticsLogger.log("AudioCaptureController: canAddOutput=false")
            throw AudioRecorderError.unableToCreateFormat
        }
        captureSession.addOutput(audioOutput)
        audioOutput.setSampleBufferDelegate(self, queue: captureQueue)
        captureSession.commitConfiguration()

        captureSession.startRunning()
        DiagnosticsLogger.log("AudioCaptureController: capture session started")
    }

    func stop() {
        stopInternal()
    }

    private func stopInternal() {
        if captureSession.isRunning {
            captureSession.stopRunning()
        }
        stateLock.lock()
        recordingSession = nil
        stateLock.unlock()
    }

    // MARK: AVCaptureAudioDataOutputSampleBufferDelegate

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbdPtr = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) else {
            return
        }
        let asbd = asbdPtr.pointee

        stateLock.lock()
        if !didLogFirstSample {
            didLogFirstSample = true
            DiagnosticsLogger.log("AudioRecorder: first sample ASBD rate=\(Int(asbd.mSampleRate)) ch=\(asbd.mChannelsPerFrame)")
        }
        let activeSession = recordingSession
        stateLock.unlock()

        guard let activeSession else { return }
        guard let pcmBuffer = makePCMBuffer(from: sampleBuffer, asbdPtr: asbdPtr) else { return }
        activeSession.write(pcmBuffer, hardwareSampleRate: asbd.mSampleRate)
    }

    private func makePCMBuffer(
        from sampleBuffer: CMSampleBuffer,
        asbdPtr: UnsafePointer<AudioStreamBasicDescription>
    ) -> AVAudioPCMBuffer? {
        guard let format = AVAudioFormat(streamDescription: asbdPtr) else { return nil }

        let frameCount = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard frameCount > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return nil
        }
        buffer.frameLength = frameCount

        var blockBufferOut: CMBlockBuffer?
        var audioBufferList = AudioBufferList()
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: &audioBufferList,
            bufferListSize: MemoryLayout<AudioBufferList>.size,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: 0,
            blockBufferOut: &blockBufferOut
        )
        guard status == noErr else {
            DiagnosticsLogger.log("AudioCaptureController: GetAudioBufferList failed status=\(status)")
            return nil
        }

        // Single-buffer ABL covers PCM (interleaved or planar single channel).
        let src = audioBufferList.mBuffers
        guard let srcData = src.mData else { return nil }

        let destAbl = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        guard destAbl.count > 0, let destData = destAbl[0].mData else { return nil }

        let copyBytes = min(Int(src.mDataByteSize), Int(destAbl[0].mDataByteSize))
        memcpy(destData, srcData, copyBytes)
        destAbl[0].mDataByteSize = UInt32(copyBytes)

        return buffer
    }
}

// MARK: - Recording session (write pipeline)

private final class RecordingSession: @unchecked Sendable {
    let url: URL

    private let file: AVAudioFile
    private let targetFormat: AVAudioFormat
    private let queue = DispatchQueue(label: "com.example.dictator.audio-writer")
    private let onSamplesAppended: () -> Void

    private let stateLock = NSLock()
    private var converter: AVAudioConverter?
    private var hardwareSampleRate: Double = 0
    private var sourceFormat: AVAudioFormat?

    private var framesWritten = 0
    private var peakRMS: Float = 0
    private var audioSamples: [Float] = []

    init(
        url: URL,
        file: AVAudioFile,
        targetFormat: AVAudioFormat,
        onSamplesAppended: @escaping () -> Void
    ) {
        self.url = url
        self.file = file
        self.targetFormat = targetFormat
        self.onSamplesAppended = onSamplesAppended
    }

    func audioSamplesSnapshot() async -> [Float] {
        await withCheckedContinuation { continuation in
            queue.async {
                self.stateLock.lock()
                let copy = self.audioSamples
                self.stateLock.unlock()
                continuation.resume(returning: copy)
            }
        }
    }

    func write(_ buffer: AVAudioPCMBuffer, hardwareSampleRate: Double) {
        let activeConverter = ensureConverter(for: buffer.format, hardwareSampleRate: hardwareSampleRate)
        guard let activeConverter else { return }

        guard let converted = convert(buffer, using: activeConverter) else { return }
        updatePeakRMS(converted)
        appendSamples(from: converted)
        guard let copied = copyBuffer(converted) else { return }

        queue.async { [file] in
            do {
                try file.write(from: copied)
                self.framesWritten += Int(copied.frameLength)
            } catch {
                // No-op — file write failures shouldn't crash; transcription will see short audio.
            }
        }
    }

    func finish() async -> Int {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: self.framesWritten)
            }
        }
    }

    func peakRMS() async -> Float {
        await withCheckedContinuation { continuation in
            queue.async {
                self.stateLock.lock()
                let value = self.peakRMS
                self.stateLock.unlock()
                continuation.resume(returning: value)
            }
        }
    }

    private func ensureConverter(for sourceFormat: AVAudioFormat, hardwareSampleRate: Double) -> AVAudioConverter? {
        stateLock.lock()
        defer { stateLock.unlock() }
        if let converter, self.sourceFormat == sourceFormat {
            return converter
        }
        let newConverter = AVAudioConverter(from: sourceFormat, to: targetFormat)
        if newConverter == nil {
            DiagnosticsLogger.log("AudioRecorder: AVAudioConverter init failed (source=\(sourceFormat), target=\(targetFormat))")
        }
        converter = newConverter
        self.sourceFormat = sourceFormat
        self.hardwareSampleRate = hardwareSampleRate
        return newConverter
    }

    private func convert(_ buffer: AVAudioPCMBuffer, using converter: AVAudioConverter) -> AVAudioPCMBuffer? {
        stateLock.lock()
        let hwRate = hardwareSampleRate
        stateLock.unlock()
        let ratio = targetFormat.sampleRate / max(hwRate, 1)
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 16)
        guard let converted = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else {
            return nil
        }

        var didProvideInput = false
        var conversionError: NSError?
        converter.convert(to: converted, error: &conversionError) { _, outStatus in
            if didProvideInput {
                outStatus.pointee = .noDataNow
                return nil
            }
            didProvideInput = true
            outStatus.pointee = .haveData
            return buffer
        }

        guard conversionError == nil, converted.frameLength > 0 else { return nil }
        return converted
    }

    private func appendSamples(from buffer: AVAudioPCMBuffer) {
        guard buffer.frameLength > 0,
              let channelData = buffer.floatChannelData else {
            return
        }
        let frameLength = Int(buffer.frameLength)
        let channels = Int(buffer.format.channelCount)
        stateLock.lock()
        if channels == 1 {
            audioSamples.append(contentsOf: UnsafeBufferPointer(start: channelData[0], count: frameLength))
        } else {
            for index in 0..<frameLength {
                var sum: Float = 0
                for channel in 0..<channels {
                    sum += channelData[channel][index]
                }
                audioSamples.append(sum / Float(channels))
            }
        }
        stateLock.unlock()
        onSamplesAppended()
    }

    private func updatePeakRMS(_ buffer: AVAudioPCMBuffer) {
        guard buffer.frameLength > 0 else { return }
        let frameLength = Int(buffer.frameLength)
        let channels = Int(buffer.format.channelCount)
        var peak: Float = 0

        for channel in 0..<channels {
            if let channelData = buffer.floatChannelData?[channel] {
                var sum: Float = 0
                for index in 0..<frameLength {
                    let sample = channelData[index]
                    sum += sample * sample
                }
                peak = max(peak, sqrt(sum / Float(frameLength)))
            } else if let channelData = buffer.int16ChannelData?[channel] {
                var sum: Float = 0
                for index in 0..<frameLength {
                    let sample = Float(channelData[index]) / Float(Int16.max)
                    sum += sample * sample
                }
                peak = max(peak, sqrt(sum / Float(frameLength)))
            }
        }

        guard peak > 0 else { return }
        stateLock.lock()
        if peak > peakRMS { peakRMS = peak }
        stateLock.unlock()
    }

    private func copyBuffer(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameCapacity) else {
            return nil
        }
        copy.frameLength = buffer.frameLength
        guard let source = buffer.floatChannelData, let destination = copy.floatChannelData else {
            return nil
        }
        let byteCount = Int(buffer.frameLength) * MemoryLayout<Float>.size
        for channel in 0..<Int(buffer.format.channelCount) {
            memcpy(destination[channel], source[channel], byteCount)
        }
        return copy
    }
}

struct RecordingCapture: Sendable {
    let url: URL
    let peakRMS: Float
    let audioSamples: [Float]
}
