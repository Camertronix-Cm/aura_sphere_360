import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:ui' as ui;
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'texture_provider.dart';
import 'native_frame_decoder.dart';

/// Native WebRTC texture provider that receives raw pixel data from the
/// `webrtc_pixel_stream` companion plugin via FFI shared memory.
///
/// ## Architecture (Phase 2 — Double-Buffered FFI)
/// 1. Dart allocates two C-memory buffers via [calloc] (buffer A + buffer B).
/// 2. The integer addresses of both buffers are sent to iOS native once at
///    initialisation via a MethodChannel `createPixelStream` call.
/// 3. Native writes each decoded WebRTC frame into one of the two buffers
///    and flips the write index. Only a tiny metadata-only EventChannel
///    event is fired (`bufferIndex`, `width`, `height`, `stride`).
/// 4. Dart reads the indicated buffer (the one native is *not* writing to)
///    via [ffi.Pointer.asTypedList] — zero EventChannel pixel copies.
/// 5. On dispose both buffers are freed with [calloc.free].
///
/// Falls back to the legacy EventChannel `bytes` path for Android / any
/// platform that doesn't send `bufferIndex` in the event.
class NativeWebRTCTextureProvider extends PanoramaTextureProvider {
  // Method channel for the webrtc_pixel_stream companion plugin
  static const MethodChannel _pixelStreamMethod =
      MethodChannel('webrtc_pixel_stream/control');

  /// The RTCVideoRenderer associated with this stream.
  final RTCVideoRenderer renderer;

  /// The MediaStreamTrack.id of the video track to stream pixels from.
  final String trackId;

  /// The peer connection ID, needed for remote track lookup.
  /// Pass null for local tracks (e.g., local camera demo).
  final String? peerConnectionId;

  // ── FFI double-buffer ──────────────────────────────────────────────────
  ffi.Pointer<ffi.Uint8>? _sharedBufferA;
  ffi.Pointer<ffi.Uint8>? _sharedBufferB;
  int _allocatedBytes = 0;

  // ── EventChannel / state ───────────────────────────────────────────────
  EventChannel? _eventChannel;
  StreamSubscription? _sub;
  ui.Image? _currentFrame;
  bool _ready = false;
  bool _decoding = false;
  Map<dynamic, dynamic>? _pendingEvent;

  NativeWebRTCTextureProvider(
    this.renderer, {
    required this.trackId,
    this.peerConnectionId,
  });

  @override
  PanoramaSourceType get sourceType => PanoramaSourceType.webrtc;

  @override
  bool get isReady => _ready;

  // ── Initialisation ─────────────────────────────────────────────────────

  Future<void> _allocateSharedMemory() async {
    // Over-allocate for 4K to prevent frequent re-allocation.
    // 4000 × 4000 × 4 bytes ≈ 64 MB total for both buffers.
    _allocatedBytes = 4000 * 4000 * 4;
    _sharedBufferA = calloc<ffi.Uint8>(_allocatedBytes);
    _sharedBufferB = calloc<ffi.Uint8>(_allocatedBytes);
    debugPrint(
        '🔵 [NativeWebRTCTextureProvider] FFI buffers allocated — '
        'A: 0x${_sharedBufferA!.address.toRadixString(16)}  '
        'B: 0x${_sharedBufferB!.address.toRadixString(16)}  '
        'size: $_allocatedBytes bytes each');
  }

