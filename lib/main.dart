import 'dart:math';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flame/game.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'maglev_flip_game.dart';
import 'audio_manager.dart';
import 'ui/widgets/video_background.dart';
import 'ad_banner.dart';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Google Mobile Ads ONLY on Native, AdSense handles Web natively via index.html
  if (!kIsWeb) {
    await MobileAds.instance.initialize();
  }

  await Supabase.initialize(
    url: 'https://hteolkfbjmouicmyuxqv.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imh0ZW9sa2Ziam1vdWljbXl1eHF2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODExOTQ4OTgsImV4cCI6MjA5Njc3MDg5OH0.-EfrXpGR4v7svfu8-a8e97-U3roS7P42uqJ5P1NFtYI',
  );

  final supabase = Supabase.instance.client;

  // Silently log the player in or restore their existing session
  var session = supabase.auth.currentSession;
  if (session == null) {
    try {
      await supabase.auth.signInAnonymously();
    } catch (e) {
      print('Anonymous Auth Error: $e');
    }
  }

  // Ensure they have a row in the 'profiles' table
  if (supabase.auth.currentUser != null) {
    final userId = supabase.auth.currentUser!.id;
    try {
      // Attempt to insert a default profile. If it already exists, it will just fail safely.
      await supabase.from('profiles').insert({
        'id': userId,
        'player_name': 'Pilot_${userId.substring(0, 4)}',
        'coins': 0,
      });
    } catch (e) {
      // Profile already exists, which is perfect.
    }
  }

  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Maglev Flip',
      home: const MaglevFlipScreen(),
    ),
  );
}



class MaglevFlipScreen extends StatefulWidget {
  const MaglevFlipScreen({super.key});

  @override
  State<MaglevFlipScreen> createState() => _MaglevFlipScreenState();
}

class _MaglevFlipScreenState extends State<MaglevFlipScreen> {
  late final MaglevFlipGame _game;

  @override
  void initState() {
    super.initState();
    _game = MaglevFlipGame();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. Reactive Bottom Layer: The Looping Video or Gradient Fallback
          ValueListenableBuilder<String?>(
            valueListenable: _game.liveBgUrlNotifier,
            builder: (context, videoUrl, child) {
              if (videoUrl == null) {
                return Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF0F2027), Color(0xFF203A43)],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                );
              }
              return VideoBackground(videoUrl: videoUrl);
            },
          ),

          // 2. Top Layer: The Transparent Flame Game
          GameWidget<MaglevFlipGame>(
            game: _game,
            overlayBuilderMap: {
              'MainMenuOverlay': (BuildContext context, MaglevFlipGame game) {
                return MainMenu(game: game);
              },
              'QuizOverlay': (BuildContext context, MaglevFlipGame game) {
                return QuizMenu(game: game);
              },
              'GameOverOverlay': (BuildContext context, MaglevFlipGame game) {
                return GameOverMenu(game: game);
              },
              'LeaderboardOverlay': (BuildContext context, MaglevFlipGame game) {
                return LeaderboardMenu(game: game);
              },
              'InGameHUD': (BuildContext context, MaglevFlipGame game) {
                return InGameHUD(game: game);
              },
              'VibeShopOverlay': (BuildContext context, MaglevFlipGame game) {
                return VibeShopMenu(game: game);
              },
              'SoundSettingsOverlay': (BuildContext context, MaglevFlipGame game) {
                return SoundSettingsMenu(game: game);
              },
              'CreateSubjectOverlay': (BuildContext context, MaglevFlipGame game) {
                return CreateSubjectMenu(game: game);
              },
              'ShootButtonOverlay': (BuildContext context, MaglevFlipGame game) {
                return ShootButtonOverlay(game: game);
              },
              'PauseButtonOverlay': (BuildContext context, MaglevFlipGame game) {
                return PauseButtonOverlay(game: game);
              },
              'PauseMenuOverlay': (BuildContext context, MaglevFlipGame game) {
                return PauseMenuOverlay(game: game);
              },
            },
          ),
        ],
      ),
    );
  }
}

class QuizMenu extends StatefulWidget {
  final MaglevFlipGame game;
  const QuizMenu({super.key, required this.game});

  @override
  State<QuizMenu> createState() => _QuizMenuState();
}

class _QuizMenuState extends State<QuizMenu> {
  late List<String> shuffledOptions;
  String? selectedOption;
  bool isProcessing = false;

  @override
  void initState() {
    super.initState();
    // Grab the options and shuffle them ONCE when the menu opens
    // This prevents the buttons from changing order if the screen resizes
    final question = widget.game.currentQuestion!;
    shuffledOptions = List.from(question.allOptions)..shuffle();
  }

  Color? _getButtonColor(String option, bool isCorrect) {
    if (!isProcessing) return Colors.blueGrey[900];
    if (isCorrect) return Colors.green[800]; // Highlight correct answer always!
    if (selectedOption == option && !isCorrect) return Colors.red[800]; // Highlight wrong choice
    return Colors.blueGrey[900]; // Default
  }

  Color _getBorderColor(String option, bool isCorrect) {
    if (!isProcessing) return Colors.cyan;
    if (isCorrect) return Colors.greenAccent;
    if (selectedOption == option && !isCorrect) return Colors.redAccent;
    return Colors.cyan;
  }

