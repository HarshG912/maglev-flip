import 'dart:async' hide Timer;
import 'dart:convert';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flame/effects.dart';
import 'package:flutter/painting.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flame/particles.dart';
import 'package:flame/collisions.dart';
import 'package:flame/camera.dart';
import 'package:csv/csv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:audioplayers/audioplayers.dart';
import 'audio_manager.dart';

class QuizCategory {
  final String name;
  final String csvUrl;
  final String shareCode;
  final bool isPublic;

  QuizCategory(this.name, this.csvUrl, {this.shareCode = '', this.isPublic = true});
}

class QuizQuestion {
  final String text;
  final String correctAnswer;
  final List<String> allOptions; // Now holds ANY number of options

  QuizQuestion(this.text, this.correctAnswer, this.allOptions);
}

class MaglevFlipGame extends FlameGame with TapCallbacks, HasCollisionDetection {
  MaglevFlipGame() : super(
    camera: CameraComponent.withFixedResolution(
      width: 1280, 
      height: 720,
    )..viewfinder.anchor = Anchor.topLeft,
  );

  late final RailComponent rail;
  late final PlayerComponent player;
  
  double _spawnTimer = 0.0;
  final random = Random();
  double gameSpeed = 300.0;
  double score = 0;
  int shardsCollected = 0; // Track total loot collected in the run
  
  int bankBalance = 0; // Total coins saved in DB
  List<String> unlockedSkins = [];
  String activeSkin = 'default_train';
  List<Map<String, dynamic>> liveShopInventory = [];

  bool isGameOver = false;
  Obstacle? collidedObstacle;
  
  // Create a quick reference to the Supabase client
  final supabase = Supabase.instance.client;
  
  List<QuizCategory> availableCategories = []; 
  List<QuizQuestion> activeQuestions = []; // The loaded subject
  QuizQuestion? currentQuestion;
  QuizCategory? activeCategory;
  List<Map<String, dynamic>> currentTop5 = []; // Store the top 5 players for the HUD
  bool isDownloading = false; // Used to show a loading state on the UI
  bool isDirectoryLoaded = false; // Used to prevent infinite spinning when database is empty
  bool isPlayForFun = false; // Tracks if the player bypassed trivia
  bool isHitStop = false; // Tracks if we are currently playing the crash sequence
  double preCrashSpeed = 300.0; // Tracks speed before crash
  bool isTriviaFromPowerup = false; // Tracks if the quiz was triggered by a crate
  int obstaclesCleared = 0;
  bool isMissileArmed = false;
  
  late TextComponent scoreText;
  late TextComponent shardText;
  late TextComponent gameOverText;
  
  final AudioManager audioManager = AudioManager();

  void incrementObstacleCombo() {
    obstaclesCleared++;
    if (obstaclesCleared % 3 == 0) {
      armMissile();
    }
  }

  void armMissile() {
    isMissileArmed = true;
    audioManager.playSfx('missile_unlocked.mp3', volume: 1.0);
    overlays.add('ShootButtonOverlay');
  }

  void fireMissile() {
    if (!isMissileArmed || isGameOver || isHitStop || isGamePaused) return;
    
    isMissileArmed = false;
    audioManager.playSfx('missile_fired.mp3', volume: 1.0);
    overlays.remove('ShootButtonOverlay');
    
    // Spawn the missile component slightly ahead of the train so it doesn't instantly crash
    // into an obstacle that is currently touching the train's nose.
    var missilePos = player.position.clone();
    missilePos.x += 60; // Offset by 60 pixels to the right
    rail.add(MissileComponent(position: missilePos, isTop: player.isOnTop));
  }

  void spawnQuestionCrate(Vector2 explosionPosition) {
    final crate = QuestionCrateComponent(position: explosionPosition);
    rail.add(crate);
  }

  List<Sprite> globalBlockSprites = [];
  late Sprite globalTrackSprite;
  final ValueNotifier<String?> liveBgUrlNotifier = ValueNotifier<String?>(null);
  final AudioPlayer bgmPlayer = AudioPlayer();
  String? networkBgmUrl;
  bool _hasInteracted = false;

  @override
  Color backgroundColor() => const Color(0x00000000); // Fully transparent!

  @override
  FutureOr<void> onLoad() async {
    super.onLoad();
    
    // Turn this on! It draws neon boxes around all hitboxes.
    debugMode = false;
    
    // Set the audio player to loop infinitely
    await bgmPlayer.setReleaseMode(ReleaseMode.loop);
    
    pauseEngine(); 
    
    // Initialize and preload audio files
    await audioManager.init();
    
    // Fetch Global Assets (Live Ops Season Engine)
    await _fetchGlobalAssets();
    
    // 1. Fetch the player's saved data from Supabase
    await _loadPlayerData();
    
    // NEW: Fetch the live store
    await _fetchLiveShop();
    
    // Fetch the Master Directory list right as the game boots
    await _fetchMasterDirectory();


    // The rail cuts exactly through the middle of the screen
    rail = RailComponent(
      position: Vector2(size.x / 2, size.y / 2),
      size: Vector2(size.x, 40), // 40 pixels thick
    )..anchor = Anchor.center;
    add(rail);

    // The player starts resting on top of the rail
    player = PlayerComponent(rail: rail);
    rail.add(player);

    scoreText = TextComponent(
      text: 'Score: 0',
      position: Vector2(size.x / 2, 50),
      anchor: Anchor.center,
    );
    add(scoreText);

    shardText = TextComponent(
      text: 'CELLS: 0',
      position: Vector2(size.x / 2, 80), // Slightly below score
      textRenderer: TextPaint(
        style: const TextStyle(
          color: Colors.amberAccent,
          fontSize: 14,
          fontWeight: FontWeight.bold,
          fontFamily: 'Courier',
        ),
      ),
      anchor: Anchor.center,
    );
    add(shardText);

    gameOverText = TextComponent(
      text: 'CRASHED!\nTap to Restart',
      position: Vector2(size.x / 2, size.y / 2),
      anchor: Anchor.center,
    );

    // 1. Initialize the manual timer
    _spawnTimer = 0.0;
    
    // Show the Main Menu
    overlays.add('MainMenuOverlay');
  }

