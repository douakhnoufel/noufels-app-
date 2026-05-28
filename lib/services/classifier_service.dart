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

class YoloDetection {
  final String label;
  final double confidence;
  final Rect box;
  final Color color;

  const YoloDetection({
    required this.label,
    required this.confidence,
    required this.box,
    required this.color,
  });
}

class FullInferenceResult {
  final DetectionResult result;
  final Map<String, double> probabilities;
  final List<YoloDetection> detections;

  const FullInferenceResult({
    required this.result,
    required this.probabilities,
    this.detections = const [],
  });
}

class ClassifierService {
  static const String _modelPath = 'assets/models/best_float32.tflite';
  static const int _defaultInputSize = 224;
  static const int _numClasses = 3;
  static const double _minDetectionConfidence = 0.05;

  static const List<String> _labels = [
    'Early Blight',
    'Healthy',
    'Late Blight',
  ];

  static const List<String> _severities = [
    'Moderate Risk',
    'No Disease',
    'High Risk',
  ];

  static const List<String> _descriptions = [
    'Early blight is caused by the fungus Alternaria solani. '
        'It appears as dark brown circular spots with concentric rings '
        '(target-board pattern), typically starting on older leaves.',
    'This leaf appears healthy with no visible signs of disease. '
        'Continue regular monitoring and preventive care practices.',
    'Late blight is caused by Phytophthora infestans. '
        'It produces irregular water-soaked lesions that rapidly turn '
        'brown-black. Highly destructive - responsible for the Irish Famine.',
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
    // Healthy
    [
      'Continue regular watering at soil level',
      'Monitor weekly for early signs of disease',
      'Maintain proper fertilization schedule',
      'Keep weeds controlled around plants',
      'Inspect undersides of leaves for pests',
    ],
    // Late blight
    [
      'URGENT: Remove ALL infected plants immediately',
      'Apply copper-based fungicide or metalaxyl',
      'Do NOT compost infected material - burn or bag it',
      'Monitor neighbouring plants twice daily',
      'Consult local agricultural extension for emergency help',
    ],
  ];

  static const List<Color> _colors = [
    Color(0xFFFF8C42), // orange - early blight
    Color(0xFF43A047), // green  - healthy
    Color(0xFFE53935), // red    - late blight
  ];

  ImagePreprocessor _preprocessor;
  final InferenceEngine _engine;
  int _inputSize;

