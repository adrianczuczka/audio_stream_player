import Flutter
import UIKit
import AVFoundation

public class SwiftAudioStreamPlayerPlugin: NSObject, FlutterPlugin {
  private var player: AVPlayer!

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "audio_stream_player", binaryMessenger: registrar.messenger())
    let instance = SwiftAudioStreamPlayerPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch(call.method){
    case "play":
      play(call.argument("url") as String)
      response.success(nil)
    case "pause":
      pause()
      response.success(nil)
    case "stop":
      stop()
      response.success(nil)
    case "mute":
      mute()
      response.success(nil)
    case default:
      print("unexpected state")
    }
  }

  private func play(url: String){
    if(player == nil){
      player = AVPlayer(url: URL(string: url)!)
      player.volume = 1.0
      player.rate = 1.0
    }
    player.play()
  }

  private func pause(){
    if(player != nil){
      player.pause()
    }
  }

  private func stop(){
    player = nil
  }

  private func mute(){
    if(player != nil){
      if(!player.isMuted){
        player.isMuted = true
      }
      else{
        player.isMuted = false
      }
    }
  }
}
