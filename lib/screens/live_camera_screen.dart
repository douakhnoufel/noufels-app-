import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter/services.dart';
import '../services/classifier_service.dart';
import '../services/image_preprocessor.dart';
import '../services/database_service.dart';
import '../widgets/yolo_box_overlay.dart';
import 'result_screen.dart';

class LiveCameraScreen extends StatefulWidget {
  final ClassifierService classifier;
  const LiveCameraScreen({super.key, required this.classifier});

  @override
  State<LiveCameraScreen> createState() => _LiveCameraScreenState();
}

class _LiveCameraScreenState extends State<LiveCameraScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  bool _isInitialized = false;
  bool _isDetecting = false;
  bool _isFrontCamera = false;
  bool _isFlashOn = false;

  // Detection results
  String _label = 'Scanning...';
  double _confidence = 0.0;
  Color _labelColor = Colors.white70;
  List<YoloDetection> _detections = const [];

  // Thresholds
  static const double _confidenceThreshold = 0.30;
  static const double _vibrationThreshold = 0.85;
  String _lastVibratedLabel = '';

  // Throttle
  static const int _inferenceIntervalMs = 150;
  DateTime _lastInference = DateTime.fromMillisecondsSinceEpoch(0);

  final DatabaseService _db = DatabaseService();

  static const Map<String, Color> _classColors = {
    'Early Blight': Color(0xFFFF8C42),
    'Late Blight': Color(0xFFE53935),
    'Healthy': Color(0xFF43A047),
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) return;
      await _startCamera(_cameras[0]);
    } catch (e) {
      debugPrint('Camera Init Error: $e');
    }
  }

  Future<void> _startCamera(CameraDescription camera) async {
    final controller = CameraController(
      camera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup:
          Platform.isIOS ? ImageFormatGroup.bgra8888 : ImageFormatGroup.yuv420,
    );
    _controller = controller;

    try {
      await controller.initialize();
      if (!mounted) return;
      setState(() => _isInitialized = true);
      await controller.startImageStream(_onCameraFrame);
    } catch (e) {
      debugPrint('Camera Start Error: $e');
    }
  }

  void _onCameraFrame(CameraImage image) async {
    final now = DateTime.now();
    if (now.difference(_lastInference).inMilliseconds < _inferenceIntervalMs) {
      return;
    }
    if (_isDetecting) return;

    _lastInference = now;
    _isDetecting = true;

    try {
      final frame = _buildFrame(image);
      final full = await widget.classifier.classifyCameraFrameFull(frame);
      final result = full.result;
      debugPrint(
          '[LiveCameraScreen] Frame inference result: ${result.label} (${result.confidence})');

      if (mounted) {
        final double currentConf = result.confidence;
        final bool isCertain = currentConf >= _confidenceThreshold;

        final nextLabel = isCertain ? result.label : 'Scanning...';
        final nextColor = isCertain
            ? (_classColors[result.label] ?? Colors.white)
            : Colors.white70;

        // Haptic Feedback Logic
        if (isCertain &&
            currentConf >= _vibrationThreshold &&
            _lastVibratedLabel != result.label) {
          HapticFeedback.mediumImpact();
          _lastVibratedLabel = result.label;
        } else if (!isCertain) {
          _lastVibratedLabel = '';
        }

        setState(() {
          _label = nextLabel;
          _confidence = isCertain ? currentConf : 0.0;
          _labelColor = nextColor;
          _detections = isCertain ? full.detections : const [];
        });
      }
    } catch (e) {
      debugPrint('[LiveCameraScreen] Frame error: $e');
    } finally {
      _isDetecting = false;
    }
  }

  CameraFrame _buildFrame(CameraImage image) {
    if (image.format.group == ImageFormatGroup.jpeg) {
      return CameraFrame.jpeg(
          width: image.width,
          height: image.height,
          bytes: image.planes[0].bytes);
    }
    if (image.format.group == ImageFormatGroup.bgra8888) {
      return CameraFrame.bgra8888(
          width: image.width,
          height: image.height,
          bytes: image.planes[0].bytes,
          bytesPerRow: image.planes[0].bytesPerRow);
    }
    if (image.format.group == ImageFormatGroup.yuv420) {
      return CameraFrame.yuv420(
        width: image.width,
        height: image.height,
        yPlane: image.planes[0].bytes,
        uPlane: image.planes[1].bytes,
        vPlane: image.planes[2].bytes,
        yRowStride: image.planes[0].bytesPerRow,
        uRowStride: image.planes[1].bytesPerRow,
        vRowStride: image.planes[2].bytesPerRow,
        uPixelStride: image.planes[1].bytesPerPixel ?? 1,
        vPixelStride: image.planes[2].bytesPerPixel ?? 1,
      );
    }
    throw UnsupportedError('Unsupported image format');
  }

  Future<void> _toggleFlash() async {
    if (_controller == null || !_isInitialized) return;
    try {
      _isFlashOn = !_isFlashOn;
      await _controller!
          .setFlashMode(_isFlashOn ? FlashMode.torch : FlashMode.off);
      setState(() {});
    } catch (e) {
      debugPrint('Flash Error: $e');
    }
  }

  Future<void> _toggleCamera() async {
    if (_cameras.length < 2) return;
    final controller = _controller;
    if (controller != null) {
      await controller.stopImageStream();
      await controller.dispose();
    }
    _isFrontCamera = !_isFrontCamera;
    _isFlashOn = false;
    setState(() => _isInitialized = false);
    await _startCamera(_cameras[_isFrontCamera ? 1 : 0]);
  }

  Future<void> _captureAndAnalyze() async {
    if (_controller == null || !_isInitialized) return;
    try {
      await _controller!.stopImageStream();
      final XFile photo = await _controller!.takePicture();
      final bytes = await photo.readAsBytes();
      debugPrint('[LiveCameraScreen] Photo captured, bytes: ${bytes.length}');
      final full = await widget.classifier.classifyBytes(bytes);
      debugPrint(
          '[LiveCameraScreen] Capture inference result: ${full.result.label} (${full.result.confidence})');

      // Save to History
      await _db.insertScan(ScanHistoryItem(
        label: full.result.label,
        confidence: full.result.confidence,
        timestamp: DateTime.now(),
        imageBytes: bytes,
      ));

      if (mounted) {
        debugPrint('[LiveCameraScreen] Pushing ResultScreen');
        Navigator.of(context)
            .push(PageRouteBuilder(
          pageBuilder: (_, __, ___) => ResultScreen(
            imageBytes: bytes,
            result: full.result,
            allProbabilities: full.probabilities,
            detections: full.detections,
          ),
          transitionsBuilder: (_, anim, __, child) =>
              FadeTransition(opacity: anim, child: child),
        ))
            .then((_) async {
          if (_controller != null && _isInitialized) {
            await _controller!.startImageStream(_onCameraFrame);
          }
        });
      }
    } catch (e) {
      debugPrint('[LiveCameraScreen] Capture error: $e');
      if (_controller != null && _isInitialized) {
        await _controller!.startImageStream(_onCameraFrame);
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      controller.dispose();
      _controller = null;
      setState(() => _isInitialized = false);
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_isInitialized && _controller != null)
            CameraPreview(_controller!)
                .animate()
                .fadeIn(duration: 400.milliseconds)
          else
            Container(
                color: Colors.black,
                child: Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const CircularProgressIndicator(
                          color: Color(0xFF4CAF50), strokeWidth: 3)
                      .animate(onPlay: (c) => c.repeat())
                      .rotate(duration: 2.seconds),
                  const SizedBox(height: 16),
                  Text('Accessing Camera...',
                      style:
                          textTheme.bodySmall?.copyWith(color: Colors.white54)),
                ]))),
          if (_isInitialized)
            YoloBoxOverlay(
              detections: _detections,
              fit: BoxFit.cover,
              minConfidence: _confidenceThreshold,
            ),
          if (_isInitialized)
            _ScanningOverlay(color: _labelColor)
                .animate()
                .fadeIn(duration: 600.milliseconds),
          Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                  child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                      child: Row(children: [
                        _BlurButton(
                            icon: Icons.arrow_back_ios_new,
                            onTap: () => Navigator.pop(context)),
                        const Spacer(),
                        _BlurButton(
                            icon: _isFlashOn
                                ? Icons.flash_on_rounded
                                : Icons.flash_off_rounded,
                            onTap: _toggleFlash),
                        const SizedBox(width: 12),
                        Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                                color: Colors.black38,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: Colors.white12)),
                            child: Row(children: [
                              const Icon(Icons.lens, size: 8, color: Colors.red)
                                  .animate(onPlay: (c) => c.repeat())
                                  .fadeIn(duration: 500.milliseconds)
                                  .fadeOut(delay: 500.milliseconds),
                              const SizedBox(width: 8),
                              Text('LIVE',
                                  style: textTheme.labelSmall?.copyWith(
                                      color: Colors.white,
                                      letterSpacing: 1.2,
                                      fontWeight: FontWeight.bold)),
                            ])),
                        const SizedBox(width: 12),
                        _BlurButton(
                            icon: Icons.flip_camera_ios_outlined,
                            onTap: _toggleCamera),
                      ])))),
          if (_isInitialized)
            Positioned(
                top: 110,
                left: 0,
                right: 0,
                child: Center(
                    child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 24, vertical: 12),
                            decoration: BoxDecoration(
                                color: _labelColor.withValues(alpha: 0.8),
                                borderRadius: BorderRadius.circular(30),
                                boxShadow: [
                                  BoxShadow(
                                      color: _labelColor.withValues(alpha: 0.3),
                                      blurRadius: 20,
                                      spreadRadius: 2)
                                ]),
                            child: Text(_label,
                                style: textTheme.titleSmall?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800)))
                        .animate(key: ValueKey(_label))
                        .scale(
                            duration: 200.milliseconds,
                            begin: const Offset(0.9, 0.9),
                            curve: Curves.easeOutBack))),
          Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _BottomDashboard(
                  confidence: _confidence,
                  color: _labelColor,
                  onCapture: _captureAndAnalyze)),
        ],
      ),
    );
  }
}