  // 2. The function that creates a new obstacle or shard
  void _spawnObstacle() {
    if (isGameOver || isHitStop) return;

    bool spawnOnTop = random.nextBool(); // Randomly pick top or bottom
    
    // With rail thickness = 40 and center anchor, local y=0 is top edge.
    // Rail local center is y=20.
    // Obstacle size is 80, with center anchor.
    // Top: center Y = 20 - 20 - 40 = -40
    // Bottom: center Y = 20 + 20 + 40 = 80
    double obstacleY = spawnOnTop ? -40.0 : 80.0;
    
    // Shard size is 24, with center anchor.
    // Top: center Y = 20 - 20 - 12 = -12
    // Bottom: center Y = 20 + 20 + 12 = 52
    double shardY = spawnOnTop ? -12.0 : 52.0;

    // Roll a dice: 70% chance for an obstacle, 30% chance for a safe item path
    if (random.nextDouble() > 0.3) {
      rail.add(Obstacle(
        isTop: spawnOnTop,
        position: Vector2(size.x + 100, obstacleY),
        sprite: globalBlockSprites[random.nextInt(globalBlockSprites.length)],
      ));
      
      // If an obstacle spawns, sometimes spawn a reward shard on the opposite side 
      if (random.nextBool()) {
        double oppositeShardY = spawnOnTop ? 52.0 : -12.0;
        rail.add(DataShard(
          isTop: !spawnOnTop,
          position: Vector2(size.x + 250, oppositeShardY), // 150 pixels behind the obstacle
        ));
      }
    } else {
      // Just a clean reward path with no danger nearby
      rail.add(DataShard(
        isTop: spawnOnTop,
        position: Vector2(size.x + 100, shardY),
      ));
    }
  }

  bool isGamePaused = false;



  @override
  void update(double dt) {
    if (isGamePaused) return; // Stop all updates if paused
    
    if (dt > 0.1) {
      dt = 0.016; // Clamp massive dt spikes globally
    }
    
    super.update(dt);
    if (isGameOver || isHitStop) return; // Stop updating game logic if crashed or during crash animation
    
    // 3. Update the manual spawn timer
    _spawnTimer += dt;
    if (_spawnTimer >= 1.5) {
      _spawnTimer -= 1.5;
      _spawnObstacle();
    }
    
    // 2. Increase the speed slightly every frame to make it harder!
    gameSpeed += 5.0 * dt; 

    // Increment score based on time survived and update the text
    score += dt * 10; 
    scoreText.text = 'Score: ${score.toInt()}';
    shardText.text = 'CELLS: $shardsCollected';
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    if (isLoaded) {
      // Keep the rail correctly centered if screen resizes
      rail.position = Vector2(size.x / 2, size.y / 2);
      rail.size = Vector2(size.x, 40);
      // player is now a child of rail, so it doesn't need its absolute position updated!
    }
  }

  @override
  void onTapDown(TapDownEvent event) {
    // Block accidental screen taps if any interactive menu is open
    if (overlays.isActive('MainMenuOverlay') ||
        overlays.isActive('GameOverOverlay') ||
        overlays.isActive('QuizOverlay') ||
        overlays.isActive('LeaderboardOverlay') ||
        overlays.isActive('VibeShopOverlay')) {
      return;
    }

    if (!_hasInteracted) {
      _hasInteracted = true;
      if (networkBgmUrl != null && bgmPlayer.state != PlayerState.playing) {
        bgmPlayer.play(UrlSource(networkBgmUrl!), volume: 0.5).catchError((e) {
          print("Failed to auto-play background music on tap: $e");
        });
      }
    }

    if (isGameOver) {
      resetGame();
    } else {
      // Tapping instantly flips gravity
      player.flipGravity();
      audioManager.playSfx('Flip.wav', volume: 0.8);
      
      // FIRE THE BURST!
      player.spawnMagentaBurst();
      
      // CHECK FOR THE NEAR-MISS BONUS
      bool nearMiss = false;
      
      // Look at every obstacle currently on the screen
      for (final obstacle in rail.children.whereType<Obstacle>()) {
        // Calculate the distance from the front of the train to the obstacle
        double distance = obstacle.position.x - (player.position.x + player.size.x / 2);
        
        // If the obstacle is between 0 and 80 pixels ahead of the train, it's a Near Miss!
        if (distance > 0 && distance < 80) {
          nearMiss = true;
          break; // We found one, no need to keep checking
        }
      }

      // Reward the player if they pulled it off
      if (nearMiss) {
        score += 50; // Big point boost
        audioManager.playSfx('near_miss.wav', volume: 1.0);
        
        // Spawn the floating text right above the train
        spawnBonusText(
          "+50 GRAZE!", 
          Vector2(player.position.x, player.position.y - 60) // Slightly higher so it clears the train
        );
      }
    }
  }

