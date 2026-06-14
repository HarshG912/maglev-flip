import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class VideoBackground extends StatefulWidget {
  final String videoUrl;

  const VideoBackground({super.key, required this.videoUrl});

  @override
  State<VideoBackground> createState() => _VideoBackgroundState();
}

class _VideoBackgroundState extends State<VideoBackground> {
  late VideoPlayerController _controller;

  @override
  void initState() {
    super.initState();
    // Initialize the network video from your Supabase URL
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl))
      ..initialize().then((_) {
        // Once initialized, mute it, loop it, and play it!
        _controller.setVolume(0.0);
        _controller.setLooping(true);
        _controller.play();
        setState(() {}); // Trigger a rebuild to show the first frame
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _controller.value.isInitialized
        ? SizedBox.expand(
            // BoxFit.cover ensures the video stretches to fill the whole screen,
            // trimming the edges if the aspect ratio doesn't perfectly match the phone.
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: _controller.value.size.width,
                height: _controller.value.size.height,
                child: VideoPlayer(_controller),
              ),
            ),
          )
        : Container(color: Colors.black); // Show black while buffering
  }
}
