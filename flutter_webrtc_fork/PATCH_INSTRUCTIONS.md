# flutter_webrtc Fork — Patch Instructions

This directory contains the **new files** that must be added to a local copy
of `flutter_webrtc 0.11.7` to enable native pixel streaming for panorama_viewer.

## What this fork adds

Two new files (`FlutterRTCStreamingSink.h/.m`) and ~15 lines patched into `FlutterWebRTCPlugin.m`.
**No existing behaviour is changed.**

## Setup steps

### 1. Copy flutter_webrtc source

```bash
# From the project root:
cp -R ~/.pub-cache/hosted/pub.dev/flutter_webrtc-0.11.7 ../flutter_webrtc_fork
```

### 2. Add the streaming sink files

Copy the two files from this directory into the fork:

```bash
cp flutter_webrtc_fork/ios/Classes/FlutterRTCStreamingSink.h \
   ../flutter_webrtc_fork/ios/Classes/
cp flutter_webrtc_fork/ios/Classes/FlutterRTCStreamingSink.m \
   ../flutter_webrtc_fork/ios/Classes/
```

### 3. Patch FlutterWebRTCPlugin.m

Open `../flutter_webrtc_fork/ios/Classes/FlutterWebRTCPlugin.m` and make these changes:

#### a. Add import at the top (near other #import lines):

```objc
#import "FlutterRTCStreamingSink.h"
```

#### b. Add properties to the @interface extension (near other @property declarations):

```objc
@property(nonatomic, strong) NSMutableDictionary<NSString *, FlutterRTCStreamingSink *> *pixelStreams;
@property(nonatomic, strong) NSMutableDictionary<NSString *, RTCVideoTrack *> *pixelStreamTracks;
```

#### c. Initialize dictionaries in `initWithRegistrar:` or `registerWithRegistrar:`

Find where `_localTracks` is initialized and add nearby:

```objc
_pixelStreams = [NSMutableDictionary dictionary];
_pixelStreamTracks = [NSMutableDictionary dictionary];
```

#### d. Add method handlers (find the `captureFrame` handler and add alongside):

```objc
} else if ([@"createPixelStream" isEqualToString:call.method]) {
  NSString *trackId = call.arguments[@"trackId"];
  NSString *peerConnectionId = call.arguments[@"peerConnectionId"];

  RTCMediaStreamTrack *track = [self trackForId:trackId
                               peerConnectionId:peerConnectionId];
  if (!track || ![track isKindOfClass:[RTCVideoTrack class]]) {
    result([FlutterError errorWithCode:@"TRACK_NOT_FOUND"
                               message:@"Video track not found"
                               details:nil]);
    return;
  }

  RTCVideoTrack *videoTrack = (RTCVideoTrack *)track;
  FlutterRTCStreamingSink *sink =
      [[FlutterRTCStreamingSink alloc] initWithTrackId:trackId
                                             messenger:self.messenger];
  [videoTrack addRenderer:sink];

  self.pixelStreams[trackId] = sink;
  self.pixelStreamTracks[trackId] = videoTrack;

  result([NSString stringWithFormat:@"FlutterWebRTC/PixelStream/%@", trackId]);

} else if ([@"disposePixelStream" isEqualToString:call.method]) {
  NSString *trackId = call.arguments[@"trackId"];
  FlutterRTCStreamingSink *sink = self.pixelStreams[trackId];
  if (!sink) { result(nil); return; }

  RTCVideoTrack *videoTrack = self.pixelStreamTracks[trackId];
  if (videoTrack) [videoTrack removeRenderer:sink];

  [sink dispose];
  [self.pixelStreams removeObjectForKey:trackId];
  [self.pixelStreamTracks removeObjectForKey:trackId];
  result(nil);
}
```

### 4. Add dependency_overrides to your pubspec.yaml

```yaml
dependency_overrides:
  flutter_webrtc:
    path: ../flutter_webrtc_fork
```

### 5. Re-run pod install

```bash
cd example/ios && pod install
```

## Verification

After applying the patch, the `createPixelStream` method call from Dart should:
1. Find the video track via `trackForId:peerConnectionId:`
2. Create a `FlutterRTCStreamingSink` and attach it as a renderer
3. Return the EventChannel name (`FlutterWebRTC/PixelStream/{trackId}`)
4. Begin streaming raw BGRA frame bytes to the Dart provider

The `disposePixelStream` method cleanly detaches the renderer and releases resources.