  // A juicy arcade text pop-up
  void spawnBonusText(String text, Vector2 startPosition) {
    final textPaint = TextPaint(
      style: const TextStyle(
        color: Colors.amberAccent,
        fontSize: 22,
        fontWeight: FontWeight.bold,
        fontFamily: 'Courier',
        shadows: [Shadow(color: Colors.pinkAccent, blurRadius: 6)],
      ),
    );

    final textComp = TextComponent(
      text: text,
      position: startPosition.clone(),
      textRenderer: textPaint,
      anchor: Anchor.center,
    );

    add(textComp);

    // Make it float upwards for 0.6 seconds, then delete itself
    textComp.add(MoveByEffect(
      Vector2(0, -60),
      EffectController(duration: 0.6),
      onComplete: () => textComp.removeFromParent(),
    ));
  }

  Future<void> _fetchMasterDirectory() async {
    try {
      final data = await Supabase.instance.client
          .from('master_subjects')
          .select()
          .eq('is_public', true)
          .order('created_at', ascending: false);

      availableCategories.clear();
      for (var row in data) {
        availableCategories.add(QuizCategory(
          row['name'].toString(),
          row['sheet_url'].toString(),
          shareCode: row['share_code'].toString(),
          isPublic: true,
        ));
      }
    } catch (e) {
      print("Failed to load master directory: $e");
    } finally {
      isDirectoryLoaded = true;
    }
  }

  Future<void> _fetchGlobalAssets() async {
    try {
      final data = await supabase
          .from('global_config')
          .select()
          .limit(4);
      
      String? blocksStr;
      String? trackStr;
      String? bgStr;
      String? musicStr;
      
      for (var row in data) {
        if (row['config_key'] == 'active_block_url') blocksStr = row['config_value'];
        if (row['config_key'] == 'active_track_url') trackStr = row['config_value'];
        if (row['config_key'] == 'active_bg_url') bgStr = row['config_value'];
        if (row['config_key'] == 'active_bg_music_url') musicStr = row['config_value'];
      }
      
      // Helper to fetch a single sprite and fallback to local if it fails
      Future<Sprite> fetchSpriteWithFallback(String? url, String fallbackPath) async {
        if (url != null && url.trim().isNotEmpty && url.startsWith('http')) {
          try {
            final res = await http.get(Uri.parse(url.trim()));
            if (res.statusCode == 200) {
              final codec = await ui.instantiateImageCodec(res.bodyBytes);
              final frameInfo = await codec.getNextFrame();
              return Sprite(frameInfo.image);
            }
          } catch (e) {
            print("Failed to fetch $url, falling back to $fallbackPath: $e");
          }
        }
        return await loadSprite(fallbackPath);
      }

      // Fetch Blocks
      globalBlockSprites.clear();
      if (blocksStr != null && blocksStr.trim().isNotEmpty) {
        final blockUrls = blocksStr.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
        for (int i = 0; i < blockUrls.length; i++) {
          final fallbackPath = 'block${(i % 3) + 1}.png'; // default to block1, block2, block3
          globalBlockSprites.add(await fetchSpriteWithFallback(blockUrls[i], fallbackPath));
        }
      }
      // If no blocks were loaded, load defaults
      if (globalBlockSprites.isEmpty) {
        globalBlockSprites.add(await loadSprite('block1.png'));
        globalBlockSprites.add(await loadSprite('block2.png'));
        globalBlockSprites.add(await loadSprite('block3.png'));
      }

      // Fetch Track
      globalTrackSprite = await fetchSpriteWithFallback(trackStr, 'track.png');

      // Pass the Background Video URL to the UI Notifier
      if (bgStr != null && bgStr.trim().isNotEmpty && bgStr.startsWith('http')) {
        liveBgUrlNotifier.value = bgStr.trim();
      }

      // Stream the Background Music (Fire and forget, do not await!)
      if (musicStr != null && musicStr.trim().isNotEmpty && musicStr.startsWith('http')) {
        networkBgmUrl = musicStr.trim();
        bgmPlayer.play(UrlSource(networkBgmUrl!), volume: 0.5).catchError((e) {
          print("Failed to auto-play background music: $e");
        });
      }
      
      print("Global asset initialization complete.");
    } catch (e) {
      print("Critical error in _fetchGlobalAssets: $e");
      // Ultimate fallback just in case
      globalBlockSprites.clear();
      globalBlockSprites.add(await loadSprite('block1.png'));
      globalBlockSprites.add(await loadSprite('block2.png'));
      globalBlockSprites.add(await loadSprite('block3.png'));
      globalTrackSprite = await loadSprite('track.png');
    }
  }

  Future<void> _loadPlayerData() async {
    final supabase = Supabase.instance.client;
    final currentUser = supabase.auth.currentUser;
    if (currentUser == null) return;
    
    final userId = currentUser.id;
    
    try {
      // 1. Use maybeSingle() instead of single(). 
      // This returns null instead of crashing if the row doesn't exist.
      var response = await supabase
          .from('profiles')
          .select()
          .eq('id', userId)
          .maybeSingle();

      // 2. If no profile exists, create one right now!
      if (response == null) {
        print("No profile found. Forging a new one in the database...");
        
        await supabase.from('profiles').insert({
          'id': userId,
          'player_name': 'Pilot_${userId.substring(0, 4)}', // Provide a fallback name
          'coins': 0, // Explicitly set coins to 0 in case the DB default is missing
        });
        
        // Fetch it again now that we guarantee it exists
        response = await supabase
            .from('profiles')
            .select()
            .eq('id', userId)
            .single();
      }

      // 3. Load the data into the game
      bankBalance = response['coins'] as int;
      // Aggressively strip any stray quotes from manual DB entries
      activeSkin = (response['active_skin'] as String).replaceAll("'", "").replaceAll('"', '');
      // Convert the dynamic array back into a List of Strings
      unlockedSkins = List<String>.from(response['unlocked_skins']); 
      
      print("Loaded Profile: $bankBalance Coins | Skin: $activeSkin");
      
    } catch (e) {
      print("CRITICAL ERROR loading profile: $e");
      
      // 4. Ultimate Fallback: Don't let the game crash, just give them default stats
      bankBalance = 0;
      activeSkin = 'default_train';
      unlockedSkins = ['default_train'];
    }
  }

