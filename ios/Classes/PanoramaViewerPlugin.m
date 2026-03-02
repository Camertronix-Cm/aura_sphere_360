#import "PanoramaViewerPlugin.h"
#import "PanoramaVideoExtractor.h"

@interface PanoramaViewerPlugin ()
@property(nonatomic, strong) NSMutableDictionary<NSString *, PanoramaVideoExtractor *> *extractors;
@property(nonatomic, strong) NSObject<FlutterPluginRegistrar> *registrar;
@end

@implementation PanoramaViewerPlugin

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar {
  FlutterMethodChannel *channel =
      [FlutterMethodChannel methodChannelWithName:@"panorama_viewer/control"
                                  binaryMessenger:[registrar messenger]];
  PanoramaViewerPlugin *instance = [[PanoramaViewerPlugin alloc] init];
  instance.registrar = registrar;
  instance.extractors = [NSMutableDictionary dictionary];
  [registrar addMethodCallDelegate:instance channel:channel];
}

- (void)handleMethodCall:(FlutterMethodCall *)call
                  result:(FlutterResult)result {

  if ([@"createVideoExtractor" isEqualToString:call.method]) {
    NSString *urlString = call.arguments[@"url"];
    if (!urlString || [urlString length] == 0) {
      result([FlutterError errorWithCode:@"INVALID_URL"
                                 message:@"URL must not be empty"
                                 details:nil]);
      return;
    }

    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) {
      // Try as file path if URL parsing fails
      url = [NSURL fileURLWithPath:urlString];
    }

    // Create a unique channel name for this extractor
    NSString *channelName =
        [NSString stringWithFormat:@"panorama_viewer/video_frames/%@",
                                   @(self.extractors.count)];

    FlutterEventChannel *eventChannel =
        [FlutterEventChannel eventChannelWithName:channelName
                                binaryMessenger:[self.registrar messenger]];

    PanoramaVideoExtractor *extractor =
        [[PanoramaVideoExtractor alloc] initWithURL:url
                                      eventChannel:eventChannel];

    self.extractors[channelName] = extractor;
    result(channelName);

  } else if ([@"videoPlay" isEqualToString:call.method]) {
    NSString *extractorId = call.arguments[@"id"];
    PanoramaVideoExtractor *ex = self.extractors[extractorId];
    if (ex) [ex play];
    result(nil);

  } else if ([@"videoPause" isEqualToString:call.method]) {
    NSString *extractorId = call.arguments[@"id"];
    PanoramaVideoExtractor *ex = self.extractors[extractorId];
    if (ex) [ex pause];
    result(nil);

  } else if ([@"videoSeek" isEqualToString:call.method]) {
    NSString *extractorId = call.arguments[@"id"];
    NSNumber *seconds = call.arguments[@"seconds"];
    PanoramaVideoExtractor *ex = self.extractors[extractorId];
    if (ex && seconds) [ex seekTo:[seconds doubleValue]];
    result(nil);

  } else if ([@"videoSetLooping" isEqualToString:call.method]) {
    NSString *extractorId = call.arguments[@"id"];
    NSNumber *looping = call.arguments[@"looping"];
    PanoramaVideoExtractor *ex = self.extractors[extractorId];
    if (ex && looping) [ex setLooping:[looping boolValue]];
    result(nil);

  } else if ([@"disposeVideoExtractor" isEqualToString:call.method]) {
    NSString *extractorId = call.arguments[@"id"];
    PanoramaVideoExtractor *ex = self.extractors[extractorId];
    if (ex) {
      [ex dispose];
      [self.extractors removeObjectForKey:extractorId];
    }
    result(nil);

  } else {
    result(FlutterMethodNotImplemented);
  }
}

@end
