import 'dart:async';
import 'dart:ui' as ui;
import 'dart:typed_data';

/// Converts a raw BGRA event map (from the native EventChannel) to a [ui.Image].
///
/// `decodeImageFromPixels` copies bytes into an ImmutableBuffer on the main
/// isolate (fast memcpy), then hands off to Flutter's engine IO thread for
/// GPU texture upload. The callback fires back on the main isolate.
///
/// This is shared by both [NativeVideoTextureProvider] and
/// [NativeWebRTCTextureProvider].
Future<ui.Image?> decodeFrameEvent(Map<dynamic, dynamic> event) async {
  final int width = event['width'] as int;
  final int height = event['height'] as int;
  final int stride = event['stride'] as int; // bytes per row
  // FlutterStandardTypedData bytes arrive as Uint8List on the Dart side.
  final Uint8List bytes = event['bytes'] as Uint8List;

  // If stride == width * 4, bytes is already tightly packed.
  // If stride > width * 4 (hardware row-alignment padding), strip the padding.
  final Uint8List pixels = _stripPadding(bytes, width, height, stride);

  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    pixels,
    width,
    height,
    ui.PixelFormat.bgra8888, // BGRA from AVFoundation / WebRTC
    (ui.Image img) => completer.complete(img),
  );
  return completer.future;
}

/// Strips hardware row-alignment padding from pixel data.
///
/// AVFoundation and WebRTC may add extra bytes at the end of each row to
/// align to hardware boundaries (e.g., 64-byte alignment). This function
/// removes that padding so the bytes are tightly packed at width*4 per row.
Uint8List _stripPadding(Uint8List src, int width, int height, int stride) {
  final int rowBytes = width * 4;
  if (stride == rowBytes) return src; // fast path — no padding

  final Uint8List dst = Uint8List(rowBytes * height);
  for (int y = 0; y < height; y++) {
    dst.setRange(y * rowBytes, (y + 1) * rowBytes, src, y * stride);
  }
  return dst;
}
