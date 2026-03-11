# WebRTC 360° Video Architecture & FFI Migration Plan

## 1. Executive Summary & Objective

**Objective:** To achieve smooth, 4K/60fps 360-degree WebRTC video streaming in Flutter without dropping frames, spiking CPU, or crashing due to garbage collection (GC) limits.

**The Base Setup:** We are keeping **`panorama_viewer`** (Pure Dart 3D sphere) and modifying **`webrtc_pixel_stream`** (Native WebRTC pixel extractor). Replacing `panorama_viewer` with Native PlatformViews (like `video_360`) is rejected because PlatformViews do not natively ingest WebRTC tracks without enormous C++ rewrites.

**The Pivot:** We are abandoning the `FlutterEventChannel` for pixel transfer. Moving ~1 GB/sec of pixel data over a message channel destroys performance. We will migrate to **FFI Shared Memory** with double-buffering to eliminate EventChannel serialization overhead.

> **Platform scope:** This plan covers **iOS only**. Android would need a similar JNI + direct `ByteBuffer` approach, but the existing EventChannel path remains as a fallback for non-iOS platforms until an Android FFI path is implemented.

---

## 2. Current Architecture Bugs & Limitations

### Bug 1: The "Software Decode" Black Screen (Functional Flaw)
* **File:** `webrtc_pixel_stream/ios/Classes/FlutterRTCStreamingSink.m`
* **Issue:** When a WebRTC peer sends a codec (VP8/VP9) that iOS cannot decode via hardware, WebRTC produces an `RTCI420Buffer` instead of an `RTCCVPixelBuffer`. The current implementation explicitly skips non-CVPixelBuffer frames (line 163-166), causing a permanent black screen for those users.
* **Fix needed:** Implement libyuv `[RTCYUVHelper I420ToBGRA]` conversion for these software frames.

### Bug 2: The `EventChannel` Bottleneck (Performance Flaw)
* **File:** `FlutterRTCStreamingSink.m` and `NativeWebRTCTextureProvider.dart`
* **Issue:** Every frame (up to 33MB for 4K) is packaged into an `NSData` byte array, sent over an `EventChannel`, and deserialized by Dart into a `Uint8List`.
* **Fix needed:** Dart must allocate raw `dart:ffi` memory pointers (double-buffered). iOS Native casts those pointers and writes bytes directly to them. Dart reads the memory instantly from the non-active buffer.

---

## 3. The Target Architecture: Double-Buffered FFI

**The Mechanics:**
1. **Dart:** Allocates **two** `Uint8` memory buffers sized for the maximum expected resolution (e.g., 4K).
2. **Dart -> Native:** Sends the *integer memory addresses* of both buffers to iOS once at initialization.
3. **Native:** Casts the integers back into `uint8_t *` (C-pointers). Maintains a write index (0 or 1).
4. **Native:** Renders the WebRTC frame directly into the current write buffer, then flips the write index.
5. **Native -> Dart:** Fires a tiny EventChannel message: `{"frameReady": true, "bufferIndex": 0, "width": 1920, "height": 1080, "stride": 7680}`.
6. **Dart:** Sees the event, reads from the indicated buffer (which Native is **not** writing to), and calls `ui.decodeImageFromPixels` directly over the memory.

> **Why double-buffering?** WebRTC's render thread fires `renderFrame:` at up to 60fps. Without two buffers, the render thread can overwrite the shared memory while Dart is still reading the previous frame, causing torn/corrupted images. Double-buffering guarantees Dart always reads a complete, stable frame.

---

## 4. Prerequisites

### Dependency: Add `package:ffi` to `pubspec.yaml`
**File:** `aura_sphere_360/pubspec.yaml`

The `calloc` allocator and pointer utilities come from `package:ffi`. This must be added before any Phase 2+ code will compile.

```yaml
dependencies:
  ffi: ^2.1.0          # <-- ADD THIS
  flutter:
    sdk: flutter
  flutter_cube: ^0.1.1
  dchs_motion_sensors: ^2.0.1
  video_player: ^2.9.2
  flutter_webrtc: ^0.11.7
  webrtc_pixel_stream:
    path: ./webrtc_pixel_stream
```

---

## 5. Step-by-Step Implementation Guide (Exact Code)

### Phase 1: Fix the I420 Software Decoding Black Screen
**File:** `webrtc_pixel_stream/ios/Classes/FlutterRTCStreamingSink.m`

**Step 1a:** Add the missing import at the top of the file:

