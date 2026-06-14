import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Maglev Flip',
      home: const MaglevFlipScreen(),
    ),
  );
}

class MaglevFlipScreen extends StatelessWidget {
  const MaglevFlipScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, // Background will eventually be handled by Flame, but black is a good default
      body: GameWidget(
        game: MaglevFlipGame(),
      ),
    );
  }
}

class MaglevFlipGame extends FlameGame with TapCallbacks, HasCollisionDetection {
  late final RailComponent rail;
  late final PlayerComponent player;

  @override
  FutureOr<void> onLoad() async {
    await super.onLoad();

    // The rail cuts exactly through the middle of the screen
    rail = RailComponent(
      position: Vector2(0, size.y / 2),
      size: Vector2(size.x, 10), // 10 pixels thick
    );
    add(rail);

    // The player starts resting on top of the rail
    player = PlayerComponent(rail: rail);
    add(player);
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    if (isLoaded) {
      // Keep the rail correctly centered if screen resizes
      rail.position = Vector2(0, size.y / 2);
      rail.size = Vector2(size.x, 10);
      player.updatePosition();
    }
  }

  @override
  void onTapDown(TapDownEvent event) {
    // Tapping instantly flips gravity
    player.flipGravity();
  }
}

class RailComponent extends PositionComponent {
  RailComponent({required super.position, required super.size});

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    // Draw the rail
    final paint = Paint()..color = Colors.blueGrey;
    canvas.drawRect(size.toRect(), paint);
    
    // Add an electrified core line in the middle of the rail
    final corePaint = Paint()..color = Colors.lightBlueAccent;
    canvas.drawRect(
      Rect.fromLTWH(0, size.y / 2 - 1, size.x, 2),
      corePaint,
    );
  }
}

class PlayerComponent extends PositionComponent {
  final RailComponent rail;
  bool isOnTop = true;
  
  static final Vector2 playerSize = Vector2(50, 25);

  PlayerComponent({required this.rail}) : super(size: playerSize) {
    // Keep the anchor exactly in the center to make math and rotation easier
    anchor = Anchor.center;
  }

  @override
  FutureOr<void> onLoad() {
    super.onLoad();
    // Add hitbox for future collision detection
    add(RectangleHitbox());
    updatePosition();
  }

  void updatePosition() {
    // X position is fixed on the left side
    const xPos = 100.0;
    
    if (isOnTop) {
      // Rail top edge = rail.position.y
      // Center of player = rail top edge - player.size.y / 2
      position = Vector2(xPos, rail.position.y - size.y / 2);
      // Train is upright
      angle = 0; 
    } else {
      // Rail bottom edge = rail.position.y + rail.size.y
      // Center of player = rail bottom edge + player.size.y / 2
      position = Vector2(xPos, rail.position.y + rail.size.y + size.y / 2);
      // Train flips upside down visually
      angle = 3.14159; // roughly 180 degrees
    }
  }

  void flipGravity() {
    isOnTop = !isOnTop;
    updatePosition();
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    
    // Draw the main body of the train
    final paint = Paint()..color = Colors.cyanAccent;
    final rect = size.toRect();
    canvas.drawRect(rect, paint);
    
    // Draw a darker roof/trim
    final trimPaint = Paint()..color = Colors.cyan.shade700;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.x, 5), trimPaint);
    
    // Draw a window detail to indicate direction/front
    final windowPaint = Paint()..color = Colors.yellow;
    // Front is to the right (positive X direction), so window is near size.x
    canvas.drawRect(Rect.fromLTWH(size.x - 15, 8, 10, 10), windowPaint);
  }
}
