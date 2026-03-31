# Keep WebRTC classes from being stripped by R8
-keep class org.webrtc.** { *; }
-keep class com.cloudwebrtc.webrtc.** { *; }
-keep class com.camertronix.webrtc_pixel_stream.** { *; }

# Keep StateProvider interface for reflection access
-keep interface com.cloudwebrtc.webrtc.StateProvider { *; }

# Keep VideoSink implementations
-keep class * implements org.webrtc.VideoSink { *; }

# Keep native methods
-keepclasseswithmembernames class * {
    native <methods>;
}