class _BlurButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _BlurButton({required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
        onTap: onTap,
        child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: Colors.black45,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white10)),
            child: Icon(icon, color: Colors.white, size: 20)));
  }
}

class _BottomDashboard extends StatelessWidget {
  final double confidence;
  final Color color;
  final VoidCallback onCapture;
  const _BottomDashboard(
      {required this.confidence, required this.color, required this.onCapture});
  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 48),
        decoration: BoxDecoration(
            gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
              Colors.transparent,
              Colors.black.withValues(alpha: 0.7),
              Colors.black
            ])),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (confidence > 0)
            Column(children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('MATCH CONFIDENCE',
                    style: textTheme.labelSmall
                        ?.copyWith(color: Colors.white54, letterSpacing: 1)),
                Text('${(confidence * 100).toStringAsFixed(1)}%',
                    style: textTheme.labelLarge
                        ?.copyWith(color: color, fontWeight: FontWeight.w900)),
              ]),
              const SizedBox(height: 12),
              ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: LinearProgressIndicator(
                      value: confidence,
                      backgroundColor: Colors.white12,
                      valueColor: AlwaysStoppedAnimation<Color>(color),
                      minHeight: 8)),
              const SizedBox(height: 32),
            ]).animate().slideY(begin: 0.2, duration: 400.milliseconds),
          GestureDetector(
              onTap: onCapture,
              child: Stack(alignment: Alignment.center, children: [
                Container(
                    width: 84,
                    height: 84,
                    decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 4))),
                Container(
                    width: 68,
                    height: 68,
                    decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: color,
                        boxShadow: [
                          BoxShadow(
                              color: color.withValues(alpha: 0.4),
                              blurRadius: 15,
                              spreadRadius: 2)
                        ]),
                    child: const Icon(Icons.camera_alt,
                        color: Colors.white, size: 30)),
              ])),
          const SizedBox(height: 16),
          Text('HOLD TO SCAN • TAP TO ANALYZE',
              style: textTheme.labelSmall
                  ?.copyWith(color: Colors.white38, letterSpacing: 0.5)),
        ]));
  }
}

