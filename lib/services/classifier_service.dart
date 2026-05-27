import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'image_preprocessor.dart';
import 'inference_engine.dart';

/// Result of a single inference
class DetectionResult {
  final String label;
  final double confidence;
  final String severity;
  final String description;
  final List<String> recommendations;
  final Color color;

  const DetectionResult({
    required this.label,
    required this.confidence,
    required this.severity,
    required this.description,
    required this.recommendations,
    required this.color,
  });
}

class FullInferenceResult {
  final DetectionResult result;
  final Map<String, double> probabilities;

  const FullInferenceResult({
    required this.result,
    required this.probabilities,
  });
}

class ClassifierService {
  static const String _modelPath =
      'assets/models/best_float32.tflite';
  static const int _defaultInputSize = 224;
  static const int _numClasses = 3;

  static const List<String> _labels = [
    'Early Blight',
    'Late Blight',
    'Healthy',
  ];

  static const List<String> _severities = [
    'Moderate Risk',
    'High Risk',
    'No Disease',
  ];

  static const List<String> _descriptions = [
    'Early blight is caused by the fungus Alternaria solani. '
        'It appears as dark brown circular spots with concentric rings '
        '(target-board pattern), typically starting on older leaves.',
    'Late blight is caused by Phytophthora infestans. '
        'It produces irregular water-soaked lesions that rapidly turn '
        'brown-black. Highly destructive — responsible for the Irish Famine.',
    'This leaf appears healthy with no visible signs of disease. '
        'Continue regular monitoring and preventive care practices.',
  ];

  static const List<List<String>> _recommendations = [
    // Early blight
    [
      'Remove and destroy infected leaves immediately',
      'Apply fungicide: chlorothalonil or mancozeb',
      'Avoid overhead irrigation; water at base',
      'Ensure adequate plant spacing for airflow',
      'Rotate crops — avoid planting potatoes in same spot',
    ],
    // Late blight
    [
      'URGENT: Remove ALL infected plants immediately',
      'Apply copper-based fungicide or metalaxyl',
      'Do NOT compost infected material — burn or bag it',
      'Monitor neighbouring plants twice daily',
      'Consult local agricultural extension for emergency help',
    ],
    // Healthy
    [
      'Continue regular watering at soil level',
      'Monitor weekly for early signs of disease',
      'Maintain proper fertilization schedule',
      'Keep weeds controlled around plants',
      'Inspect undersides of leaves for pests',
    ],
  ];

  static const List<Color> _colors = [
    Color(0xFFFF8C42), // orange - early blight
    Color(0xFFE53935), // red    - late blight
    Color(0xFF43A047), // green  - healthy
  ];

  ImagePreprocessor _preprocessor;
  final InferenceEngine _engine;
  int _inputSize;

  ClassifierService({
    ImagePreprocessor? preprocessor,
    InferenceEngine? engine,
  })  : _inputSize = _defaultInputSize,
        _preprocessor =
            preprocessor ?? const ImagePreprocessor(inputSize: _defaultInputSize),
        _engine = engine ??
            InferenceEngine(
              modelPath: _modelPath,
              numClasses: _numClasses,
            );

  Future<void> loadModel() => _ensureModelLoaded();

  bool get isLoaded => _engine.isLoaded;

  Future<void> _ensureModelLoaded() async {
    await _engine.load();
    final resolvedInputSize = _engine.inputSize;
    if (resolvedInputSize != _inputSize) {
      _inputSize = resolvedInputSize;
      _preprocessor = ImagePreprocessor(inputSize: _inputSize);
    }
  }

  /// Run inference on a File
  Future<DetectionResult> classifyImage(File imageFile) async {
    final full = await classify(imageFile);
    return full.result;
  }

  /// Run inference on encoded image bytes (jpg/png)
  Future<FullInferenceResult> classifyBytes(Uint8List bytes) async {
    debugPrint('[ClassifierService] classifyBytes called with ${bytes.length} bytes');
    await _ensureModelLoaded();
    debugPrint('[ClassifierService] Model loaded, input size: $_inputSize');
    final input = await _preprocessor.fromBytes(bytes);
    debugPrint('[ClassifierService] Image preprocessed: ${input.length} elements');
    final result = await _engine.runQueued(
      (interpreter, output) => _runInference(interpreter, output, input),
    );
    debugPrint('[ClassifierService] Inference complete: ${result.result.label} (${result.result.confidence})');
    return result;
  }

  /// Run inference on camera frame without JPEG re-encoding
  Future<DetectionResult> classifyCameraFrame(CameraFrame frame) async {
    debugPrint('[ClassifierService] classifyCameraFrame called');
    await _ensureModelLoaded();
    final input = await _preprocessor.fromCameraFrame(frame);
    debugPrint('[ClassifierService] Camera frame preprocessed: ${input.length} elements');
    final full = await _engine.runQueued(
      (interpreter, output) => _runInference(interpreter, output, input),
    );
    debugPrint('[ClassifierService] Frame inference complete: ${full.result.label} (${full.result.confidence})');
    return full.result;
  }