```objc
#import "FlutterRTCStreamingSink.h"
#import <WebRTC/RTCVideoFrame.h>
#import <WebRTC/RTCVideoFrameBuffer.h>
#import <WebRTC/RTCCVPixelBuffer.h>
#import <WebRTC/RTCYUVHelper.h>    // <-- ADD THIS for I420ToBGRA
#import <Accelerate/Accelerate.h>
```

> **Note:** `RTCYUVHelper` is part of the WebRTC SDK's Objective-C wrapper. Verify it's exposed in the `flutter_webrtc` pod's public headers. If it's stripped from the build, you can fall back to raw `libyuv` C calls or use the `vImage` conversion path similar to the existing NV12 handling.

**Step 1b:** Replace the failing `else` block (lines 163-166) with the actual `I420ToBGRA` fallback:

```objc
// Replace this:
// } else {
//   // Software-decoded I420 buffer - use safe conversion without toI420
//   NSLog(@"[FlutterRTCStreamingSink] Warning: Non-CVPixelBuffer frame received, skipping");
// }

// With this:
} else if ([buffer conformsToProtocol:@protocol(RTCI420Buffer)]) {
  // Software decoded frame - fallback safely using LibYUV
  id<RTCI420Buffer> i420Buffer = (id<RTCI420Buffer>)buffer;
  
  int result = [RTCYUVHelper I420ToBGRA:i420Buffer.dataY
                             srcStrideY:i420Buffer.strideY
                                  srcU:i420Buffer.dataU
                            srcStrideU:i420Buffer.strideU
                                  srcV:i420Buffer.dataV
                            srcStrideV:i420Buffer.strideV
                               dstBGRA:dstBGRA
                         dstStrideBGRA:(int)dstStride
                                 width:frame.width
                                height:frame.height];
  
  if (result != 0) {
      NSLog(@"[FlutterRTCStreamingSink] I420ToBGRA conversion failed with code %d", result);
  }
} else {
  // Unknown buffer type - attempt toI420 conversion as a last resort
  id<RTCI420Buffer> i420Buffer = [buffer toI420];
  if (i420Buffer) {
    [RTCYUVHelper I420ToBGRA:i420Buffer.dataY
                  srcStrideY:i420Buffer.strideY
                       srcU:i420Buffer.dataU
                 srcStrideU:i420Buffer.strideU
                       srcV:i420Buffer.dataV
                 srcStrideV:i420Buffer.strideV
                    dstBGRA:dstBGRA
              dstStrideBGRA:(int)dstStride
                      width:frame.width
                     height:frame.height];
  } else {
    NSLog(@"[FlutterRTCStreamingSink] Warning: Unhandled buffer type, skipping frame");
  }
}
```

### Phase 2: Dart FFI Memory Allocation (Double-Buffered)
**File:** `aura_sphere_360/lib/src/native_webrtc_texture_provider.dart`

Add `dart:ffi` and allocate long-lived double-buffered memory for the stream.

```dart
import 'dart:ffi' as ffi;
import 'package:ffi/ffi.dart';

// Inside NativeWebRTCTextureProvider:
ffi.Pointer<ffi.Uint8>? _sharedBufferA;
ffi.Pointer<ffi.Uint8>? _sharedBufferB;
int _allocatedBytes = 0;

Future<void> _allocateSharedMemory(int width, int height) async {
  // Over-allocate for 4K to prevent frequent re-allocation
  // 3840 * 2160 * 4 bytes = 33,177,600 bytes (~32MB per buffer, ~64MB total)
  _allocatedBytes = 4000 * 4000 * 4; 
  _sharedBufferA = calloc<ffi.Uint8>(_allocatedBytes);
  _sharedBufferB = calloc<ffi.Uint8>(_allocatedBytes);
}

// In initialize():
await _allocateSharedMemory(1920, 1080);

final result = await _pixelStreamMethod.invokeMapMethod<String, dynamic>('createPixelStream', {
  'trackId': trackId,
  'peerConnectionId': peerConnectionId,
  'memoryAddressA': _sharedBufferA!.address,  // Buffer A address
  'memoryAddressB': _sharedBufferB!.address,  // Buffer B address
  'memorySize': _allocatedBytes,
});
```

### Phase 3: Native Accepts FFI Pointers and Writes (Double-Buffered)

#### Step 3a: Update the header file
**File:** `webrtc_pixel_stream/ios/Classes/FlutterRTCStreamingSink.h`

