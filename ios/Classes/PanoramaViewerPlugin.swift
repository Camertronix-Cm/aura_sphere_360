import Flutter
import UIKit
import AVFoundation

public class PanoramaViewerPlugin: NSObject, FlutterPlugin {
    private var registeredPlayers: [Int64: VideoFrameExtractor] = [:]
    private var eventSink: FlutterEventSink?
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "panorama_viewer/video_frames", binaryMessenger: registrar.messenger())
        let eventChannel = FlutterEventChannel(name: "panorama_viewer/video_frames_stream", binaryMessenger: registrar.messenger())
        
        let instance = PanoramaViewerPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
        eventChannel.setStreamHandler(instance)
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "registerVideoPlayer":
            handleRegisterVideoPlayer(call, result: result)
        case "unregisterVideoPlayer":
            handleUnregisterVideoPlayer(call, result: result)
        case "getCurrentFrame":
            handleGetCurrentFrame(call, result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    private func handleRegisterVideoPlayer(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let textureId = args["textureId"] as? Int64 else {
            result(FlutterError(code: "INVALID_ARGS", message: "Missing textureId", details: nil))
            return
        }
        
        print("📱 iOS: Registering video player with texture ID: \(textureId)")
        
        // Create frame extractor for this texture
        let extractor = VideoFrameExtractor(textureId: textureId) { [weak self] frameData in
            self?.sendFrameToFlutter(frameData)
        }
        
        registeredPlayers[textureId] = extractor
        
        result(["success": true, "message": "Video player registered"])
    }
    
    private func handleUnregisterVideoPlayer(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let textureId = args["textureId"] as? Int64 else {
            result(FlutterError(code: "INVALID_ARGS", message: "Missing textureId", details: nil))
            return
        }
        
        print("📱 iOS: Unregistering video player with texture ID: \(textureId)")
        
        registeredPlayers[textureId]?.stop()
        registeredPlayers.removeValue(forKey: textureId)
        
        result(["success": true])
    }
    
    private func handleGetCurrentFrame(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let textureId = args["textureId"] as? Int64 else {
            result(FlutterError(code: "INVALID_ARGS", message: "Missing textureId", details: nil))
            return
        }
        
        guard let extractor = registeredPlayers[textureId] else {
            result(FlutterError(code: "NOT_REGISTERED", message: "Video player not registered", details: nil))
            return
        }
        
        if let frameData = extractor.getCurrentFrame() {
            result(frameData)
        } else {
            result(nil)
        }
    }
    
    private func sendFrameToFlutter(_ frameData: [String: Any]) {
        eventSink?(frameData)
    }
}

// MARK: - FlutterStreamHandler
extension PanoramaViewerPlugin: FlutterStreamHandler {
    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        return nil
    }
    
    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self.eventSink = nil
        return nil
    }
}

// MARK: - VideoFrameExtractor
class VideoFrameExtractor {
    private let textureId: Int64
    private let onFrameAvailable: ([String: Any]) -> Void
    private var displayLink: CADisplayLink?
    
    init(textureId: Int64, onFrameAvailable: @escaping ([String: Any]) -> Void) {
        self.textureId = textureId
        self.onFrameAvailable = onFrameAvailable
        start()
    }
    
    func start() {
        // Create display link for 60 FPS updates
        displayLink = CADisplayLink(target: self, selector: #selector(frameUpdate))
        displayLink?.preferredFramesPerSecond = 60
        displayLink?.add(to: .main, forMode: .common)
        
        print("📱 iOS: Started frame extraction at 60 FPS")
    }
    
    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        print("📱 iOS: Stopped frame extraction")
    }
    
    @objc private func frameUpdate() {
        // TODO: Extract actual frame from AVPlayer
        // For now, this is a placeholder
        // In full implementation, we would:
        // 1. Get AVPlayer from video_player plugin
        // 2. Use AVPlayerItemVideoOutput to get CVPixelBuffer
        // 3. Convert CVPixelBuffer to PNG/JPEG bytes
        // 4. Send to Flutter
        
        // Placeholder implementation
        // In real implementation, extract frame here
    }
    
    func getCurrentFrame() -> [String: Any]? {
        // TODO: Implement actual frame extraction
        // This would use AVPlayerItemVideoOutput.copyPixelBuffer
        return nil
    }
}