  @override
  Widget build(BuildContext context) {
    final question = widget.game.currentQuestion!;

    return Center(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: Colors.cyan, width: 2),
        ),
        width: 320,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
            Text(
              widget.game.isTriviaFromPowerup ? "POWER-UP TRIVIA" : "SYSTEM FAILURE IMMINENT!",
              style: TextStyle(
                color: widget.game.isTriviaFromPowerup ? Colors.cyan[300] : Colors.red, 
                fontSize: 18, 
                fontWeight: FontWeight.bold,
                letterSpacing: widget.game.isTriviaFromPowerup ? 2 : 0,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 15),
            Text(
              question.text,
              style: const TextStyle(color: Colors.white, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            
            // dynamically generate a button for EVERY option in our shuffled list
            ...shuffledOptions.map((option) {
              bool isCorrect = option == question.correctAnswer;
              
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: ElevatedButton(
                  onPressed: () async {
                    if (isProcessing) return; // Prevent double taps without visually disabling the button
                    
                    setState(() {
                      selectedOption = option;
                      isProcessing = true;
                    });
                    
                    // Audio Feedback!
                    if (isCorrect) {
                      AudioManager().playSfx('correct.mp3');
                    } else {
                      AudioManager().playRandomCrash();
                    }
                    
                    // Wait for 1.2 seconds to show the colors
                    await Future.delayed(const Duration(milliseconds: 1200));
                    
                    if (!mounted) return; // safety check
                    
                    if (isCorrect) {
                      widget.game.answerCorrectly();
                    } else {
                      widget.game.answerIncorrectly();
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _getButtonColor(option, isCorrect), 
                    minimumSize: const Size(double.infinity, 45),
                    side: BorderSide(color: _getBorderColor(option, isCorrect), width: 1),
                  ),
                  child: Text(
                    option, 
                    style: const TextStyle(color: Colors.white), 
                    textAlign: TextAlign.center
                  ),
                ),
              );
            }).toList(),
            
          ],
        ),
        ),
      ),
    );
  }
}

class MainMenu extends StatefulWidget {
  final MaglevFlipGame game;
  const MainMenu({super.key, required this.game});

  @override
  State<MainMenu> createState() => _MainMenuState();
}

