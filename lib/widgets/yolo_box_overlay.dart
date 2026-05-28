import 'package:flutter/material.dart';
import '../services/classifier_service.dart';

class YoloBoxOverlay extends StatelessWidget {
  final List<YoloDetection> detections;
  final Size? sourceSize;
  final BoxFit fit;
  final double minConfidence;
  final bool showLabels;

  const YoloBoxOverlay({
    super.key,
    required this.detections,
    this.sourceSize,
    this.fit = BoxFit.cover,
    this.minConfidence = 0.10,
    this.showLabels = true,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _YoloBoxPainter(
          detections: detections,
          sourceSize: sourceSize,
          fit: fit,
          minConfidence: minConfidence,
          showLabels: showLabels,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _YoloBoxPainter extends CustomPainter {
  final List<YoloDetection> detections;
  final Size? sourceSize;
  final BoxFit fit;
  final double minConfidence;
  final bool showLabels;

  const _YoloBoxPainter({
    required this.detections,
    required this.sourceSize,
    required this.fit,
    required this.minConfidence,
    required this.showLabels,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (detections.isEmpty || size.isEmpty) return;

    final imageSize = sourceSize ?? size;
    final fitted = applyBoxFit(fit, imageSize, size);
    final outputRect = Alignment.center.inscribe(
      fitted.destination,
      Offset.zero & size,
    );

    canvas.save();
    canvas.clipRect(Offset.zero & size);

    final sorted = detections
        .where((detection) => detection.confidence >= minConfidence)
        .toList()
      ..sort((a, b) => a.confidence.compareTo(b.confidence));

    for (final detection in sorted) {
      final rect = Rect.fromLTRB(
        outputRect.left + detection.box.left * outputRect.width,
        outputRect.top + detection.box.top * outputRect.height,
        outputRect.left + detection.box.right * outputRect.width,
        outputRect.top + detection.box.bottom * outputRect.height,
      );
      if (rect.width <= 2 || rect.height <= 2) continue;

      final paint = Paint()
        ..color = detection.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0;
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(8)),
        paint,
      );

      final glowPaint = Paint()
        ..color = detection.color.withValues(alpha: 0.18)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7.0;
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect.inflate(1), const Radius.circular(10)),
        glowPaint,
      );

      if (!showLabels) continue;

      final label =
          '${detection.label} ${(detection.confidence * 100).toStringAsFixed(0)}%';
      final textPainter = TextPainter(
        text: TextSpan(
          text: label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout(maxWidth: size.width * 0.7);

      final labelTop = rect.top - textPainter.height - 8 < 0
          ? rect.top + 6
          : rect.top - textPainter.height - 8;
      final labelLeft = rect.left.clamp(
        0.0,
        (size.width - textPainter.width - 12).clamp(0.0, size.width),
      );
      final labelRect = Rect.fromLTWH(
        labelLeft,
        labelTop,
        textPainter.width + 12,
        textPainter.height + 8,
      );

      final labelPaint = Paint()
        ..color = detection.color.withValues(alpha: 0.92);
      canvas.drawRRect(
        RRect.fromRectAndRadius(labelRect, const Radius.circular(8)),
        labelPaint,
      );
      textPainter.paint(
        canvas,
        Offset(labelRect.left + 6, labelRect.top + 4),
      );
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(_YoloBoxPainter oldDelegate) {
    return oldDelegate.detections != detections ||
        oldDelegate.sourceSize != sourceSize ||
        oldDelegate.fit != fit ||
        oldDelegate.minConfidence != minConfidence ||
        oldDelegate.showLabels != showLabels;
  }
}