  @override
  Future<void> initialize() async {
    debugPrint(
        '🔵 [NativeWebRTCTextureProvider] initialize() START — track: $trackId');

    try {
      // Allocate double-buffer before calling native so the addresses
      // are valid when native first tries to write.
      await _allocateSharedMemory();

      debugPrint('🔵 [NativeWebRTCTextureProvider] Calling createPixelStream…');

      final result = await _pixelStreamMethod
          .invokeMapMethod<String, dynamic>('createPixelStream', {
        'trackId': trackId,
        'peerConnectionId': peerConnectionId,
        'memoryAddressA': _sharedBufferA!.address,
        'memoryAddressB': _sharedBufferB!.address,
        'memorySize': _allocatedBytes,
      });

      debugPrint(
          '🔵 [NativeWebRTCTextureProvider] createPixelStream returned: $result');

      final String? channelName = result?['channelName'];
      if (channelName == null || channelName.isEmpty) {
        debugPrint(
            '🔴 [NativeWebRTCTextureProvider] Failed — channelName is null/empty');
        _freeBuffers();
        return;
      }

      debugPrint(
          '🔵 [NativeWebRTCTextureProvider] Listening on channel: $channelName');
      _eventChannel = EventChannel(channelName);
      _sub = _eventChannel!
          .receiveBroadcastStream()
          .cast<Map<dynamic, dynamic>>()
          .listen(_onNativeEvent, onError: _onError);

      debugPrint('🟢 [NativeWebRTCTextureProvider] Setup complete');
    } on PlatformException catch (e) {
      debugPrint('🔴 [NativeWebRTCTextureProvider] PlatformException: ${e.message}');
      _freeBuffers();
    } on MissingPluginException catch (e) {
      debugPrint('🔴 [NativeWebRTCTextureProvider] MissingPluginException: ${e.message}');
      _freeBuffers();
    } catch (e, st) {
      debugPrint('🔴 [NativeWebRTCTextureProvider] Unexpected error: $e\n$st');
      _freeBuffers();
    }
  }

  // ── Frame processing ───────────────────────────────────────────────────

  void _onNativeEvent(Map<dynamic, dynamic> event) {
    _pendingEvent = event;
    if (!_decoding) _processNext();
  }

  Future<void> _processNext() async {
    if (_pendingEvent == null) return;
    _decoding = true;
    final event = _pendingEvent!;
    _pendingEvent = null;

    try {
      ui.Image? img;

      final bool isFFIEvent = event.containsKey('bufferIndex') &&
          _sharedBufferA != null &&
          _sharedBufferB != null;

      if (isFFIEvent) {
        // Phase 2 path — read directly from shared FFI memory, no copy
        img = await decodeFFIFrame(event, _sharedBufferA!, _sharedBufferB!);
      } else {
        // Legacy fallback — EventChannel bytes (Android / pre-migration)
        img = await decodeFrameEvent(event);
      }

      if (img != null) {
        _currentFrame?.dispose();
        _currentFrame = img;
        if (!_ready) {
          _ready = true;
          debugPrint(
              '🟢 [NativeWebRTCTextureProvider] First frame ready: '
              '${img.width}x${img.height}');
        }
        notifyListeners();
      }
    } catch (e, st) {
      debugPrint('🔴 [NativeWebRTCTextureProvider] decode error: $e\n$st');
    }

    _decoding = false;
    if (_pendingEvent != null) _processNext();
  }

  void _onError(Object err) {
    debugPrint('🔴 [NativeWebRTCTextureProvider] stream error: $err');
  }

  // ── Public API ─────────────────────────────────────────────────────────

  @override
  Future<ui.Image?> getCurrentFrame() async => _currentFrame;

  // ── Disposal ───────────────────────────────────────────────────────────

  @override
  void dispose() {
    debugPrint('🗑️ [NativeWebRTCTextureProvider] Disposing…');
    _sub?.cancel();
    _sub = null;
    _currentFrame?.dispose();
    _currentFrame = null;
    _pixelStreamMethod.invokeMethod('disposePixelStream', {'trackId': trackId});
    _freeBuffers();
    super.dispose();
    debugPrint('🗑️ [NativeWebRTCTextureProvider] Dispose complete');
  }

  /// Frees both FFI buffers. Safe to call multiple times (guards on null).
  void _freeBuffers() {
    if (_sharedBufferA != null) {
      calloc.free(_sharedBufferA!);
      _sharedBufferA = null;
    }
    if (_sharedBufferB != null) {
      calloc.free(_sharedBufferB!);
      _sharedBufferB = null;
    }
  }
}