  Future<void> _fetchLiveShop() async {
    try {
      final data = await Supabase.instance.client
          .from('shop_items')
          .select()
          .order('price', ascending: true);
          
      liveShopInventory = List<Map<String, dynamic>>.from(data);
      print("Loaded ${liveShopInventory.length} items into the shop!");
    } catch (e) {
      print("Error loading shop data: $e");
    }
  }

  Future<void> bankCoins() async {
    if (shardsCollected > 0) {
      bankBalance += shardsCollected; // Update local state
      
      final currentUser = Supabase.instance.client.auth.currentUser;
      if (currentUser != null) {
        final userId = currentUser.id;
        try {
          await Supabase.instance.client
              .from('profiles')
              .update({'coins': bankBalance})
              .eq('id', userId);
              
          print("Deposited $shardsCollected coins. New Balance: $bankBalance");
        } catch (e) {
          print("Failed to save coins to cloud: $e");
        }
      }
      
      shardsCollected = 0; // Reset run coins for the next game
    }
  }

  // 3. Fetch the Specific Subject WHEN CLICKED
  Future<void> loadSubjectAndStart(QuizCategory category, {String? loginId, String? password}) async {
    isDownloading = true;
    activeCategory = category;
    overlays.remove('MainMenuOverlay'); // Refresh UI to show loader
    overlays.add('MainMenuOverlay');
    
    activeQuestions.clear(); // Clear out any previous game's questions

    try {
      // Get the secure URL from Supabase using the RPC
      // If it's a "Play for Fun" or legacy without a shareCode, we skip RPC and try direct fetch
      String fetchUrl = category.csvUrl;
      
      if (category.shareCode.isNotEmpty) {
        final responseData = await supabase.rpc('get_secure_sheet_url', params: {
          'target_share_code': category.shareCode,
          'provided_id': loginId,
          'provided_password': password,
        });
        fetchUrl = responseData.toString();
      }

      // Auto-correct standard Google Sheets links to CSV export links
      if (fetchUrl.contains('/edit') || fetchUrl.contains('/view')) {
        fetchUrl = fetchUrl.replaceAll(RegExp(r'/(edit|view).*'), '/export?format=csv');
      }

      final response = await http.get(Uri.parse(fetchUrl));
      if (response.statusCode == 200) {
        // Force UTF-8 decoding so Devanagari and other non-ASCII characters load properly
        final decodedBody = utf8.decode(response.bodyBytes);
        List<List<dynamic>> csvData = csv.decode(decodedBody);
        
        for (var i = 1; i < csvData.length; i++) {
          var row = csvData[i];
          if (row.length >= 2 && row[0].toString().trim().isNotEmpty) {
            String questionText = row[0].toString();
            String correctAnswer = row[1].toString();
            
            List<String> options = [correctAnswer];
            for (int j = 2; j < row.length; j++) {
              String wrongAnswer = row[j].toString().trim();
              if (wrongAnswer.isNotEmpty) options.add(wrongAnswer);
            }
            activeQuestions.add(QuizQuestion(questionText, correctAnswer, options));
          }
        }
      } else {
         throw Exception('Failed to load Google Sheet data. HTTP ${response.statusCode}');
      }
    } catch (e) {
      print("Failed to load questions: $e");
      // Handle the error by showing an alert or resetting
      isDownloading = false;
      overlays.remove('MainMenuOverlay');
      overlays.add('MainMenuOverlay');
      return; // Stop the flow
    }

    // Fetch Top 5 for HUD before starting
    final data = await fetchLeaderboard(category.name);
    currentTop5 = data.take(5).toList();

    isDownloading = false;
    overlays.remove('MainMenuOverlay');
    overlays.add('PauseButtonOverlay');
    
    // Start game and show the HUD
    overlays.add('InGameHUD');
    
    // Start background music loop (Prioritize Network BGM if available)
    if (networkBgmUrl != null) {
      if (bgmPlayer.state != PlayerState.playing) {
        bgmPlayer.play(UrlSource(networkBgmUrl!), volume: 0.5).catchError((e) {
          print("Failed to play network bgm: $e");
        });
      }
    } else {
      audioManager.playBgm(audioManager.currentBgmTrack, volume: 0.5);
    }
    
    resetGame();
    resumeEngine(); 
  }

