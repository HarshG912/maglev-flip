import 'dart:math';
import 'package:flame_audio/flame_audio.dart';

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

  Future<void> init() async {
    FlameAudio.bgm.initialize();
    
    // Preload all audio assets
    await FlameAudio.audioCache.loadAll([
      ...bgmTracks,
      'coin_collector.wav',
      'crash.wav',
      'crash2.wav',
      'Flip.wav',
      'game_over.wav',
      'near_miss.wav',
      'missile_fired.mp3',
      'missile_unlocked.mp3',
    ]);
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
    FlameAudio.bgm.play(fileName, volume: volume);
  }

  void stopBgm() {
    FlameAudio.bgm.stop();
  }

  void playSfx(String fileName, {double volume = 1.0}) {
    if (_isSfxMuted) return;
    FlameAudio.play(fileName, volume: volume);
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