class _MainMenuState extends State<MainMenu> {
  String searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _searchByShareCode(String code) async {
    setState(() {
      widget.game.isDownloading = true;
    });

    try {
      // Use the secure RPC to bypass RLS without exposing passwords or URLs
      final responseList = await Supabase.instance.client
          .rpc('lookup_subject', params: {'p_share_code': code.trim()});

      setState(() {
        widget.game.isDownloading = false;
      });

      if (responseList != null && (responseList as List).isNotEmpty) {
        final data = responseList[0];
        bool isPublic = data['is_public'];
        String name = data['name'];
        
        // We leave the URL blank here because the engine fetches the secure URL via get_secure_sheet_url later!
        QuizCategory category = QuizCategory(name, '', shareCode: code.trim(), isPublic: isPublic);

        if (isPublic) {
          widget.game.loadSubjectAndStart(category);
        } else {
          _showLoginDialog(category);
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Subject not found!')));
        }
      }
    } catch (e) {
      setState(() {
        widget.game.isDownloading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  void _showLoginDialog(QuizCategory category) {
    String loginId = '';
    String password = '';
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.black87,
          title: const Text("PRIVATE SUBJECT", style: TextStyle(color: Colors.cyan)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(labelText: "Login ID", labelStyle: TextStyle(color: Colors.cyan)),
                onChanged: (val) => loginId = val,
              ),
              TextField(
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(labelText: "Password", labelStyle: TextStyle(color: Colors.cyan)),
                obscureText: true,
                onChanged: (val) => password = val,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("CANCEL", style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.pinkAccent),
              onPressed: () {
                Navigator.pop(context);
                widget.game.loadSubjectAndStart(category, loginId: loginId, password: password);
              },
              child: const Text("LOGIN", style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      }
    );
  }

  @override
  Widget build(BuildContext context) {
    // Filter the categories based on the search query
    var filteredCategories = widget.game.availableCategories.where((category) {
      return category.name.toLowerCase().contains(searchQuery.toLowerCase());
    }).toList();
    
    // UX FIX: If there are 100+ subjects, don't show all of them at once! 
    // Only show the top 5 newest ones. The user can use the search bar to find the rest.
    bool showingLimited = false;
    if (searchQuery.isEmpty && filteredCategories.length > 5) {
      filteredCategories = filteredCategories.take(5).toList();
      showingLimited = true;
    }

    return Center(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: Colors.cyan, width: 2),
        ),
        width: 320,
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "SELECT DATABASE",
                style: TextStyle(color: Colors.cyan, fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: 2),
              ),
              const SizedBox(height: 20),
              
              // NEW: The pure Arcade Mode button
              ElevatedButton(
                onPressed: () => widget.game.startPlayForFun(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.pinkAccent.withOpacity(0.2), // Distinct color
                  side: const BorderSide(color: Colors.pinkAccent, width: 2),
                  minimumSize: const Size(double.infinity, 50),
                ),
                child: const Text("PLAY FOR FUN (PURE ARCADE)", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
              
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Text("--- OR STUDY ---", style: TextStyle(color: Colors.white54, fontSize: 12)),
              ),
              
              // Check if we are currently downloading a specific subject
              if (widget.game.isDownloading) ...[
                const CircularProgressIndicator(color: Colors.cyan),
                const SizedBox(height: 15),
                const Text("Connecting to Server...", style: TextStyle(color: Colors.white)),
              ] 
              // Check if the master directory is still loading
              else if (!widget.game.isDirectoryLoaded) ...[
                const CircularProgressIndicator(color: Colors.cyan),
              ] 
              // Show the dynamic buttons
              else ...[
                // Search Bar
                TextField(
                  controller: _searchController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Search subjects...',
                    hintStyle: const TextStyle(color: Colors.white54),
                    prefixIcon: const Icon(Icons.search, color: Colors.cyan),
                    enabledBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: Colors.cyan),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: Colors.cyan, width: 2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.arrow_forward, color: Colors.cyan),
                      onPressed: () async {
                        if (_searchController.text.isNotEmpty) {
                          await _searchByShareCode(_searchController.text);
                        }
                      },
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 10),
                  ),
                  onChanged: (value) {
                    setState(() {
                      searchQuery = value;
                    });
                  },
                  onSubmitted: (value) async {
                    if (value.isNotEmpty) {
                      await _searchByShareCode(value);
                    }
                  },
                ),
                const SizedBox(height: 15),
                
                // List of categories directly inline
                ...filteredCategories.map((category) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: ElevatedButton(
                      onPressed: () => widget.game.loadSubjectAndStart(category),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueGrey[900],
                        minimumSize: const Size(double.infinity, 50),
                        side: const BorderSide(color: Colors.cyan, width: 1),
                      ),
                      child: Text(
                        category.name, 
                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)
                      ),
                    ),
                  );
                }).toList(),
                
                if (filteredCategories.isEmpty)
                   const Padding(
                     padding: EdgeInsets.all(20.0),
                     child: Text("No subjects found", style: TextStyle(color: Colors.white54)),
                   ),
                
                // Show a hint if we capped the list
                if (showingLimited)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 10),
                    child: Text("Use the search bar to find more subjects!", style: TextStyle(color: Colors.cyan, fontSize: 12, fontStyle: FontStyle.italic)),
                  ),
              const SizedBox(height: 20),
              const Divider(color: Colors.cyan, thickness: 1),
              const SizedBox(height: 10),

              // THE NEW CREATE SUBJECT BUTTON
              ElevatedButton(
                onPressed: () {
                  widget.game.overlays.remove('MainMenuOverlay');
                  widget.game.overlays.add('CreateSubjectOverlay'); // Open the creator!
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  side: const BorderSide(color: Colors.greenAccent, width: 2),
                  minimumSize: const Size(double.infinity, 50),
                ),
                child: const Text(
                  "CREATE NEW SUBJECT", 
                  style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, letterSpacing: 1)
                ),
              ),
              const SizedBox(height: 10),

              // THE NEW LEADERBOARD BUTTON
              ElevatedButton(
                onPressed: () {
                  widget.game.overlays.remove('MainMenuOverlay');
                  widget.game.overlays.add('LeaderboardOverlay'); // Open the leaderboard!
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  side: const BorderSide(color: Colors.pinkAccent, width: 2),
                  minimumSize: const Size(double.infinity, 50),
                ),
                child: const Text(
                  "VIEW HALL OF FAME", 
                  style: TextStyle(color: Colors.pinkAccent, fontWeight: FontWeight.bold, letterSpacing: 1)
                ),
              ),
              const SizedBox(height: 10),
              
              // NEW: VIBE SHOP BUTTON
              ElevatedButton(
                onPressed: () {
                  widget.game.overlays.remove('MainMenuOverlay');
                  widget.game.overlays.add('VibeShopOverlay'); // Open the shop!
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amberAccent.withOpacity(0.2),
                  side: const BorderSide(color: Colors.amberAccent, width: 2),
                  minimumSize: const Size(double.infinity, 50),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.shopping_cart, color: Colors.amberAccent),
                    SizedBox(width: 10),
                    Text(
                      "VIBE SHOP", 
                      style: TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, letterSpacing: 1)
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              
              // NEW: SOUND SETTINGS BUTTON
              ElevatedButton(
                onPressed: () {
                  widget.game.overlays.remove('MainMenuOverlay');
                  widget.game.overlays.add('SoundSettingsOverlay');
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.purpleAccent.withOpacity(0.2),
                  side: const BorderSide(color: Colors.purpleAccent, width: 2),
                  minimumSize: const Size(double.infinity, 50),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.volume_up, color: Colors.purpleAccent),
                    SizedBox(width: 10),
                    Text(
                      "SOUND SETTINGS", 
                      style: TextStyle(color: Colors.purpleAccent, fontWeight: FontWeight.bold, letterSpacing: 1)
                    ),
                  ],
                ),
              ),
            ],
            
            const SizedBox(height: 20),
            // The AdMob Banner
            const AdBannerWidget(),
          ],
        ),
      ),
    ),
    );
  }
}

class GameOverMenu extends StatefulWidget {
  final MaglevFlipGame game;
  const GameOverMenu({super.key, required this.game});

  @override
  State<GameOverMenu> createState() => _GameOverMenuState();
}

class _GameOverMenuState extends State<GameOverMenu> {
  final TextEditingController _nameController = TextEditingController();
  bool _isSubmitting = false;
  bool _hasSubmitted = false;
  List<Map<String, dynamic>> _leaderboardData = [];

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submitAndFetch() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return; // Don't allow empty names

