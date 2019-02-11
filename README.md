# AudioStreamPlayer

A Flutter audio player specifically intended for live streaming. Can play, pause, and stop livestreams, as well as being able to mute itself.

## Usage

Adding the dependency:
```
dependencies:
    flutter:
      sdk: flutter
    audio_stream_player:
```

Creating an audio stream player:

```
import 'package:audio_stream_player/audio_stream_player.dart';
```
```
AudioStreamPlayer player = AudioStreamPlayer();
```

Functions:
```
player.play("url");
player.pause();
player.stop();
player.mute();
```

## Note

This package has not been tested on iOS yet. Any help is appreciated.
