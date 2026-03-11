import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';

/// Decodes a frame from Dart-allocated FFI shared memory.
///
/// Called when the tiny metadata-only EventChannel notification fires from
/// native. Reads directly from the indicated double-buffer pointer — no
/// pixel data was ever serialised over the EventChannel.
///
/// Uses `rowBytes:` so Flutter handles row-alignment padding (common on iOS
/// where AVFoundation pads rows to 64-byte boundaries) without manual stripping.
Future<ui.Image?> decodeFFIFrame(
  Map<dynamic, dynamic> event,
  ffi.Pointer<ffi.Uint8> bufferA,
  ffi.Pointer<ffi.Uint8> bufferB,
) async {
  final int width = event['width'] as int;
  final int height = event['height'] as int;
  final int stride = event['stride'] as int;
  final int bufferIndex = event['bufferIndex'] as int;

  // Read from the buffer native just finished writing (not the one
  // it will write next). Double-buffering guarantees this is stable.
  final ffi.Pointer<ffi.Uint8> readPtr =
      (bufferIndex == 0) ? bufferA : bufferB;

  // asTypedList is a zero-copy view over the C memory.
  final int byteLength = height * stride;
  final Uint8List pixels = readPtr.asTypedList(byteLength);

  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    pixels,
    width,
    height,
    ui.PixelFormat.bgra8888,
    (ui.Image img) => completer.complete(img),
    rowBytes: stride, // handles iOS row-alignment padding without manual stripping
  );

  return completer.future;
}

/// Legacy path: decodes a raw BGRA event map sent over the EventChannel.
///
/// Used as a fallback on Android and any platform that sends pixel bytes
/// in the event rather than writing to FFI shared memory.
///
/// `decodeImageFromPixels` copies bytes into an ImmutableBuffer on the main
/// isolate (fast memcpy), then hands off to Flutter's engine IO thread for
/// GPU texture upload. The callback fires back on the main isolate.
Future<ui.Image?> decodeFrameEvent(Map<dynamic, dynamic> event) async {
  debugPrint('🔵 [decodeFrameEvent] START (legacy EventChannel path)');

  final int width = event['width'] as int;
  final int height = event['height'] as int;
  final int stride = event['stride'] as int;
  final Uint8List bytes = event['bytes'] as Uint8List;

  debugPrint(
      '🔵 [decodeFrameEvent] ${width}x$height stride=$stride bytes=${bytes.length}');

  // Strip hardware row-alignment padding if needed
  final Uint8List pixels = _stripPadding(bytes, width, height, stride);

  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    pixels,
    width,
    height,
    ui.PixelFormat.bgra8888,
    (ui.Image img) {
      debugPrint(
          '🟢 [decodeFrameEvent] Decoded: ${img.width}x${img.height}');
      completer.complete(img);
    },
  );

  return completer.future;
}

/// Strips hardware row-alignment padding from pixel data (legacy path only).
///
/// AVFoundation and WebRTC may add extra bytes at the end of each row to
/// align to hardware boundaries (e.g., 64-byte alignment). Strips that so
/// bytes are tightly packed at width*4 per row.
Uint8List _stripPadding(Uint8List src, int width, int height, int stride) {
  final int rowBytes = width * 4;
  if (stride == rowBytes) return src; // fast path — no padding
  final Uint8List dst = Uint8List(rowBytes * height);
  for (int y = 0; y < height; y++) {
    dst.setRange(y * rowBytes, (y + 1) * rowBytes, src, y * stride);
  }
  return dst;
}