class _ScanningOverlay extends StatelessWidget {
  final Color color;
  const _ScanningOverlay({required this.color});
  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final frameSize = size.width * 0.75;
    final top = (size.height - frameSize) / 2 - 40;
    return Stack(children: [
      Positioned(
          top: top,
          left: (size.width - frameSize) / 2,
          child: SizedBox(
              width: frameSize,
              height: frameSize,
              child: CustomPaint(
                  size: Size(frameSize, frameSize),
                  painter: _CornerPainter(color: color)))),
      Positioned(
          top: top,
          left: (size.width - frameSize) / 2,
          child: Container(
                  width: frameSize,
                  height: 2,
                  decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [
                        color.withValues(alpha: 0),
                        color,
                        color.withValues(alpha: 0)
                      ]),
                      boxShadow: [
                        BoxShadow(
                            color: color.withValues(alpha: 0.6),
                            blurRadius: 10,
                            spreadRadius: 2)
                      ]))
              .animate(onPlay: (c) => c.repeat())
              .moveY(
                  begin: 0,
                  end: frameSize,
                  duration: 2.seconds,
                  curve: Curves.easeInOut)),
    ]);
  }
}

class _CornerPainter extends CustomPainter {
  final Color color;
  const _CornerPainter({required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    const len = 32.0;
    const r = 12.0;
    void drawCorner(double x, double y, double dx, double dy) {
      final path = Path();
      path.moveTo(x + dx * len, y);
      path.lineTo(x + dx * r, y);
      path.arcToPoint(Offset(x, y + dy * r),
          radius: const Radius.circular(r), clockwise: dy * dx < 0);
      path.lineTo(x, y + dy * len);
      canvas.drawPath(path, paint);
    }

    drawCorner(0, 0, 1, 1);
    drawCorner(size.width, 0, -1, 1);
    drawCorner(0, size.height, 1, -1);
    drawCorner(size.width, size.height, -1, -1);
  }

  @override
  bool shouldRepaint(_CornerPainter old) => old.color != color;
}