  /// Single-pass file inference (result + probabilities)
  Future<FullInferenceResult> classify(File imageFile) async {
    await _ensureModelLoaded();
    final bytes = await imageFile.readAsBytes();
    final input = await _preprocessor.fromBytes(bytes);
    return _engine.runQueued(
      (interpreter, output) => _runInference(interpreter, output, input),
    );
  }

  FullInferenceResult _runInference(
    Interpreter interpreter,
    Object output,
    Float32List input,
  ) {
    try {
      final inputShape = _engine.inputShape;
      debugPrint('[ClassifierService] Input shape: $inputShape, Input length: ${input.length}');
      
      // Run inference with raw bytes to avoid tflite_flutter resizing input to 1D.
      final inputBytes = input.buffer.asUint8List(
        input.offsetInBytes,
        input.lengthInBytes,
      );
      interpreter.run(inputBytes, output);
      debugPrint('[ClassifierService] Inference completed');

      // Extract output values from the wrapped list
      final outputValues = _flattenOutput(output);
      debugPrint('[ClassifierService] Output flattened: $outputValues');
      
      if (outputValues.length != _labels.length) {
        throw StateError(
          'Model output size mismatch. Expected ${_labels.length} values but got ${outputValues.length}.',
        );
      }

      // If the model already outputs probabilities (sums to ~1.0), use them directly.
      // Otherwise, apply softmax to the logits.
      double sum = 0;
      for (int i = 0; i < outputValues.length; i++) {
        sum += outputValues[i];
      }

      debugPrint('[ClassifierService] Output sum: $sum');

      final List<double> probs;
      if ((sum - 1.0).abs() < 0.05) {
        probs = outputValues;
        debugPrint('[ClassifierService] Using raw outputs as probabilities');
      } else {
        probs = _softmax(outputValues);
        debugPrint('[ClassifierService] Applied softmax to outputs');
      }

      debugPrint('[ClassifierService] Probabilities: $probs');

      var bestIdx = 0;
      for (var i = 1; i < probs.length; i++) {
        if (probs[i] > probs[bestIdx]) {
          bestIdx = i;
        }
      }

      debugPrint('[ClassifierService] Best index: $bestIdx, Label: ${_labels[bestIdx]}, Confidence: ${probs[bestIdx]}');

      final result = DetectionResult(
        label: _labels[bestIdx],
        confidence: probs[bestIdx],
        severity: _severities[bestIdx],
        description: _descriptions[bestIdx],
        recommendations: _recommendations[bestIdx],
        color: _colors[bestIdx],
      );

      final probabilities = <String, double>{};
      for (var i = 0; i < _labels.length; i++) {
        probabilities[_labels[i]] = probs[i];
      }

      return FullInferenceResult(
        result: result,
        probabilities: probabilities,
      );
    } catch (e, stackTrace) {
      debugPrint('[ClassifierService] Inference error: $e');
      debugPrintStack(stackTrace: stackTrace);
      rethrow;
    }
  }

  List<double> _softmax(List<double> scores) {
    final maxScore = scores.reduce(max);
    final expScores = List<double>.filled(scores.length, 0.0);
    var sum = 0.0;
    for (var i = 0; i < scores.length; i++) {
      final expScore = exp(scores[i] - maxScore);
      expScores[i] = expScore;
      sum += expScore;
    }
    for (var i = 0; i < expScores.length; i++) {
      expScores[i] = expScores[i] / sum;
    }
    return expScores;
  }

  List<double> _flattenOutput(Object output) {
    if (output is List<double>) {
      if (output.isEmpty) {
        throw StateError('Model output buffer is empty.');
      }
      return output;
    }
    if (output is List) {
      if (output.isEmpty) {
        throw StateError('Model output buffer is empty.');
      }
      final first = output[0];
      if (first is List<double>) {
        return first;
      }
      if (first is double) {
        return output.cast<double>();
      }
      final values = output.flatten<num>();
      if (values.isEmpty) {
        throw StateError('Model output buffer is empty.');
      }
      return values.map((value) => value.toDouble()).toList();
    }
    throw StateError('Unsupported output buffer type: ${output.runtimeType}.');
  }

  String getSeverityFor(String label) {
    final idx = _labels.indexOf(label);
    return idx != -1 ? _severities[idx] : 'Unknown';
  }

  String getDescriptionFor(String label) {
    final idx = _labels.indexOf(label);
    return idx != -1 ? _descriptions[idx] : 'No description available.';
  }

  List<String> getRecommendationsFor(String label) {
    final idx = _labels.indexOf(label);
    return idx != -1 ? _recommendations[idx] : [];
  }

  Color getColorFor(String label) {
    final idx = _labels.indexOf(label);
    return idx != -1 ? _colors[idx] : Colors.grey;
  }

  void dispose() {
    _engine.dispose();
  }
}
