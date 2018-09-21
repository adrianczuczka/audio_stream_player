#import "AudioStreamPlayerPlugin.h"
#import <audio_stream_player/audio_stream_player-Swift.h>

@implementation AudioStreamPlayerPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  [SwiftAudioStreamPlayerPlugin registerWithRegistrar:registrar];
}
@end
