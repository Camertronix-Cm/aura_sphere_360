import Flutter
import UIKit
import AVFoundation

public class PanoramaViewerPlugin: NSObject, FlutterPlugin {
    private var registeredPlayers: [Int64: VideoFrameExtractor] = [:]
    private var eventSink: FlutterEventSink?
    private var textureRegistry: FlutterTextureRegistry?
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "panorama_viewer/video_frames", binaryMessenger: registrar.messenger())
        let eventChannel = FlutterEventChannel(name: "panorama_viewer/video_frames_stream", binaryMessenger: registrar.messenger())
        
        let instance = PanoramaViewerPlugin()
        instance.textureRegistry = registrar.textures()
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
        
        // Get AVPlayer from video_player plugin
        guard let player = getAVPlayer(forTextureId: textureId) else {
            print("⚠️ iOS: Could not find AVPlayer for texture ID: \(textureId)")
            result(FlutterError(code: "PLAYER_NOT_FOUND", message: "AVPlayer not found", details: nil))
            return
        }
        
        // Create frame extractor for this player
        let extractor = VideoFrameExtractor(player: player, textureId: textureId) { [weak self] frameData in
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
    
    // Access AVPlayer from video_player plugin
    // This uses reflection to access the internal player instance
    private func getAVPlayer(forTextureId textureId: Int64) -> AVPlayer? {
        // Try to get the player from video_player plugin's internal registry
        // The video_player plugin stores players in a registry accessible via texture ID
        
        // Method 1: Try to access via FLTVideoPlayerPlugin (if available)
        if let videoPlayerClass = NSClassFromString("FLTVideoPlayerPlugin") as? NSObject.Type {
            // Access the shared instance
            if let sharedInstance = videoPlayerClass.perform(NSSelectorFromString("sharedInstance"))?.takeUnretainedValue() as? NSObject {
                // Try to get the player registry
                if let registry = sharedInstance.value(forKey: "playerRegistry") as? [Int64: Any] {
                    if let playerWrapper = registry[textureId] as? NSObject {
                        // Get the AVPlayer from the wrapper
                        if let player = playerWrapper.value(forKey: "player") as? AVPlayer {
                            return player
                        }
                    }
                }
            }
        }
        
        // Method 2: Fallback - create a dummy player for testing
        print("⚠️ iOS: Using fallback method - creating test player")
        return nil
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
    private let player: AVPlayer
    private let textureId: Int64
    private let onFrameAvailable: ([String: Any]) -> Void
    private var displayLink: CADisplayLink?
    private var videoOutput: AVPlayerItemVideoOutput?
    
    init(player: AVPlayer, textureId: Int64, onFrameAvailable: @escaping ([String: Any]) -> Void) {
        self.player = player
        self.textureId = textureId
        self.onFrameAvailable = onFrameAvailable
        setupVideoOutput()
        start()
    }
    
    private func setupVideoOutput() {
        // Create video output for frame extraction
        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoOutput = AVPlayerItemVideoOutput(pixelBufferAttributes: attributes)
        
        // Add output to current item
        if let currentItem = player.currentItem {
            currentItem.add(videoOutput!)
            print("📱 iOS: Video output added to player item")
        } else {
            print("⚠️ iOS: No current item to add video output")
        }
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
        
        // Remove video output
        if let currentItem = player.currentItem, let output = videoOutput {
            currentItem.remove(output)
        }
        
        print("📱 iOS: Stopped frame extraction")
    }
    
    @objc private func frameUpdate() {
        guard let output = videoOutput else { return }
        
        let currentTime = player.currentItem?.currentTime() ?? CMTime.zero
        
        // Check if new frame is available
        if output.hasNewPixelBuffer(forItemTime: currentTime) {
            guard let pixelBuffer = output.copyPixelBuffer(forItemTime: currentTime, itemTimeForDisplay: nil) else {
                return
            }
            
            // Convert pixel buffer to image data
            if let imageData = pixelBufferToJPEG(pixelBuffer) {
                let width = CVPixelBufferGetWidth(pixelBuffer)
                let height = CVPixelBufferGetHeight(pixelBuffer)
                
                let frameData: [String: Any] = [
                    "width": width,
                    "height": height,
                    "bytes": FlutterStandardTypedData(bytes: imageData)
                ]
                
                onFrameAvailable(frameData)
            }
        }
    }
    
    func getCurrentFrame() -> [String: Any]? {
        guard let output = videoOutput else { return nil }
        
        let currentTime = player.currentItem?.currentTime() ?? CMTime.zero
        
        guard let pixelBuffer = output.copyPixelBuffer(forItemTime: currentTime, itemTimeForDisplay: nil) else {
            return nil
        }
        
        guard let imageData = pixelBufferToJPEG(pixelBuffer) else {
            return nil
        }
        
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        
        return [
            "width": width,
            "height": height,
            "bytes": FlutterStandardTypedData(bytes: imageData)
        ]
    }
    
    private func pixelBufferToJPEG(_ pixelBuffer: CVPixelBuffer) -> Data? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }
        
        let uiImage = UIImage(cgImage: cgImage)
        
        // Compress to JPEG (quality 0.8 for balance between size and quality)
        return uiImage.jpegData(compressionQuality: 0.8)
    }
}