    setState(() {
      _isSubmitting = true;
    });

    // 1. Submit the score to Supabase
    await widget.game.submitScore(name);

    // 2. Fetch the updated top 10 for the current category
    String currentCategory = widget.game.activeCategory?.name ?? "General";
    final data = await widget.game.fetchLeaderboard(currentCategory);

    // 3. Update the UI to show the leaderboard
    setState(() {
      _leaderboardData = data;
      _isSubmitting = false;
      _hasSubmitted = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(25),
        decoration: BoxDecoration(
          color: const Color(0xFF0A0A12).withOpacity(0.95), // Deep space black
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.cyanAccent, width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.cyanAccent.withOpacity(0.3),
              blurRadius: 15,
              spreadRadius: 2,
            ),
          ],
        ),
        width: 350,
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _hasSubmitted ? _buildLeaderboard() : _buildSubmissionForm(),
              const SizedBox(height: 15),
              const AdBannerWidget(),
            ],
          ),
        ),
      ),
    );
  }

  // UI STATE 1: The Input Form
  Widget _buildSubmissionForm() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          "SYSTEM CRASH",
          style: TextStyle(
            color: Colors.redAccent, 
            fontSize: 24, 
            fontWeight: FontWeight.bold, 
            letterSpacing: 3
          ),
        ),
        const SizedBox(height: 10),
        Text(
          "FINAL SCORE: ${widget.game.score.toInt()}",
          style: const TextStyle(
            color: Colors.white, 
            fontSize: 20, 
            fontFamily: 'Courier',
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.electric_bolt, color: Colors.amberAccent, size: 20),
            const SizedBox(width: 5),
            Text(
              "CELLS EXTRACTED: ${widget.game.shardsCollected}",
              style: const TextStyle(
                color: Colors.amberAccent, 
                fontSize: 16, 
                fontWeight: FontWeight.bold,
                fontFamily: 'Courier',
              ),
            ),
          ],
        ),
        const SizedBox(height: 25),
        
        // Cyberpunk Text Field
        TextField(
          controller: _nameController,
          style: const TextStyle(color: Colors.cyanAccent, fontSize: 18),
          maxLength: 12,
          textAlign: TextAlign.center,
          decoration: InputDecoration(
            counterText: "",
            hintText: "Player Name",
            hintStyle: TextStyle(color: Colors.cyanAccent.withOpacity(0.4)),
            enabledBorder: OutlineInputBorder(
              borderSide: const BorderSide(color: Colors.cyan, width: 1),
              borderRadius: BorderRadius.circular(8),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: const BorderSide(color: Colors.cyanAccent, width: 2),
              borderRadius: BorderRadius.circular(8),
            ),
            filled: true,
            fillColor: Colors.black54,
          ),
        ),
        const SizedBox(height: 20),

        // Submit Button
        _isSubmitting
            ? const CircularProgressIndicator(color: Colors.cyanAccent)
            : Column(
                children: [
                  ElevatedButton(
                    onPressed: _submitAndFetch,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      side: const BorderSide(color: Colors.pinkAccent, width: 2),
                      minimumSize: const Size(double.infinity, 50),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text(
                      "UPLOAD TO LEADERBOARD",
                      style: TextStyle(color: Colors.pinkAccent, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton(
                    onPressed: () {
                      widget.game.returnToMainMenu();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.cyanAccent,
                      minimumSize: const Size(double.infinity, 50),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text(
                      "RESTART GAME",
                      style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
      ],
    );
  }

  // UI STATE 2: The Leaderboard
  Widget _buildLeaderboard() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          "GLOBAL RANKINGS",
          style: TextStyle(
            color: Colors.cyanAccent, 
            fontSize: 22, 
            fontWeight: FontWeight.bold, 
            letterSpacing: 2
          ),
        ),
        const SizedBox(height: 15),
        
        // The Top 10 List
        Container(
          constraints: const BoxConstraints(maxHeight: 250),
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _leaderboardData.length,
            itemBuilder: (context, index) {
              final player = _leaderboardData[index];
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "#${index + 1}  ${player['player_name']}",
                      style: const TextStyle(color: Colors.white70, fontSize: 16, fontFamily: 'Courier'),
                    ),
                    Text(
                      "${player['score']}",
                      style: const TextStyle(color: Colors.pinkAccent, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 20),

        // Restart Game Button
        ElevatedButton(
          onPressed: () {
            widget.game.returnToMainMenu();
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.cyanAccent,
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
          ),
          child: const Text(
            "INITIALIZE NEW RUN",
            style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}

class InGameHUD extends StatelessWidget {
  final MaglevFlipGame game;
  const InGameHUD({super.key, required this.game});

  @override
  Widget build(BuildContext context) {
    // If no data exists, don't show the box
    if (game.currentTop5.isEmpty) return const SizedBox.shrink();

    return Align(
      alignment: Alignment.topRight, // Pin to top right
      child: Container(
        margin: const EdgeInsets.only(top: 40, right: 20),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.4), // Highly transparent
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.cyanAccent.withOpacity(0.3), width: 1),
        ),
        // IgnorePointer ensures tapping the HUD flips gravity instead of blocking the tap
        child: IgnorePointer( 
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text(
                "TARGETS TO BEAT", 
                style: TextStyle(color: Colors.pinkAccent, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)
              ),
              Text(
                game.activeCategory?.name ?? "Play for Fun",
                style: const TextStyle(color: Colors.cyanAccent, fontSize: 9, letterSpacing: 0.5),
              ),
              const SizedBox(height: 5),
              
              // Generate the Top 5 List dynamically
              ...game.currentTop5.asMap().entries.map((entry) {
                int rank = entry.key + 1;
                var player = entry.value;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 2.0),
                  child: Text(
                    "#$rank ${player['player_name']} : ${player['score']}",
                    style: TextStyle(
                      // Make the #1 player gold, others white
                      color: rank == 1 ? Colors.amberAccent : Colors.white70, 
                      fontSize: 12, 
                      fontFamily: 'Courier'
                    ),
                  ),
                );
              }).toList(),
            ],
          ),
        ),
      ),
    );
  }
}