  // Start Play for Fun mode (No Trivia)
  Future<void> startPlayForFun() async {
    isDownloading = true;
    overlays.remove('MainMenuOverlay');
    overlays.add('MainMenuOverlay'); // refresh UI

    activeCategory = QuizCategory("Play for Fun", "");
    
    final data = await fetchLeaderboard("Play for Fun");
    currentTop5 = data.take(5).toList();

    isPlayForFun = true;
    isDownloading = false;
    overlays.remove('MainMenuOverlay');
    overlays.add('PauseButtonOverlay');
    overlays.add('InGameHUD');
    
    // Start background music loop (Prioritize Network BGM if available)
    if (networkBgmUrl != null) {
      if (bgmPlayer.state != PlayerState.playing) {
        bgmPlayer.play(UrlSource(networkBgmUrl!), volume: 0.5).catchError((e) {
          print("Failed to play network bgm: $e");
        });
      }
    } else {
      audioManager.playBgm(audioManager.currentBgmTrack, volume: 0.5);
    }
    
    resetGame();
    resumeEngine();
  }

  // Return to the Main Menu
  void returnToMainMenu() {
    isGameOver = true;
    isPlayForFun = false;
    activeQuestions.clear();
    
    // Stop BGM when returning to menu
    audioManager.stopBgm();
    
    rail.children.whereType<Obstacle>().forEach((obstacle) {
      obstacle.removeFromParent();
    });
    rail.children.whereType<DataShard>().forEach((shard) {
      shard.removeFromParent();
    });
    rail.children.whereType<ParticleSystemComponent>().forEach((p) {
      p.removeFromParent();
    });
    rail.children.whereType<MissileComponent>().forEach((m) {
      m.removeFromParent();
    });
    
    if (gameOverText.isMounted) gameOverText.removeFromParent();
    
    overlays.remove('BackButtonOverlay');
    overlays.remove('PauseButtonOverlay');
    overlays.remove('QuizOverlay');
    overlays.remove('InGameHUD');
    
    player.paint.color = player.paint.color.withOpacity(1);

    overlays.add('MainMenuOverlay');
    pauseEngine();
  }

  // 4. Hit-Stop and Crash Sequence
  void triggerCrashSequence(Obstacle obstacle) {
    if (isHitStop) return;
    isHitStop = true;
    
    // Destroy any stray missiles that were fired exactly on the crash frame
    rail.children.whereType<MissileComponent>().forEach((m) {
      m.removeFromParent();
    });
    
    isTriviaFromPowerup = false;
    obstaclesCleared = 0;
    isMissileArmed = false;
    overlays.remove('ShootButtonOverlay');
    overlays.remove('PauseButtonOverlay');
    
    // Save speed and stop the treadmill immediately!
    preCrashSpeed = gameSpeed;
    gameSpeed = 0; 
    
    // Build the Camera Shake Effect
    final shakeEffect = SequenceEffect(
      [
        MoveByEffect(Vector2(8, 8), EffectController(duration: 0.05)),
        MoveByEffect(Vector2(-16, -16), EffectController(duration: 0.05)),
        MoveByEffect(Vector2(8, 16), EffectController(duration: 0.05)),
        MoveByEffect(Vector2(-16, -8), EffectController(duration: 0.05)),
        MoveByEffect(Vector2(16, 0), EffectController(duration: 0.05)),
      ],
      onComplete: () {
        isHitStop = false;
        overlays.remove('InGameHUD'); // Hide HUD during crash UI
        
        // Resolve the crash: Quiz or Game Over
        if (isPlayForFun) {
          gameOver(); 
        } else {
          collidedObstacle = obstacle;
          if (activeQuestions.isNotEmpty) {
            currentQuestion = activeQuestions[random.nextInt(activeQuestions.length)];
          } else {
            currentQuestion = QuizQuestion("Error", "No Database", ["No Database"]);
          }
          isGamePaused = true; 
          bgmPlayer.setVolume(0.1); // Duck the background music volume
          overlays.add('QuizOverlay'); 
        }
      },
    );

    // Apply the shake to the player and the rail!
    // Since the game components are added to the root instead of a Camera World, shaking the camera does nothing.
    player.add(shakeEffect);
    rail.add(SequenceEffect([
        MoveByEffect(Vector2(8, 8), EffectController(duration: 0.05)),
        MoveByEffect(Vector2(-16, -16), EffectController(duration: 0.05)),
        MoveByEffect(Vector2(8, 16), EffectController(duration: 0.05)),
        MoveByEffect(Vector2(-16, -8), EffectController(duration: 0.05)),
        MoveByEffect(Vector2(16, 0), EffectController(duration: 0.05)),
    ]));
  }

  // 2. What happens if they click the right answer
  void answerCorrectly() {
    bgmPlayer.setVolume(0.5); // Restore music volume
    overlays.remove('QuizOverlay'); // Hide the popup
    overlays.add('InGameHUD'); // Restore the HUD
    score *= 2; // DOUBLE THE SCORE!
    // Restore the dynamic speed
    gameSpeed = preCrashSpeed;
    
    // Destroy the block so the train can pass safely
    collidedObstacle?.removeFromParent(); 
    collidedObstacle = null;
    
    isGamePaused = false; // Unfreeze the game
  }

  // 3. What happens if they click the wrong answer
  void answerIncorrectly() {
    bgmPlayer.setVolume(0.5); // Restore music volume
    overlays.remove('QuizOverlay'); // Hide the popup
    
    if (isTriviaFromPowerup) {
      overlays.add('InGameHUD'); // Restore the HUD
      overlays.add('PauseButtonOverlay');
      gameSpeed = preCrashSpeed; // Restore speed
      // Do not multiply score, just resume
      isGamePaused = false; 
    } else {
      isGamePaused = false; // Unpause so particles can animate
      gameOver(); // Trigger your existing Game Over logic
    }
  }
  