```objc
#import <WebRTC/WebRTC.h>
#import <Flutter/Flutter.h>

NS_ASSUME_NONNULL_BEGIN

@interface FlutterRTCStreamingSink : NSObject <RTCVideoRenderer>

- (instancetype)initWithTrackId:(NSString *)trackId
                      messenger:(NSObject<FlutterBinaryMessenger> *)messenger
                  sharedBufferA:(uint8_t *)bufferA
                  sharedBufferB:(uint8_t *)bufferB
                     bufferSize:(size_t)bufferSize;

- (void)dispose;

@end

NS_ASSUME_NONNULL_END
```

#### Step 3b: Update the plugin to pass addresses
**File:** `webrtc_pixel_stream/ios/Classes/WebrtcPixelStreamPlugin.m`

Store the incoming memory pointers and pass them to the sink.

```objc
// In handleCreatePixelStream: — extract FFI addresses from args
NSNumber *addressA = args[@"memoryAddressA"];
NSNumber *addressB = args[@"memoryAddressB"];
NSNumber *sizeNumber = args[@"memorySize"];
uint8_t *sharedBufferA = (uint8_t *)[addressA unsignedLongLongValue];
uint8_t *sharedBufferB = (uint8_t *)[addressB unsignedLongLongValue];
size_t bufferSize = [sizeNumber unsignedIntegerValue];

FlutterRTCStreamingSink *sink = [[FlutterRTCStreamingSink alloc] initWithTrackId:trackId 
                                                                       messenger:_messenger
                                                                   sharedBufferA:sharedBufferA
                                                                   sharedBufferB:sharedBufferB
                                                                      bufferSize:bufferSize];
```

#### Step 3c: Update the sink to write with double-buffering
**File:** `webrtc_pixel_stream/ios/Classes/FlutterRTCStreamingSink.m`

Add double-buffer ivars and alternate writes between buffers.

```objc
@implementation FlutterRTCStreamingSink {
  FlutterEventChannel *_channel;
  FlutterEventSink     _eventSink;
  CVPixelBufferRef     _pixelBuffer;
  CGSize               _bufferSize;
  
  // FFI double-buffering
  uint8_t             *_sharedBufferA;
  uint8_t             *_sharedBufferB;
  size_t               _sharedBufferSize;
  int                  _writeIndex;         // 0 = writing to A, 1 = writing to B
}

// In renderFrame: — write to the current buffer, then flip
- (void)renderFrame:(nullable RTCVideoFrame *)frame {
  // ... (existing null checks and format conversion stay the same) ...
  
  // Select the write target based on _writeIndex
  uint8_t *writeTarget = (_writeIndex == 0) ? _sharedBufferA : _sharedBufferB;
  int currentBufferIndex = _writeIndex;
  
  // Copy BGRA bytes to the FFI buffer instead of NSData
  size_t bytesToCopy = dstStride * frame.height;
  if (bytesToCopy <= _sharedBufferSize) {
      memcpy(writeTarget, dstBGRA, bytesToCopy);
  }
  
  CVPixelBufferUnlockBaseAddress(_pixelBuffer, 0);
  
  // Flip the write index for the next frame
  _writeIndex = 1 - _writeIndex;
  
  // Fire TINY notification to Dart — no pixel data, just metadata
  FlutterEventSink sink = _eventSink;
  if (!sink) return;
  NSDictionary *event = @{
    @"frameReady"   : @(YES),
    @"bufferIndex"  : @(currentBufferIndex),  // tells Dart WHICH buffer to read
    @"width"        : @(frame.width),
    @"height"       : @(frame.height),
    @"stride"       : @(dstStride),
  };
  dispatch_async(dispatch_get_main_queue(), ^{
    sink(event);  // Tiny event — zero pixel data!
  });
}
```

### Phase 4: Dart Decodes from FFI Buffer (Stride-Aware)
**File:** `aura_sphere_360/lib/src/native_frame_decoder.dart`

Add a new function for FFI-based decoding. The existing `decodeFrameEvent` is kept for backward compatibility (Android / fallback).

