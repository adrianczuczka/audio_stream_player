Pod::Spec.new do |s|
  s.name             = 'audio_stream_player'
  s.version          = '1.0.0'
  s.summary          = 'Low-latency PCM audio streaming player for Flutter.'
  s.description      = <<-DESC
Feed raw PCM chunks from TTS or realtime voice APIs and hear them as they
arrive, with buffer introspection, underrun events, and drain completion.
                       DESC
  s.homepage         = 'https://github.com/adrianczuczka/audio_stream_player'
  s.license          = { :type => 'MIT', :file => '../LICENSE' }
  s.author           = { 'Adrian Czuczka' => 'adrianczuczka@gmail.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'audio_stream_player/Sources/audio_stream_player/**/*.swift'
  s.resource_bundles = {
    'audio_stream_player_privacy' => [
      'audio_stream_player/Sources/audio_stream_player/Resources/PrivacyInfo.xcprivacy'
    ]
  }
  s.ios.dependency 'Flutter'
  s.osx.dependency 'FlutterMacOS'
  s.ios.deployment_target = '13.0'
  s.osx.deployment_target = '10.15'
  s.swift_version = '5.9'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
