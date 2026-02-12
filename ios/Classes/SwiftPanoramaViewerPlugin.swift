// This file is just for backwards compatibility
// The actual implementation is in PanoramaViewerPlugin.swift
import Flutter
import UIKit

public class SwiftPanoramaViewerPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    PanoramaViewerPlugin.register(with: registrar)
  }
}
