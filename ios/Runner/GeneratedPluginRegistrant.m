//
//  Generated file. Do not edit.
//

// clang-format off

#import "GeneratedPluginRegistrant.h"

#if __has_include(<dchs_motion_sensors/MotionSensorsPlugin.h>)
#import <dchs_motion_sensors/MotionSensorsPlugin.h>
#else
@import dchs_motion_sensors;
#endif

#if __has_include(<flutter_webrtc/FlutterWebRTCPlugin.h>)
#import <flutter_webrtc/FlutterWebRTCPlugin.h>
#else
@import flutter_webrtc;
#endif

#if __has_include(<path_provider_foundation/PathProviderPlugin.h>)
#import <path_provider_foundation/PathProviderPlugin.h>
#else
@import path_provider_foundation;
#endif

#if __has_include(<video_player_avfoundation/FVPVideoPlayerPlugin.h>)
#import <video_player_avfoundation/FVPVideoPlayerPlugin.h>
#else
@import video_player_avfoundation;
#endif

#if __has_include(<webrtc_pixel_stream/WebrtcPixelStreamPlugin.h>)
#import <webrtc_pixel_stream/WebrtcPixelStreamPlugin.h>
#else
@import webrtc_pixel_stream;
#endif

@implementation GeneratedPluginRegistrant

+ (void)registerWithRegistry:(NSObject<FlutterPluginRegistry>*)registry {
  [MotionSensorsPlugin registerWithRegistrar:[registry registrarForPlugin:@"MotionSensorsPlugin"]];
  [FlutterWebRTCPlugin registerWithRegistrar:[registry registrarForPlugin:@"FlutterWebRTCPlugin"]];
  [PathProviderPlugin registerWithRegistrar:[registry registrarForPlugin:@"PathProviderPlugin"]];
  [FVPVideoPlayerPlugin registerWithRegistrar:[registry registrarForPlugin:@"FVPVideoPlayerPlugin"]];
  [WebrtcPixelStreamPlugin registerWithRegistrar:[registry registrarForPlugin:@"WebrtcPixelStreamPlugin"]];
}

@end