class LeaderboardMenu extends StatefulWidget {
  final MaglevFlipGame game;
  const LeaderboardMenu({super.key, required this.game});

  @override
  State<LeaderboardMenu> createState() => _LeaderboardMenuState();
}

class _LeaderboardMenuState extends State<LeaderboardMenu> {
  bool _isLoading = true;
  String _selectedCategory = "General";
  List<Map<String, dynamic>> _leaderboardData = [];
  String _searchQuery = "";
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // Default to Play for Fun
    _selectedCategory = "Play for Fun";
    _fetchData();
  }

  Future<void> _fetchData() async {
    setState(() {
      _isLoading = true;
    });
    
    final data = await widget.game.fetchLeaderboard(_selectedCategory);
    
    if (mounted) {
      setState(() {
        _leaderboardData = data;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF0A0A12).withOpacity(0.95),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: Colors.cyanAccent, width: 2),
        ),
        width: 350,
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "GLOBAL RANKINGS",
              style: TextStyle(color: Colors.pinkAccent, fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: 2),
            ),
            const SizedBox(height: 15),

            // Category Selector Dropdown
            if (widget.game.availableCategories.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  border: Border.all(color: Colors.cyan, width: 1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    dropdownColor: Colors.black87,
                    value: _selectedCategory,
                    isExpanded: true,
                    icon: const Icon(Icons.arrow_drop_down, color: Colors.cyanAccent),
                    style: const TextStyle(color: Colors.cyanAccent, fontSize: 16),
                    onChanged: (String? newValue) {
                      if (newValue != null && newValue != _selectedCategory) {
                        setState(() {
                          _selectedCategory = newValue;
                        });
                        _fetchData();
                      }
                    },
                    items: [
                      const DropdownMenuItem<String>(
                        value: "Play for Fun",
                        child: Text("Play for Fun"),
                      ),
                      ...widget.game.availableCategories.map<DropdownMenuItem<String>>((category) {
                        return DropdownMenuItem<String>(
                          value: category.name,
                          child: Text(category.name),
                        );
                      }).toList(),
                    ],
                  ),
                ),
              ),
            
            const SizedBox(height: 15),

            // Search Bar
            TextField(
              controller: _searchController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Search by rank or name...',
                hintStyle: const TextStyle(color: Colors.white54),
                prefixIcon: const Icon(Icons.search, color: Colors.cyanAccent),
                enabledBorder: OutlineInputBorder(
                  borderSide: const BorderSide(color: Colors.cyanAccent),
                  borderRadius: BorderRadius.circular(8),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: const BorderSide(color: Colors.pinkAccent, width: 2),
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 10),
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value.toLowerCase();
                });
              },
            ),
            const SizedBox(height: 20),

            // The Leaderboard List
            Builder(
              builder: (context) {
                List<Map<String, dynamic>> filteredData = [];
                for (int i = 0; i < _leaderboardData.length; i++) {
                  final player = _leaderboardData[i];
                  final rank = (i + 1).toString();
                  final name = player['player_name'].toString().toLowerCase();
                  if (_searchQuery.isEmpty || rank.contains(_searchQuery) || name.contains(_searchQuery)) {
                    filteredData.add({
                      'rank': rank,
                      'player': player,
                    });
                  }
                }
                return Flexible(
                  child: _isLoading
                      ? const Padding(
                          padding: EdgeInsets.all(20.0),
                          child: CircularProgressIndicator(color: Colors.cyanAccent),
                        )
                      : filteredData.isEmpty
                          ? const Text("NO DATA FOUND", style: TextStyle(color: Colors.white54))
                          : ListView.builder(
                              shrinkWrap: true,
                              itemCount: filteredData.length,
                              itemBuilder: (context, index) {
                                final item = filteredData[index];
                                final player = item['player'];
                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 6.0),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        "#${item['rank']}  ${player['player_name']}",
                                        style: const TextStyle(color: Colors.white, fontSize: 16, fontFamily: 'Courier'),
                                      ),
                                      Text(
                                        "${player['score']}",
                                        style: const TextStyle(color: Colors.pinkAccent, fontSize: 16, fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                );
              }
            ),
            const SizedBox(height: 20),

            // Back Button
            ElevatedButton(
              onPressed: () {
                widget.game.overlays.remove('LeaderboardOverlay');
                widget.game.overlays.add('MainMenuOverlay');
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                side: const BorderSide(color: Colors.cyanAccent, width: 1),
                minimumSize: const Size(double.infinity, 45),
              ),
              child: const Text("RETURN TO MENU", style: TextStyle(color: Colors.cyanAccent)),
            ),
          ],
        ),
      ),
    );
  }
}