  ClassifierService({
    ImagePreprocessor? preprocessor,
    InferenceEngine? engine,
  })  : _inputSize = _defaultInputSize,
        _preprocessor = preprocessor ??
            const ImagePreprocessor(inputSize: _defaultInputSize),
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
    debugPrint(
        '[ClassifierService] classifyBytes called with ${bytes.length} bytes');
    await _ensureModelLoaded();
    debugPrint('[ClassifierService] Model loaded, input size: $_inputSize');
    final input = await _preprocessor.fromBytesDetailed(bytes);
    debugPrint(
        '[ClassifierService] Image preprocessed: ${input.tensor.length} elements');
    final result = await _engine.runQueued(
      (interpreter, output) => _runInference(interpreter, output, input),
    );
    debugPrint(
        '[ClassifierService] Inference complete: ${result.result.label} (${result.result.confidence})');
    return result;
  }

  /// Run inference on camera frame without JPEG re-encoding
  Future<DetectionResult> classifyCameraFrame(CameraFrame frame) async {
    final full = await classifyCameraFrameFull(frame);
    return full.result;
  }

  Future<FullInferenceResult> classifyCameraFrameFull(CameraFrame frame) async {
    debugPrint('[ClassifierService] classifyCameraFrame called');
    await _ensureModelLoaded();
    final input = await _preprocessor.fromCameraFrameDetailed(frame);
    debugPrint(
        '[ClassifierService] Camera frame preprocessed: ${input.tensor.length} elements');
    final full = await _engine.runQueued(
      (interpreter, output) => _runInference(interpreter, output, input),
    );
    debugPrint(
        '[ClassifierService] Frame inference complete: ${full.result.label} (${full.result.confidence})');
    return full;
  }

  /// Single-pass file inference (result + probabilities)
  Future<FullInferenceResult> classify(File imageFile) async {
    await _ensureModelLoaded();
    final bytes = await imageFile.readAsBytes();
    final input = await _preprocessor.fromBytesDetailed(bytes);
    return _engine.runQueued(
      (interpreter, output) => _runInference(interpreter, output, input),
    );
  }

  FullInferenceResult _runInference(
    Interpreter interpreter,
    Object output,
    PreprocessedInput input,
  ) {
    try {
      final inputShape = _engine.inputShape;
      debugPrint(
          '[ClassifierService] Input shape: $inputShape, Input length: ${input.tensor.length}');

      // Run inference with raw bytes to avoid tflite_flutter resizing input to 1D.
      final inputBytes = input.tensor.buffer.asUint8List(
        input.tensor.offsetInBytes,
        input.tensor.lengthInBytes,
      );
      interpreter.run(inputBytes, output);
      debugPrint('[ClassifierService] Inference completed');

      // Extract output values from the wrapped list
      final outputValues = _flattenOutput(output);
      debugPrint(
        '[ClassifierService] Output shape: ${_engine.outputShape}, '
        'values: ${_summarizeValues(outputValues)}',
      );

      return parseModelOutputForTesting(
        outputValues,
        _engine.outputShape,
        input: input,
      );
    } catch (e, stackTrace) {
      debugPrint('[ClassifierService] Inference error: $e');
      debugPrintStack(stackTrace: stackTrace);
      rethrow;
    }
  }

  @visibleForTesting
  FullInferenceResult parseModelOutputForTesting(
    Object output,
    List<int> outputShape, {
    PreprocessedInput? input,
  }) {
    final outputValues =
        output is List<double> ? output : _flattenOutput(output);

    if (_isYoloNmsOutput(outputValues, outputShape)) {
      return _parseYoloNmsOutput(outputValues, outputShape, input);
    }

    if (_isRawYoloOutput(outputValues, outputShape)) {
      return _parseRawYoloOutput(outputValues, outputShape, input);
    }

    if (outputValues.length == _labels.length) {
      return _parseClassificationOutput(outputValues);
    }

    throw StateError(
      'Unsupported model output shape $outputShape with '
      '${outputValues.length} values. Expected classification output '
      '(${_labels.length} values) or YOLO detection output.',
    );
  }

  FullInferenceResult _parseClassificationOutput(List<double> outputValues) {
    var sum = 0.0;
    for (final value in outputValues) {
      sum += value;
    }

    debugPrint('[ClassifierService] Classification output sum: $sum');

    final List<double> probs;
    if ((sum - 1.0).abs() < 0.05) {
      probs = outputValues.map(_clampConfidence).toList();
      debugPrint('[ClassifierService] Using raw outputs as probabilities');
    } else {
      probs = _softmax(outputValues);
      debugPrint('[ClassifierService] Applied softmax to outputs');
    }

    return _buildResultFromScores(probs);
  }

  bool _isYoloNmsOutput(List<double> values, List<int> shape) {
    if (values.length <= _labels.length || values.length % 6 != 0) {
      return false;
    }
    if (shape.isEmpty) {
      return true;
    }
    return shape.contains(6);
  }

  FullInferenceResult _parseYoloNmsOutput(
    List<double> values,
    List<int> shape,
    PreprocessedInput? input,
  ) {
    final scores = List<double>.filled(_labels.length, 0.0);
    final detections = <YoloDetection>[];
    var bestClassIndex = _healthyClassIndex;
    var bestConfidence = -1.0;
    var validDetections = 0;

    for (final row in _yoloRows(values, shape, 6)) {
      final confidence = _clampConfidence(row[4]);
      final classIndex = row[5].round();

      if (confidence <= 0.0 ||
          classIndex < 0 ||
          classIndex >= _labels.length ||
          (row[5] - classIndex).abs() > 0.01) {
        continue;
      }

      validDetections++;
      if (confidence >= _minDetectionConfidence) {
        detections.add(
          _buildDetection(
            classIndex: classIndex,
            confidence: confidence,
            box: _boxFromYoloRow(row, input),
          ),
        );
      }
      if (confidence > scores[classIndex]) {
        scores[classIndex] = confidence;
      }
      if (confidence > bestConfidence) {
        bestConfidence = confidence;
        bestClassIndex = classIndex;
      }
    }

    debugPrint(
      '[ClassifierService] Parsed $validDetections YOLO NMS detections, '
      'scores: $scores',
    );

    if (validDetections == 0) {
      debugPrint(
          '[ClassifierService] No valid detections; returning healthy fallback');
      return _buildResultFromScores(scores,
          forcedBestIndex: _healthyClassIndex);
    }

    return _buildResultFromScores(
      scores,
      forcedBestIndex: bestClassIndex,
      detections: detections,
    );
  }

  bool _isRawYoloOutput(List<double> values, List<int> shape) {
    final rowSize = _labels.length + 4;
    if (values.length <= rowSize || values.length % rowSize != 0) {
      return false;
    }
    if (shape.isEmpty) {
      return true;
    }
    return shape.contains(rowSize);
  }

  FullInferenceResult _parseRawYoloOutput(
    List<double> values,
    List<int> shape,
    PreprocessedInput? input,
  ) {
    final rowSize = _labels.length + 4;
    final scores = List<double>.filled(_labels.length, 0.0);
    final detections = <YoloDetection>[];
    var bestClassIndex = _healthyClassIndex;
    var bestConfidence = -1.0;
    var validDetections = 0;

    for (final row in _yoloRows(values, shape, rowSize)) {
      var classIndex = 0;
      var confidence = row[4];
      for (var i = 1; i < _labels.length; i++) {
        if (row[4 + i] > confidence) {
          confidence = row[4 + i];
          classIndex = i;
        }
      }

      confidence = _clampConfidence(confidence);
      if (confidence <= 0.0) continue;

      validDetections++;
      if (confidence >= _minDetectionConfidence) {
        detections.add(
          _buildDetection(
            classIndex: classIndex,
            confidence: confidence,
            box: _boxFromYoloRow(row, input, isCenterBox: true),
          ),
        );
      }
      if (confidence > scores[classIndex]) {
        scores[classIndex] = confidence;
      }
      if (confidence > bestConfidence) {
        bestConfidence = confidence;
        bestClassIndex = classIndex;
      }
    }

    debugPrint(
      '[ClassifierService] Parsed $validDetections raw YOLO rows, '
      'scores: $scores',
    );

    if (validDetections == 0) {
      return _buildResultFromScores(scores,
          forcedBestIndex: _healthyClassIndex);
    }

    return _buildResultFromScores(
      scores,
      forcedBestIndex: bestClassIndex,
      detections: detections,
    );
  }

  Iterable<List<double>> _yoloRows(
    List<double> values,
    List<int> shape,
    int rowSize,
  ) sync* {
    if (_isChannelsFirst(shape, rowSize)) {
      final rowCount = shape.last;
      final batchOffset = values.length - (rowSize * rowCount);
      for (var rowIndex = 0; rowIndex < rowCount; rowIndex++) {
        yield List<double>.generate(
          rowSize,
          (channel) => values[batchOffset + (channel * rowCount) + rowIndex],
          growable: false,
        );
      }
      return;
    }

    for (var offset = 0; offset + rowSize <= values.length; offset += rowSize) {
      yield values.sublist(offset, offset + rowSize);
    }
  }

  bool _isChannelsFirst(List<int> shape, int rowSize) {
    if (shape.length < 2 || !shape.contains(rowSize)) {
      return false;
    }
    return shape.length >= 3 && shape[shape.length - 2] == rowSize;
  }

  FullInferenceResult _buildResultFromScores(
    List<double> scores, {
    int? forcedBestIndex,
    List<YoloDetection> detections = const [],
  }) {
    final probs = List<double>.generate(
      _labels.length,
      (index) => index < scores.length ? _clampConfidence(scores[index]) : 0.0,
      growable: false,
    );

    var bestIdx = forcedBestIndex ?? 0;
    for (var i = 1; i < probs.length; i++) {
      if (probs[i] > probs[bestIdx]) {
        bestIdx = i;
      }
    }

    debugPrint(
      '[ClassifierService] Best index: $bestIdx, '
      'Label: ${_labels[bestIdx]}, Confidence: ${probs[bestIdx]}',
    );

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
      detections: detections,
    );
  }

  YoloDetection _buildDetection({
    required int classIndex,
    required double confidence,
    required Rect box,
  }) {
    return YoloDetection(
      label: _labels[classIndex],
      confidence: confidence,
      box: box,
      color: _colors[classIndex],
    );
  }

  int get _healthyClassIndex => _labels.indexOf('Healthy');

  double _clampConfidence(double value) {
    if (value.isNaN || value.isInfinite) return 0.0;
    return value.clamp(0.0, 1.0).toDouble();
  }

  Rect _boxFromYoloRow(
    List<double> row,
    PreprocessedInput? input, {
    bool isCenterBox = false,
  }) {
    var x1 = row[0];
    var y1 = row[1];
    var x2 = row[2];
    var y2 = row[3];

    if (isCenterBox) {
      final centerX = row[0];
      final centerY = row[1];
      final width = row[2].abs();
      final height = row[3].abs();
      x1 = centerX - (width / 2);
      y1 = centerY - (height / 2);
      x2 = centerX + (width / 2);
      y2 = centerY + (height / 2);
    }

    final left = min(x1, x2);
    final top = min(y1, y2);
    final right = max(x1, x2);
    final bottom = max(y1, y2);
    final maxCoord = [left, top, right, bottom].reduce(max);
    final inputSize = input?.inputSize.toDouble() ?? _inputSize.toDouble();
    final coordScale = maxCoord <= 1.5 ? inputSize : 1.0;

    var inputLeft = left * coordScale;
    var inputTop = top * coordScale;
    var inputRight = right * coordScale;
    var inputBottom = bottom * coordScale;

    if (input != null) {
      inputLeft = (inputLeft - input.contentLeft) / input.contentWidth;
      inputRight = (inputRight - input.contentLeft) / input.contentWidth;
      inputTop = (inputTop - input.contentTop) / input.contentHeight;
      inputBottom = (inputBottom - input.contentTop) / input.contentHeight;
    } else {
      inputLeft /= inputSize;
      inputRight /= inputSize;
      inputTop /= inputSize;
      inputBottom /= inputSize;
    }

    return Rect.fromLTRB(
      inputLeft.clamp(0.0, 1.0).toDouble(),
      inputTop.clamp(0.0, 1.0).toDouble(),
      inputRight.clamp(0.0, 1.0).toDouble(),
      inputBottom.clamp(0.0, 1.0).toDouble(),
    );
  }

  String _summarizeValues(List<double> values) {
    final preview = values.take(12).map((value) => value.toStringAsFixed(4));
    final suffix = values.length > 12 ? ', ...' : '';
    return '[${preview.join(', ')}$suffix] (${values.length} total)';
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
    final values = <double>[];

    void collect(Object? value) {
      if (value is num) {
        values.add(value.toDouble());
        return;
      }
      if (value is List) {
        for (final item in value) {
          collect(item);
        }
        return;
      }
      if (value != null) {
        throw StateError(
            'Unsupported output value type: ${value.runtimeType}.');
      }
    }

    collect(output);
    if (values.isEmpty) {
      throw StateError('Model output buffer is empty.');
    }
    return values;
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