  void pauseGame() {
    if (isGameOver || isHitStop || isGamePaused) return;
    isGamePaused = true;
    overlays.add('PauseMenuOverlay');
    overlays.remove('InGameHUD');
    overlays.remove('ShootButtonOverlay');
    overlays.remove('PauseButtonOverlay');
  }

  void resumeGame() {
    isGamePaused = false;
    overlays.remove('PauseMenuOverlay');
    overlays.add('InGameHUD');
    overlays.add('PauseButtonOverlay');
    if (isMissileArmed) {
      overlays.add('ShootButtonOverlay');
    }
  }

  void gameOver() {
    isGameOver = true;
    
    // Stop BGM and trigger crash sounds
    audioManager.stopBgm();
    audioManager.playRandomCrash();
    audioManager.playSfx('game_over.wav', volume: 1.0);
    
    bankCoins(); // Save the run's loot to the cloud
    overlays.add('GameOverOverlay'); // Show the new cyberpunk menu
    
    // Hide player
    player.paint.color = player.paint.color.withOpacity(0);
    
    // Spawn explosion
    rail.add(
      ParticleSystemComponent(
        position: player.position,
        particle: Particle.generate(
          count: 50,
          lifespan: 1.5,
          generator: (i) {
            return AcceleratedParticle(
              acceleration: Vector2(0, 400),
              speed: Vector2((random.nextDouble() - 0.5) * 800, (random.nextDouble() - 0.5) * 800),
              position: Vector2.zero(),
              child: CircleParticle(
                radius: random.nextDouble() * 5 + 2,
                paint: Paint()..color = Colors.orangeAccent,
              ),
            );
          },
        ),
      ),
    );
  }

  void resetGame() {
    isGameOver = false;
    score = 0;
    shardsCollected = 0;
    gameSpeed = 300.0;
    
    // Reset the camera exactly back to the center
    camera.viewfinder.position = Vector2.zero();
    
    // Restart manual timer
    _spawnTimer = 0.0;
    
    player.paint.color = player.paint.color.withOpacity(1);
    
    // Remove the Game Over text and menu
    if (gameOverText.isMounted) gameOverText.removeFromParent();
    overlays.remove('GameOverOverlay');
    
    // Find all existing red blocks and shards and destroy them so the track is clear
    rail.children.whereType<Obstacle>().forEach((obstacle) {
      obstacle.removeFromParent();
    });
    rail.children.whereType<DataShard>().forEach((shard) {
      shard.removeFromParent();
    });
    rail.children.whereType<ParticleSystemComponent>().forEach((p) {
      p.removeFromParent();
    });
    rail.children.whereType<MissileComponent>().forEach((m) {
      m.removeFromParent();
    });

    resumeEngine(); // Unfreeze the game
  }

  // 1. Function to SAVE a score to the database and update profile name
  Future<void> submitScore(String playerName) async {
    // We get the category from the active subject
    String currentCategory = activeCategory?.name ?? "General";
    
    try {
      // 1. Save the score to the leaderboard
      await supabase.from('leaderboards').insert({
        'category': currentCategory,
        'player_name': playerName,
        'score': score.toInt(), // Make sure score is an integer
      });
      
      // 2. Update their permanent profile with this new name
      final currentUser = supabase.auth.currentUser;
      if (currentUser != null) {
        await supabase.from('profiles').update({
          'player_name': playerName
        }).eq('id', currentUser.id);
      }
      
      print("Score and profile name successfully updated in Supabase!");
    } catch (e) {
      print("Error uploading score: $e");
    }
  }

  // 2. Function to FETCH the top 10 scores for a specific category
  Future<List<Map<String, dynamic>>> fetchLeaderboard(String category) async {
    try {
      final data = await supabase
          .from('leaderboards')
          .select('player_name, score')
          .eq('category', category) // Only get scores for this subject
          .order('score', ascending: false) // Highest score first
          .limit(10); // Only grab the Top 10
          
      return data;
    } catch (e) {
      print("Error fetching leaderboard: $e");
      return [];
    }
  }
}

class RailComponent extends SpriteComponent with HasGameRef<MaglevFlipGame> {
  RailComponent({required Vector2 position, required Vector2 size}) 
      : super(position: position, size: size, anchor: Anchor.center);

  @override
  FutureOr<void> onLoad() async {
    super.onLoad();
    sprite = gameRef.globalTrackSprite;
  }
}

class PlayerComponent extends SpriteComponent with CollisionCallbacks, HasGameRef<MaglevFlipGame> {
  final RailComponent rail;
  bool isOnTop = true;
  
  static final Vector2 playerSize = Vector2(160, 80);

  final Random _random = Random();
  double _trailTimer = 0; // Keeps track of when to spit out a new spark

  PlayerComponent({required this.rail}) : super(size: playerSize, anchor: Anchor.center);

  @override
  FutureOr<void> onLoad() async {
    super.onLoad();
    // Start with the user's active skin from Supabase
    await applySkin(gameRef.activeSkin);
    // Add hitbox for future collision detection
    add(RectangleHitbox(collisionType: CollisionType.active));
    updatePosition();
  }

