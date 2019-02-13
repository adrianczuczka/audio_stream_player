import 'package:flutter/material.dart';
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:audio_stream_player/audio_stream_player.dart';

void main() => runApp(new MyApp());

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => new _MyAppState();
}

class _MyAppState extends State<MyApp> {
  AudioStreamPlayer player = AudioStreamPlayer();
  bool isPlaying = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return new MaterialApp(
      home: new Scaffold(
        appBar: new AppBar(
          title: const Text('Plugin example app'),
        ),
        body: Center(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: <Widget>[
              IconButton(
                icon: Icon(Icons.fiber_manual_record),
                onPressed: () {
                  reset();
                },
                color: Colors.red,
                iconSize: 60.0,
              ),
              IconButton(
                icon: Icon(isPlaying
                    ? Icons.pause_circle_filled
                    : Icons.play_circle_filled),
                onPressed: () {
                  isPlaying ? pause() : play();
                },
                iconSize: 100.0,
              ),
              IconButton(
                icon: Icon(Icons.stop),
                onPressed: () {
                  player.stop();
                },
                iconSize: 60.0,
              )
            ],
          ),
        ),
      ),
    );
  }

  void play() {
    player.play("http://radio.freshair.org.uk/radio");
    setState(() {
      isPlaying = true;
    });
  }

  void pause() {
    player.pause();
    setState(() {
      isPlaying = false;
    });
  }

  void stop() {
    player.stop();
    setState(() {
      isPlaying = false;
    });
  }

  void reset() {
    stop();
    play();
  }

  @override
  void dispose() {
    player.stop();
    super.dispose();
  }
}
