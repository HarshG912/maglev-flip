import 'dart:math';
import 'package:audioplayers/audioplayers.dart';

class AudioManager {
  static final AudioManager _instance = AudioManager._internal();
  factory AudioManager() => _instance;
  AudioManager._internal();

  bool _isBgmMuted = false;
  bool _isSfxMuted = false;

  bool get isBgmMuted => _isBgmMuted;
  bool get isSfxMuted => _isSfxMuted;

  String _currentBgmTrack = 'background1.mp3';
  String get currentBgmTrack => _currentBgmTrack;

  // Track list for UI dropdown
  final List<String> bgmTracks = [
    'background1.mp3',
    'background2.mp3',
    'background3.mp3',
    'background4.mp3',
  ];

  final Random _random = Random();
  final AudioPlayer _localBgmPlayer = AudioPlayer();

  Future<void> init() async {
    await _localBgmPlayer.setReleaseMode(ReleaseMode.loop);
    // Note: With modern audioplayers, we don't need to explicitly preload small SFX files
    // as they load instantly from the asset bundle when requested.
  }

  void setBgmTrack(String trackName) {
    if (!bgmTracks.contains(trackName)) return;
    _currentBgmTrack = trackName;
    if (!_isBgmMuted) {
      stopBgm();
      playBgm(_currentBgmTrack);
    }
  }

  void playBgm(String fileName, {double volume = 0.4}) {
    if (_isBgmMuted) return;
    _localBgmPlayer.play(AssetSource('audio/$fileName'), volume: volume).catchError((e) {
      print("Error playing local BGM $fileName: $e");
    });
  }

  void stopBgm() {
    _localBgmPlayer.stop();
  }

  void playSfx(String fileName, {double volume = 1.0}) async {
    if (_isSfxMuted) return;
    try {
      final player = AudioPlayer();
      await player.play(AssetSource('audio/$fileName'), volume: volume);
      player.onPlayerComplete.listen((_) => player.dispose());
    } catch (e) {
      print("Error playing SFX $fileName: $e");
    }
  }

  void playRandomCrash() {
    if (_isSfxMuted) return;
    final String crashSound = _random.nextBool() ? 'crash.wav' : 'crash2.wav';
    playSfx(crashSound, volume: 1.0);
  }

  void toggleBgm() {
    _isBgmMuted = !_isBgmMuted;
    if (_isBgmMuted) {
      stopBgm();
    } else {
      playBgm(_currentBgmTrack);
    }
  }

  void toggleSfx() {
    _isSfxMuted = !_isSfxMuted;
  }
}
