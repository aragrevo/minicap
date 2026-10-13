import AVFoundation
import ScreenCaptureKit

/// Graba una pantalla con ScreenCaptureKit + SCRecordingOutput.
/// El sistema captura, codifica (HEVC por hardware) y escribe el archivo;
/// los fotogramas nunca pasan por nuestro proceso.
final class Recorder: NSObject, SCStreamDelegate, SCRecordingOutputDelegate {
    struct Options {
        var fps: Int = 30
        var microphone = true
        var systemAudio = true
        var showCursor = true
    }

    private var stream: SCStream?
    private var output: SCRecordingOutput?
    private(set) var fileURL: URL?

    var onFinish: ((Result<URL, Error>) -> Void)?

    var isRecording: Bool { stream != nil }

    func start(options: Options) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = Self.displayUnderMouse(in: content.displays) else {
            throw NSError(domain: "MiniCap", code: 1, userInfo: [NSLocalizedDescriptionKey: "No se encontró ninguna pantalla"])
        }
        // Excluye la propia app (icono de la barra de menús, avisos).
        let me = content.applications.filter { $0.processID == getpid() }
        let filter = SCContentFilter(display: display, excludingApplications: me, exceptingWindows: [])

        let config = SCStreamConfiguration()
        let scale = Int(filter.pointPixelScale)
        config.width = Int(filter.contentRect.width) * scale
        config.height = Int(filter.contentRect.height) * scale
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(options.fps))
        config.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        config.colorSpaceName = CGColorSpace.sRGB
        config.queueDepth = 4
        config.showsCursor = options.showCursor
        config.capturesAudio = options.systemAudio
        config.excludesCurrentProcessAudio = true
        config.captureMicrophone = options.microphone

        let url = Self.newFileURL()
        let recConfig = SCRecordingOutputConfiguration()
        recConfig.outputURL = url
        recConfig.outputFileType = .mp4
        recConfig.videoCodecType = .hevc

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        let output = SCRecordingOutput(configuration: recConfig, delegate: self)
        try stream.addRecordingOutput(output)
        try await stream.startCapture()

        self.stream = stream
        self.output = output
        self.fileURL = url
    }

    func stop() async {
        guard let stream else { return }
        self.stream = nil
        // Al detener la captura, SCRecordingOutput cierra el archivo y llama a
        // recordingOutputDidFinishRecording.
        try? await stream.stopCapture()
    }

    // MARK: SCRecordingOutputDelegate

    func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        output = nil
        if let fileURL { onFinish?(.success(fileURL)) }
    }

    func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
        output = nil
        stream = nil
        onFinish?(.failure(error))
    }

    // MARK: SCStreamDelegate

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        self.stream = nil
        if output != nil {
            output = nil
            onFinish?(.failure(error))
        }
    }

    // MARK: Helpers

    static var folder: URL {
        let movies = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask)[0]
        let dir = movies.appendingPathComponent("MiniCap", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func newFileURL() -> URL {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd 'a las' HH.mm.ss"
        return folder.appendingPathComponent("Grabación \(f.string(from: Date())).mp4")
    }

    private static func displayUnderMouse(in displays: [SCDisplay]) -> SCDisplay? {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        let id = screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        return displays.first { $0.displayID == id } ?? displays.first
    }
}
