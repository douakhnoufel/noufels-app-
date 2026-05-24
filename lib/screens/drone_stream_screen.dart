import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_vlc_player/flutter_vlc_player.dart';
import '../services/classifier_service.dart';
import 'result_screen.dart';

class DroneStreamScreen extends StatefulWidget {
  final ClassifierService classifier;
  const DroneStreamScreen({super.key, required this.classifier});

  @override
  State<DroneStreamScreen> createState() => _DroneStreamScreenState();
}

class _DroneStreamScreenState extends State<DroneStreamScreen> {
  late VlcPlayerController _vlcController;
  final TextEditingController _urlController = TextEditingController(
    text: 'rtmp://192.168.1.10/live/drone', // Default placeholder
  );
  
  bool _isPlaying = false;
  bool _isDetecting = false;
  String _label = 'Waiting for stream...';
  double _confidence = 0.0;
  Color _labelColor = Colors.white70;

  @override
  void initState() {
    super.initState();
    _vlcController = VlcPlayerController.network(
      _urlController.text,
      hwAcc: HwAcc.full,
      autoPlay: false,
      options: VlcPlayerOptions(),
    );
  }

  @override
  void dispose() {
    _vlcController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _toggleStream() async {
    if (_isPlaying) {
      await _vlcController.pause();
    } else {
      await _vlcController.setStreamUrl(_urlController.text);
      await _vlcController.play();
      _startInferenceLoop();
    }
    setState(() => _isPlaying = !_isPlaying);
  }

  void _startInferenceLoop() async {
    // Run inference every 500ms on the stream frame
    while (_isPlaying && mounted) {
      if (!_isDetecting) {
        _runInferenceOnFrame();
      }
      await Future.delayed(const Duration(milliseconds: 500));
    }
  }

  Future<void> _runInferenceOnFrame() async {
    if (!mounted || _isDetecting) return;
    
    _isDetecting = true;
    try {
      // Capture the current frame from VLC as bytes
      final Uint8List? imageBytes = await _vlcController.takeSnapshot();
      
      if (imageBytes != null && mounted) {
        final full = await widget.classifier.classifyBytes(imageBytes);
        
        if (mounted) {
          setState(() {
            if (full.result.confidence > 0.45) {
              _label = full.result.label;
              _confidence = full.result.confidence;
              _labelColor = full.result.color;
            } else {
              _label = 'Scanning Field...';
              _confidence = 0.0;
              _labelColor = Colors.white70;
            }
          });
        }
      }
    } catch (e) {
      debugPrint('Drone Inference Error: $e');
    } finally {
      _isDetecting = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('DRONE GROUND STATION', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 1.5)),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Column(
        children: [
          // URL Input
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _urlController,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.white10,
                      hintText: 'Enter RTMP URL',
                      hintStyle: const TextStyle(color: Colors.white24),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                IconButton.filled(
                  onPressed: _toggleStream,
                  icon: Icon(_isPlaying ? Icons.stop_rounded : Icons.play_arrow_rounded),
                  style: IconButton.styleFrom(backgroundColor: _isPlaying ? Colors.red : colorScheme.primary),
                ),
              ],
            ),
          ),

          // Video Feed
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white10),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    VlcPlayer(
                      controller: _vlcController,
                      aspectRatio: 16 / 9,
                      placeholder: const Center(child: CircularProgressIndicator()),
                    ),
                    
                    // Scanning Lines (Animated)
                    if (_isPlaying)
                      _DroneScanningOverlay(color: _labelColor),

                    // Floating Detection Result
                    Positioned(
                      top: 20,
                      left: 20,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: _labelColor.withValues(alpha: 0.8),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _label,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ).animate(key: ValueKey(_label)).scale(duration: 200.milliseconds),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // HUD / Stats
          Container(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _HudStat(label: 'ALTITUDE', value: '--- m'),
                    _HudStat(label: 'CONFIDENCE', value: '${(_confidence * 100).toStringAsFixed(1)}%'),
                    _HudStat(label: 'MODE', value: 'RTMP LIVE'),
                  ],
                ),
                const SizedBox(height: 32),
                const Text(
                  'MAVIC AIR 2 REMOTE FEED',
                  style: TextStyle(color: Colors.white24, fontSize: 10, letterSpacing: 2, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HudStat extends StatelessWidget {
  final String label;
  final String value;
  const _HudStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900)),
      ],
    );
  }
}

class _DroneScanningOverlay extends StatelessWidget {
  final Color color;
  const _DroneScanningOverlay({required this.color});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Horizontal scan line
        Container(
          width: double.infinity,
          height: 2,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [color.withValues(alpha: 0), color, color.withValues(alpha: 0)],
            ),
          ),
        ).animate(onPlay: (c) => c.repeat()).moveY(
              begin: 0,
              end: 300,
              duration: 3.seconds,
              curve: Curves.easeInOut,
            ),
        // Corner borders
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
          ),
        ),
      ],
    );
  }
}