class VibeShopMenu extends StatefulWidget {
  final MaglevFlipGame game;
  const VibeShopMenu({super.key, required this.game});

  @override
  State<VibeShopMenu> createState() => _VibeShopMenuState();
}

class _VibeShopMenuState extends State<VibeShopMenu> {
  Future<void> _buySkin(String skinId, int price) async {
    if (widget.game.bankBalance >= price && !widget.game.unlockedSkins.contains(skinId)) {
      setState(() {
        widget.game.bankBalance -= price;
        widget.game.unlockedSkins.add(skinId);
      });
      
      // Update Supabase Database
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId != null) {
        await Supabase.instance.client.from('profiles').update({
          'coins': widget.game.bankBalance,
          'unlocked_skins': widget.game.unlockedSkins,
        }).eq('id', userId);
      }
    }
  }

  Future<void> _equipSkin(String skinId) async {
    setState(() {
      widget.game.activeSkin = skinId;
    });
    
    // Apply the skin visually immediately
    await widget.game.player.applySkin(skinId);
    
    // Update Supabase Database
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId != null) {
      await Supabase.instance.client.from('profiles').update({
        'active_skin': skinId,
      }).eq('id', userId);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: Colors.amberAccent, width: 2),
        ),
        child: Column(
          children: [
            // Header with Back button and Bank Balance
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.cyan),
                  onPressed: () {
                    widget.game.overlays.remove('VibeShopOverlay');
                    widget.game.overlays.add('MainMenuOverlay');
                  },
                ),
                const Text(
                  "VIBE SHOP",
                  style: TextStyle(color: Colors.cyan, fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: 2),
                ),
                Row(
                  children: [
                    const Icon(Icons.electric_bolt, color: Colors.amberAccent, size: 20),
                    const SizedBox(width: 4),
                    Text(
                      "${widget.game.bankBalance}",
                      style: const TextStyle(color: Colors.amberAccent, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ],
            ),
            const Divider(color: Colors.amberAccent, thickness: 1),
            const SizedBox(height: 10),
            
            if (widget.game.liveShopInventory.isEmpty)
              const Expanded(
                child: Center(
                  child: CircularProgressIndicator(color: Colors.amberAccent),
                ),
              )
            else
              // Shop Inventory List
              Expanded(
                child: ListView.builder(
                  itemCount: widget.game.liveShopInventory.length,
                  itemBuilder: (context, index) {
                    final item = widget.game.liveShopInventory[index];
                    final skinId = item['id'];
                    final price = item['price'] as int;
                    final isUnlocked = widget.game.unlockedSkins.contains(skinId);
                    final isEquipped = widget.game.activeSkin == skinId;

                    return Card(
                      color: Colors.blueGrey[900],
                      margin: const EdgeInsets.only(bottom: 15),
                      shape: RoundedRectangleBorder(
                        side: BorderSide(color: isEquipped ? Colors.amberAccent : Colors.cyan.withOpacity(0.3)),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(10.0),
                        child: Row(
                          children: [
                            // Render Remote Image
                            Container(
                              width: 80,
                              height: 40,
                              decoration: BoxDecoration(
                                color: Colors.black,
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: Image.network(
                                item['image_url'],
                                fit: BoxFit.contain,
                                errorBuilder: (context, error, stackTrace) => const Icon(Icons.image_not_supported, color: Colors.white54),
                              ),
                            ),
                            const SizedBox(width: 15),
                            
                            // Name and Price
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item['name'],
                                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 5),
                                  if (!isUnlocked)
                                    Row(
                                      children: [
                                        const Icon(Icons.electric_bolt, color: Colors.amberAccent, size: 14),
                                        const SizedBox(width: 4),
                                        Text(
                                          "$price",
                                          style: const TextStyle(color: Colors.amberAccent, fontSize: 14),
                                        ),
                                      ],
                                    )
                                  else
                                    const Text("OWNED", style: TextStyle(color: Colors.greenAccent, fontSize: 14)),
                                ],
                              ),
                            ),
                            
                            // Action Button (Buy or Equip)
                            if (isEquipped)
                              const Padding(
                                padding: EdgeInsets.all(8.0),
                                child: Text("EQUIPPED", style: TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold)),
                              )
                            else if (isUnlocked)
                              ElevatedButton(
                                onPressed: () => _equipSkin(skinId),
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.cyan),
                                child: const Text("EQUIP", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                              )
                            else
                              ElevatedButton(
                                onPressed: widget.game.bankBalance >= price ? () => _buySkin(skinId, price) : null,
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.pinkAccent),
                                child: const Text("BUY", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class SoundSettingsMenu extends StatefulWidget {
  final MaglevFlipGame game;
  const SoundSettingsMenu({super.key, required this.game});

  @override
  State<SoundSettingsMenu> createState() => _SoundSettingsMenuState();
}

class _SoundSettingsMenuState extends State<SoundSettingsMenu> {
  late AudioManager audioManager;

  @override
  void initState() {
    super.initState();
    audioManager = AudioManager();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(25),
        decoration: BoxDecoration(
          color: const Color(0xFF1E103C).withOpacity(0.95), // Deep purple theme
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: Colors.purpleAccent, width: 2),
        ),
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "SOUND SETTINGS",
                  style: TextStyle(color: Colors.purpleAccent, fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 1),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white54),
                  onPressed: () {
                    widget.game.overlays.remove('SoundSettingsOverlay');
                    if (widget.game.isGamePaused) {
                      widget.game.overlays.add('PauseMenuOverlay');
                    } else {
                      widget.game.overlays.add('MainMenuOverlay');
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 20),
            
            // BGM Toggle
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                audioManager.isBgmMuted ? Icons.music_off : Icons.music_note,
                color: audioManager.isBgmMuted ? Colors.redAccent : Colors.greenAccent,
                size: 30,
              ),
              title: Text(
                audioManager.isBgmMuted ? "BGM Muted" : "BGM Enabled",
                style: const TextStyle(color: Colors.white, fontSize: 18),
              ),
              trailing: Switch(
                value: !audioManager.isBgmMuted,
                activeColor: Colors.greenAccent,
                inactiveThumbColor: Colors.redAccent,
                onChanged: (value) {
                  setState(() {
                    audioManager.toggleBgm();
                    // Also mute the network BGM from Supabase
                    if (audioManager.isBgmMuted) {
                      widget.game.bgmPlayer.pause();
                    } else if (widget.game.networkBgmUrl != null) {
                      widget.game.bgmPlayer.resume();
                    }
                  });
                },
              ),
            ),
            
            // SFX Toggle
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                audioManager.isSfxMuted ? Icons.volume_off : Icons.volume_up,
                color: audioManager.isSfxMuted ? Colors.redAccent : Colors.greenAccent,
                size: 30,
              ),
              title: Text(
                audioManager.isSfxMuted ? "SFX Muted" : "SFX Enabled",
                style: const TextStyle(color: Colors.white, fontSize: 18),
              ),
              trailing: Switch(
                value: !audioManager.isSfxMuted,
                activeColor: Colors.greenAccent,
                inactiveThumbColor: Colors.redAccent,
                onChanged: (value) {
                  setState(() {
                    audioManager.toggleSfx();
                  });
                },
              ),
            ),
            const Divider(color: Colors.purpleAccent, height: 30),
            
            // BGM Selector
            const Align(
              alignment: Alignment.centerLeft,
              child: Text("Background Music", style: TextStyle(color: Colors.purpleAccent, fontSize: 14)),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.purpleAccent.withOpacity(0.5)),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: audioManager.currentBgmTrack,
                  isExpanded: true,
                  dropdownColor: const Color(0xFF1E103C),
                  icon: const Icon(Icons.music_note, color: Colors.purpleAccent),
                  items: audioManager.bgmTracks.map((String track) {
                    return DropdownMenuItem<String>(
                      value: track,
                      child: Text(
                        track.replaceAll('.mp3', '').replaceAll('_', ' ').toUpperCase(),
                        style: const TextStyle(color: Colors.white),
                      ),
                    );
                  }).toList(),
                  onChanged: (String? newValue) {
                    if (newValue != null) {
                      setState(() {
                        audioManager.setBgmTrack(newValue);
                      });
                    }
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CreateSubjectMenu extends StatefulWidget {
  final MaglevFlipGame game;
  const CreateSubjectMenu({super.key, required this.game});

  @override
  State<CreateSubjectMenu> createState() => _CreateSubjectMenuState();
}

class _CreateSubjectMenuState extends State<CreateSubjectMenu> {
  final _nameController = TextEditingController();
  final _urlController = TextEditingController();
  bool _isPublic = true;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  String _generateRandomString(int length) {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rnd = Random();
    return String.fromCharCodes(Iterable.generate(
      length, (_) => chars.codeUnitAt(rnd.nextInt(chars.length))));
  }

  Future<void> _downloadSampleCSV() async {
    try {
      Directory? dir = await getDownloadsDirectory();
      dir ??= await getApplicationDocumentsDirectory();
      
      final String filePath = '${dir.path}/maglev_flip_sample_quiz.csv';
      final File file = File(filePath);
      
      final String csvData = "Question,Correct Answer,Option 1,Option 2,Option 3\nWhat is 2+2?,4,3,5,6\nWhat color is the sky?,Blue,Red,Green,Yellow";
      await file.writeAsString(csvData);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Sample CSV saved to: $filePath')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to download: $e')));
      }
    }
  }

  Future<void> _createSubject() async {
    final name = _nameController.text.trim();
    final url = _urlController.text.trim();

    if (name.isEmpty || url.isEmpty) {
       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please fill all fields')));
       return;
    }

    setState(() {
      _isSubmitting = true;
    });

    final shareCode = '${_generateRandomString(2)}-${_generateRandomString(4)}';
    String? loginId;
    String? password;

    if (!_isPublic) {
      loginId = _generateRandomString(6);
      password = _generateRandomString(4);
    }

    try {
      await Supabase.instance.client.from('master_subjects').insert({
        'share_code': shareCode,
        'name': name,
        'sheet_url': url,
        'is_public': _isPublic,
        'login_id': loginId,
        'password': password,
      });

      setState(() {
        _isSubmitting = false;
      });

      _showSuccessDialog(shareCode, loginId, password);

    } catch (e) {
      setState(() {
        _isSubmitting = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  void _showSuccessDialog(String shareCode, String? loginId, String? password) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.black87,
          title: const Text("SUBJECT CREATED!", style: TextStyle(color: Colors.greenAccent)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Save these details. You will not see them again.", style: TextStyle(color: Colors.white54)),
              const SizedBox(height: 10),
              Text("Share Code: $shareCode", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              if (!_isPublic) ...[
                const SizedBox(height: 5),
                Text("Login ID: $loginId", style: const TextStyle(color: Colors.white)),
                Text("Password: $password", style: const TextStyle(color: Colors.white)),
              ]
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () {
                const String appLink = String.fromEnvironment('APP_LINK', defaultValue: 'https://maglevflip.com');
                String shareText = "Play Maglev Flip! Link: $appLink | Share Code: $shareCode";
                if (!_isPublic) {
                  shareText += " | Login ID: $loginId | Password: $password";
                }
                Share.share(shareText);
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
              child: const Text("SHARE", style: TextStyle(color: Colors.white)),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context); // close dialog
                widget.game.overlays.remove('CreateSubjectOverlay');
                widget.game.overlays.add('MainMenuOverlay');
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.greenAccent),
              child: const Text("DONE", style: TextStyle(color: Colors.black)),
            ),
          ],
        );
      }
    );
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: Colors.greenAccent, width: 2),
        ),
        width: 320,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("NEW SUBJECT", style: TextStyle(color: Colors.greenAccent, fontSize: 22, fontWeight: FontWeight.bold)),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white54),
                    onPressed: () {
                      widget.game.overlays.remove('CreateSubjectOverlay');
                      widget.game.overlays.add('MainMenuOverlay');
                    },
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _nameController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: "Subject Name",
                  labelStyle: TextStyle(color: Colors.greenAccent),
                  enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.greenAccent)),
                  focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white)),
                ),
              ),
              const SizedBox(height: 15),
              TextField(
                controller: _urlController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: "Google Sheet Link",
                  hintText: "Ensure link is public",
                  hintStyle: TextStyle(color: Colors.white38),
                  labelStyle: TextStyle(color: Colors.greenAccent),
                  enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.greenAccent)),
                  focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white)),
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _downloadSampleCSV,
                  child: const Text("Download Sample CSV", style: TextStyle(color: Colors.cyan, decoration: TextDecoration.underline, fontSize: 12)),
                ),
              ),
              const SizedBox(height: 5),
              CheckboxListTile(
                title: const Text("Public Subject", style: TextStyle(color: Colors.white)),
                activeColor: Colors.greenAccent,
                checkColor: Colors.black,
                value: _isPublic,
                onChanged: (val) {
                  if (val != null) setState(() => _isPublic = val);
                },
              ),
              const SizedBox(height: 20),
              _isSubmitting
                ? const CircularProgressIndicator(color: Colors.greenAccent)
                : ElevatedButton(
                    onPressed: _createSubject,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.greenAccent,
                      minimumSize: const Size(double.infinity, 50),
                    ),
                    child: const Text("CREATE", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

class ShootButtonOverlay extends StatelessWidget {
  final MaglevFlipGame game;

  const ShootButtonOverlay({super.key, required this.game});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 32,
      right: 32,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.orange,
          shape: const CircleBorder(),
          padding: const EdgeInsets.all(24),
        ),
        onPressed: () {
          game.fireMissile();
        },
        child: const Icon(
          Icons.rocket_launch,
          size: 36,
          color: Colors.white,
        ),
      ),
    );
  }
}

