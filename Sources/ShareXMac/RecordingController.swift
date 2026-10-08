import AVFoundation
import ScreenCaptureKit

@MainActor
final class RecordingController: NSObject, ObservableObject {
    enum Phase: Equatable { case idle, countdown(Int), starting, recording, stopping }
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var startedAt: Date?
    var onFailure: ((Error) -> Void)?
    var onExternalFinish: ((URL) -> Void)?
    var onStarted: (() -> Void)?
    var isActive: Bool { phase != .idle }
    var canStop: Bool { phase == .recording }
    private var stream: SCStream?
    private var output: SCRecordingOutput?
    private var url: URL?
    private var sessionID = UUID()
    private var finished: Result<URL, Error>?
    private var stoppedBySystem = false
    private var waiter: CheckedContinuation<URL, Error>?
    private var watchdog: Task<Void, Never>?

    func start(source: CaptureSource, destination: URL, systemAudio: Bool, microphone: Bool, cursor: Bool, gif: Bool = false) async throws {
        guard !isActive else { return }
        sessionID = UUID()
        finished = nil
        stoppedBySystem = false
        do {
            if microphone {
                let allowed = await AVCaptureDevice.requestAccess(for: .audio)
                guard allowed else {
                    throw CaptureError.message("Microphone access was denied. Enable it in System Settings, or turn off microphone recording.")
                }
            }
            for second in (1...3).reversed() {
                phase = .countdown(second)
                try await Task.sleep(for: .seconds(1))
            }
            phase = .starting
            url = destination
            let config = source.configuration(recording: true, cursor: cursor)
            if gif {
                let factor = min(1, 960.0 / Double(max(config.width, config.height)))
                config.width = max(2, Int(Double(config.width) * factor) / 2 * 2)
                config.height = max(2, Int(Double(config.height) * factor) / 2 * 2)
                config.minimumFrameInterval = CMTime(value: 1, timescale: 10)
            }
            config.capturesAudio = systemAudio
            config.excludesCurrentProcessAudio = true
            config.captureMicrophone = microphone
            if microphone { config.microphoneCaptureDeviceID = AVCaptureDevice.default(for: .audio)?.uniqueID }
            let stream = SCStream(filter: source.filter, configuration: config, delegate: self)
            let recordingConfig = SCRecordingOutputConfiguration()
            recordingConfig.outputURL = destination
            recordingConfig.outputFileType = .mp4
            recordingConfig.videoCodecType = .h264
            let output = SCRecordingOutput(configuration: recordingConfig, delegate: self)
            self.stream = stream
            self.output = output
            try stream.addRecordingOutput(output)
            try await stream.startCapture()
            armWatchdog(seconds: 15, message: "The recording did not start. Try selecting a new source.")
        } catch {
            cleanup()
            throw error
        }
    }

    func stop() async throws -> URL {
        guard let stream, phase == .recording else {
            throw CaptureError.message("There is no active recording to stop.")
        }
        phase = .stopping
        do { try await stream.stopCapture() }
        catch { fail(error); throw error }
        // The stream stopping does not guarantee the movie has finished writing.
        return try await withCheckedThrowingContinuation { continuation in
            if let finished { continuation.resume(with: finished) }
            else {
                waiter = continuation
                armWatchdog(seconds: 30, message: "The movie did not finish saving. Any partial recording is kept in InProgress.")
            }
        }
    }

    private func armWatchdog(seconds: Int, message: String) {
        watchdog?.cancel()
        let id = sessionID
        watchdog = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
            guard let self, self.sessionID == id, self.phase != .idle,
                  self.phase != .recording else { return }
            self.fail(CaptureError.message(message))
        }
    }
    private func fail(_ error: Error) {
        finished = .failure(error)
        let pending = waiter
        waiter = nil
        let activeStream = stream
        cleanup()
        pending?.resume(throwing: error)
        if pending == nil { onFailure?(error) }
        if let activeStream { Task { try? await activeStream.stopCapture() } }
    }
    private func cleanup() {
        watchdog?.cancel(); watchdog = nil
        phase = .idle; startedAt = nil; stream = nil; output = nil; url = nil
    }
}

extension RecordingController: SCRecordingOutputDelegate, SCStreamDelegate {
    nonisolated func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) {
        Task { @MainActor [weak self] in
            guard let self, self.output === recordingOutput else { return }
            self.watchdog?.cancel()
            self.startedAt = Date()
            self.phase = .recording
            self.onStarted?()
        }
    }
    nonisolated func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            guard let self, self.output === recordingOutput else { return }
            self.fail(error)
        }
    }
    nonisolated func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        Task { @MainActor [weak self] in
            guard let self, self.output === recordingOutput, let url = self.url else { return }
            let requested = self.phase == .stopping && !self.stoppedBySystem
            self.finished = .success(url)
            let pending = self.waiter
            self.waiter = nil
            self.cleanup()
            pending?.resume(returning: url)
            if !requested { self.onExternalFinish?(url) }
        }
    }
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor [weak self] in
            guard let self, self.stream === stream else { return }
            let systemError = error as NSError
            if systemError.domain == SCStreamErrorDomain && systemError.code == SCStreamError.Code.userStopped.rawValue {
                self.stoppedBySystem = true
                self.phase = .stopping
                self.armWatchdog(seconds: 30, message: "The stopped recording did not finish saving. Check InProgress for partial files.")
                return
            }
            self.fail(error)
        }
    }
}