  Future<void> applySkin(String skinId) async {
    // 1. Strip any stray quotes just to be completely safe
    skinId = skinId.replaceAll("'", "").replaceAll('"', '');

    if (skinId == 'default_train' || gameRef.liveShopInventory.isEmpty) {
      sprite = await gameRef.loadSprite('train.png'); // Using train.png as the default
      return;
    }

    // 2. Find the URL from our live shop inventory
    String? targetUrl;
    for (var item in gameRef.liveShopInventory) {
      if (item['id'] == skinId) {
        targetUrl = item['image_url'];
        break;
      }
    }

    if (targetUrl == null) {
      print("Skin URL not found, using default.");
      sprite = await gameRef.loadSprite('train.png');
      return;
    }

    // 3. Download the image and convert it to a Flame Sprite using Flutter's robust native pipeline
    try {
      final ImageProvider provider = NetworkImage(targetUrl);
      final ImageStream stream = provider.resolve(ImageConfiguration.empty);
      final Completer<ui.Image> completer = Completer();
      
      ImageStreamListener? listener;
      listener = ImageStreamListener((ImageInfo info, bool synchronousCall) {
        if (!completer.isCompleted) completer.complete(info.image);
        stream.removeListener(listener!);
      }, onError: (dynamic exception, StackTrace? stackTrace) {
        if (!completer.isCompleted) completer.completeError(exception);
        stream.removeListener(listener!);
      });
      
      stream.addListener(listener);
      
      final ui.Image image = await completer.future;
      sprite = Sprite(image);
      
    } catch (e) {
      print("Network image failed to load: $e");
      sprite = await gameRef.loadSprite('train.png');
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (gameRef.isGameOver || gameRef.isHitStop) return; 
    
    // Generate the continuous Cyan Engine Trail
    _trailTimer += dt;
    if (_trailTimer > 0.1) { // Changed from 0.03 to 0.1 to prevent component tree spam lag
      _trailTimer = 0;
      _spawnCyanTrail();
    }
  }

  // The Engine Exhaust Spark Generator
  void _spawnCyanTrail() {
    gameRef.rail.add(
      ParticleSystemComponent(
        // Spawn at the back of the train (since anchor is center, back is position.x - size.x/2)
        position: Vector2(position.x - size.x / 2 + 10, position.y),
        particle: Particle.generate(
          count: 2, // Spawn 2 tiny sparks per tick
          lifespan: 0.4, // They live for less than half a second
          generator: (i) => AcceleratedParticle(
            // Shoot them slightly backwards and randomly up/down
            speed: Vector2(-(_random.nextDouble() * 150), _random.nextDouble() * 40 - 20),
            child: ComputedParticle(
              renderer: (canvas, particle) {
                // Fade out as they die
                final paint = Paint()
                  ..color = Colors.cyanAccent.withOpacity(1 - particle.progress);
                // Shrink as they die
                canvas.drawCircle(Offset.zero, 3 * (1 - particle.progress), paint);
              },
            ),
          ),
        ),
      ),
    );
  }

  // The Magenta Gravity Burst Generator
  void spawnMagentaBurst() {
    gameRef.rail.add(
      ParticleSystemComponent(
        // Spawn right in the dead center of the train
        position: position,
        particle: Particle.generate(
          count: 15, // A big explosion of 15 particles
          lifespan: 0.3, 
          generator: (i) {
            // Calculate a random circular direction (360 degrees)
            double angle = _random.nextDouble() * 2 * pi;
            double speed = _random.nextDouble() * 250 + 100; // Fast explosion
            
            return AcceleratedParticle(
              speed: Vector2(cos(angle) * speed, sin(angle) * speed),
              child: ComputedParticle(
                renderer: (canvas, particle) {
                  final paint = Paint()
                    ..color = Colors.pinkAccent.withOpacity(1 - particle.progress);
                  canvas.drawCircle(Offset.zero, 4 * (1 - particle.progress), paint);
                },
              ),
            );
          },
        ),
      ),
    );
  }

  void updatePosition() {
    // Moved further right so it's fully visible (half-width is 80, so 150 leaves 70px gap)
    const xPos = 150.0;
    
    // Rail local Y center is 20
    if (isOnTop) {
      position = Vector2(xPos, -40.0);
      if (isFlippedVertically) {
        flipVertically();
      }
    } else {
      position = Vector2(xPos, 80.0);
      if (!isFlippedVertically) {
        flipVertically();
      }
    }
  }

  void flipGravity() {
    isOnTop = !isOnTop;
    updatePosition();
  }

  // 2. This function fires the exact moment the train hits a red block
  @override
  void onCollisionStart(Set<Vector2> intersectionPoints, PositionComponent other) {
    super.onCollisionStart(intersectionPoints, other);
    
    // If the object was already destroyed this exact frame (e.g., by a missile), ignore it!
    if (other.isRemoving) return;
    
    if (other is Obstacle) {
      // Defer the crash to the end of the frame! 
      // If a missile destroys this block in the EXACT same collision frame, 
      // the block will be marked as 'isRemoving', and we cancel the crash!
      Future.microtask(() {
        if (!other.isRemoving) {
          gameRef.triggerCrashSequence(other);
        }
      });
    } else if (other is DataShard) {
      // 1. Reward the player
      gameRef.score += 10;
      gameRef.shardsCollected += 1;
      
      // Play collection sound
      gameRef.audioManager.playSfx('coin_collector.wav', volume: 1.0);
      
      // 2. Spawn a glowing pop-up effect text
      gameRef.spawnBonusText("+10 CELL", other.position);
      
      // 3. Remove the shard from the game world cleanly
      other.removeFromParent();
    } else if (other is QuestionCrateComponent) {
      // If we are currently crashing, do not let crates interrupt the crash sequence!
      // This prevents multiple overlapping quizzes if the train hits a crate while shaking.
      if (gameRef.isHitStop || gameRef.isGamePaused) return;

      other.removeFromParent();
      
      if (!gameRef.isPlayForFun) {
        final random = Random();
        if (gameRef.activeQuestions.isNotEmpty) {
          gameRef.currentQuestion = gameRef.activeQuestions[random.nextInt(gameRef.activeQuestions.length)];
        } else {
          gameRef.currentQuestion = QuizQuestion("Error", "No Database", ["No Database"]);
        }
        
        gameRef.isTriviaFromPowerup = true;
        gameRef.preCrashSpeed = gameRef.gameSpeed;
        gameRef.isGamePaused = true;
        gameRef.bgmPlayer.setVolume(0.1); // Duck the background music volume
        gameRef.overlays.add('QuizOverlay');
        gameRef.overlays.remove('PauseButtonOverlay');
        gameRef.audioManager.playSfx('coin_collector.wav', volume: 1.0);
      } else {
        gameRef.score += 50;
        gameRef.audioManager.playSfx('coin_collector.wav', volume: 1.0);
        gameRef.spawnBonusText("+50", other.position);
      }
    }
  }
}

class DataShard extends PositionComponent with CollisionCallbacks, HasGameRef<MaglevFlipGame> {
  final bool isTop;
  double _animationTime = 0;