```dart
/// Decodes a frame from FFI shared memory. Called when the tiny EventChannel
/// notification fires. Uses the `rowBytes` parameter to handle stride padding
/// correctly without needing to strip padding manually.
Future<ui.Image?> decodeFFIFrame(
  Map<dynamic, dynamic> event,
  ffi.Pointer<ffi.Uint8> bufferA,
  ffi.Pointer<ffi.Uint8> bufferB,
) async {
  final int width = event['width'] as int;
  final int height = event['height'] as int;
  final int stride = event['stride'] as int;
  final int bufferIndex = event['bufferIndex'] as int;

  // Select the correct read buffer (opposite of what Native is currently writing to)
  final ffi.Pointer<ffi.Uint8> readPtr = (bufferIndex == 0) ? bufferA : bufferB;

  // Map the FFI pointer to a Dart Uint8List view — no copy!
  final int byteLength = height * stride;
  final Uint8List pixels = readPtr.asTypedList(byteLength);

  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    pixels,       // <--- No data copied over EventChannel! Instant read.
    width,
    height,
    ui.PixelFormat.bgra8888,
    (ui.Image img) {
      completer.complete(img);
    },
    rowBytes: stride,  // <--- CRITICAL: tells Flutter the actual row pitch
                       //      so it handles padding correctly without manual stripping
  );

  return completer.future;
}
```

**Update the event listener in `NativeWebRTCTextureProvider`** to call the new decoder:

```dart
// In _onNativeEvent — detect FFI mode vs fallback:
void _onNativeEvent(Map<dynamic, dynamic> event) {
  _pendingEvent = event;
  if (!_decoding) {
    _processNext();
  }
}

// In _processNext — use FFI decoder when buffers are allocated:
Future<void> _processNext() async {
  if (_pendingEvent == null) return;
  _decoding = true;
  final event = _pendingEvent!;
  _pendingEvent = null;

  try {
    ui.Image? img;
    if (_sharedBufferA != null && _sharedBufferB != null && event.containsKey('bufferIndex')) {
      // FFI path — read directly from shared memory
      img = await decodeFFIFrame(event, _sharedBufferA!, _sharedBufferB!);
    } else {
      // Fallback path — EventChannel bytes (Android, or pre-migration)
      img = await decodeFrameEvent(event);
    }
    
    if (img != null) {
      _currentFrame?.dispose();
      _currentFrame = img;
      if (!_ready) _ready = true;
      notifyListeners();
    }
  } catch (e, st) {
    debugPrint('🔴 [NativeWebRTCTextureProvider] decode error: $e\n$st');
  }

  _decoding = false;
  if (_pendingEvent != null) _processNext();
}
```

### Phase 5: Memory Leak Prevention
**File:** `NativeWebRTCTextureProvider.dart`

FFI memory is strictly unmanaged. Dart's Garbage Collector will **not** clean it up. You must physically free it.

```dart
@override
void dispose() {
  _sub?.cancel();
  _currentFrame?.dispose();
  _pixelStreamMethod.invokeMethod('disposePixelStream', {'trackId': trackId});
  
  // CRITICAL: Free BOTH C-memory buffers to prevent memory leak
  if (_sharedBufferA != null) {
    calloc.free(_sharedBufferA!);
    _sharedBufferA = null;
  }
  if (_sharedBufferB != null) {
    calloc.free(_sharedBufferB!);
    _sharedBufferB = null;
  }
  super.dispose();
}
```

---

## 6. Implementation Sequence & Next Steps for AI/Dev

If handing this off to implement:
1. **Add `ffi: ^2.1.0` to `pubspec.yaml`** and run `flutter pub get`. This is needed before any FFI code compiles.
2. **Execute Phase 1 First:** Edit `FlutterRTCStreamingSink.m` to add the `RTCYUVHelper` import and patch the I420 black screen bug (lines 163-166). This doesn't require FFI and fixes broken streams on old devices immediately.
3. **Execute Phase 2 & 3 Together:** Implement the Dart `ffi` double-buffer allocation in `native_webrtc_texture_provider.dart`, update `FlutterRTCStreamingSink.h` (new init signature), update `WebrtcPixelStreamPlugin.m` (pass addresses), and update `FlutterRTCStreamingSink.m` (double-buffer write logic).
4. **Execute Phase 4 & 5:** Modify the Dart event listener to detect FFI mode (`bufferIndex` in event) and read from the correct shared buffer pointer. Ensure `calloc.free` is called on **both** buffers in dispose. Keep the existing `decodeFrameEvent` as a fallback for Android.
5. **Test Thoroughly:** Use a standard iOS Real Device (not simulator) and monitor CPU and Memory in Xcode Instruments to verify that CPU usage plummets by ~80% during WebRTC reception. Specifically verify:
   - No torn or sheared frames (double-buffer correctness)
   - No memory leaks after dispose (Instruments Allocations track)
   - VP8/VP9 software-decoded streams display correctly (Phase 1 fix)
   - Hardware-decoded H.264 streams still work (regression check)