class PauseButtonOverlay extends StatelessWidget {
  final MaglevFlipGame game;
  const PauseButtonOverlay({super.key, required this.game});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 40,
      left: 20,
      child: Material(
        color: Colors.transparent,
        child: IconButton(
          icon: const Icon(Icons.pause, color: Colors.cyan, size: 35),
          onPressed: () => game.pauseGame(),
        ),
      ),
    );
  }
}

class PauseMenuOverlay extends StatelessWidget {
  final MaglevFlipGame game;
  const PauseMenuOverlay({super.key, required this.game});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(25),
        decoration: BoxDecoration(
          color: const Color(0xFF0A0A12).withOpacity(0.95),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: Colors.cyan, width: 2),
        ),
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "PAUSED",
              style: TextStyle(color: Colors.cyan, fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 2),
            ),
            const SizedBox(height: 30),
            ElevatedButton(
              onPressed: () => game.resumeGame(),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.cyan,
                minimumSize: const Size(double.infinity, 50),
              ),
              child: const Text("RESUME", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 15),
            ElevatedButton(
              onPressed: () {
                game.overlays.remove('PauseMenuOverlay');
                game.overlays.add('SoundSettingsOverlay');
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purpleAccent.withOpacity(0.2),
                side: const BorderSide(color: Colors.purpleAccent, width: 2),
                minimumSize: const Size(double.infinity, 50),
              ),
              child: const Text("SOUND SETTINGS", style: TextStyle(color: Colors.purpleAccent, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 15),
            ElevatedButton(
              onPressed: () {
                game.isGamePaused = false;
                game.overlays.remove('PauseMenuOverlay');
                game.returnToMainMenu();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent.withOpacity(0.2),
                side: const BorderSide(color: Colors.redAccent, width: 2),
                minimumSize: const Size(double.infinity, 50),
              ),
              child: const Text("QUIT TO MENU", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}