  DataShard({required this.isTop, required Vector2 position})
      : super(position: position, size: Vector2(24, 24), anchor: Anchor.center);

  final Paint _paint = Paint()
    ..color = Colors.amberAccent
    ..style = PaintingStyle.fill;
    
  late Path _path;

  @override
  Future<void> onLoad() async {
    // Cache the path drawing so we don't recalculate it 60 times a second
    _path = Path()
      ..moveTo(size.x / 2, 0)
      ..lineTo(size.x, size.y / 2)
      ..lineTo(size.x / 2, size.y)
      ..lineTo(0, size.y / 2)
      ..close();
      
    // Add a circular hitbox for clean item collection
    add(CircleHitbox(collisionType: CollisionType.passive));
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    // Draw the cached path
    canvas.drawPath(_path, _paint);
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (gameRef.isGameOver || gameRef.isHitStop) return; 
    
    // Move left matching the game treadmill speed
    position.x -= gameRef.gameSpeed * dt;

    // Add a subtle floating hover animation up and down
    _animationTime += dt * 5;
    position.y += sin(_animationTime) * 0.2;

    // Memory Management: Delete if it leaves the screen uncollected
    if (position.x < -size.x) {
      removeFromParent();
    }
  }
}

class Obstacle extends SpriteComponent with HasGameRef<MaglevFlipGame>, CollisionCallbacks {
  final bool isTop;

  Obstacle({required this.isTop, required Vector2 position, required Sprite sprite})
      : super(position: position, size: Vector2(80, 80), sprite: sprite, anchor: Anchor.center);

  @override
  FutureOr<void> onLoad() async {
    super.onLoad();
    
    if (isTop) {
      flipVertically();
    }
    
    // Add hitbox for collision detection in Stage 3
    add(RectangleHitbox(collisionType: CollisionType.passive));
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (gameRef.isGameOver || gameRef.isHitStop) return; // Freeze obstacle

    // 2. Use the dynamic speed from the main game class
    position.x -= gameRef.gameSpeed * dt;

    // Memory Management: Delete the block once it leaves the left side of the screen
    if (position.x < -size.x) {
      removeFromParent();
      gameRef.incrementObstacleCombo();
    }
  }
}

class MissileComponent extends SpriteComponent with HasGameRef<MaglevFlipGame>, CollisionCallbacks {
  final double speed = 800.0;
  final bool isTop;

  MissileComponent({required Vector2 position, required this.isTop}) : super(position: position) {
    size = Vector2(80, 40); 
    anchor = Anchor.center;
  }

  @override
  Future<void> onLoad() async {
    super.onLoad();
    sprite = await gameRef.loadSprite('missile.png');
    
    if (!isTop) {
      flipVertically();
    }
    
    add(RectangleHitbox(collisionType: CollisionType.active));
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (gameRef.isGameOver || gameRef.isHitStop) {
      removeFromParent(); // Self-destruct if the game is crashing
      return;
    }
    
    position.x += speed * dt;

    if (position.x > gameRef.size.x) {
      removeFromParent();
    }
  }

  @override
  void onCollisionStart(Set<Vector2> intersectionPoints, PositionComponent other) {
    super.onCollisionStart(intersectionPoints, other);

    if (isRemoving || gameRef.isGameOver || gameRef.isHitStop) return;

    if (other is Obstacle) {
      removeFromParent();
      other.removeFromParent();
      
      gameRef.audioManager.playRandomCrash(); 
      gameRef.spawnQuestionCrate(other.position.clone());
    }
  }
}

class QuestionCrateComponent extends SpriteComponent with HasGameRef<MaglevFlipGame>, CollisionCallbacks {
  double _animationTime = 0;

  QuestionCrateComponent({required Vector2 position}) : super(position: position) {
    size = Vector2(80, 80); 
    anchor = Anchor.center;
  }

  @override
  Future<void> onLoad() async {
    super.onLoad();
    sprite = await gameRef.loadSprite('crate.png');
    
    add(RectangleHitbox(collisionType: CollisionType.passive));
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (gameRef.isGameOver || gameRef.isHitStop) return;
    
    position.x -= gameRef.gameSpeed * dt;

    _animationTime += dt * 5;
    position.y += sin(_animationTime) * 0.3;

    if (position.x < -size.x) {
      removeFromParent();
    }
  }
}
