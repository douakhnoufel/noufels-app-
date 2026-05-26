import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:tflite_flutter/tflite_flutter.dart';

class InferenceEngine {
  final String modelPath;
  final int numClasses;
  final int? threads;

  Interpreter? _interpreter;
  List<int>? _inputShape;
  List<int>? _outputShape;
  Object? _outputBuffer;
  bool _isLoaded = false;
  Future<void>? _loadFuture;
  Future<void> _queue = Future.value();

  InferenceEngine({
    required this.modelPath,
    required this.numClasses,
    this.threads,
  });

  bool get isLoaded => _isLoaded;
  List<int> get inputShape => _inputShape ?? const [];
  List<int> get outputShape => _outputShape ?? const [];

  int get inputSize {
    final shape = _inputShape;
    if (shape == null || shape.isEmpty) {
      throw StateError('Model input shape is unavailable.');
    }
    if (shape.length == 4) {
      if (shape[1] != shape[2]) {
        throw StateError('Non-square input tensor shape: $shape');
      }
      return shape[1];
    }
    if (shape.length == 3) {
      if (shape[0] != shape[1]) {
        throw StateError('Non-square input tensor shape: $shape');
      }
      return shape[0];
    }
    throw StateError('Unsupported input tensor shape: $shape');
  }

  Future<void> load() async {
    if (_isLoaded) return;
    _loadFuture ??= _loadInternal();
    return _loadFuture!;
  }

  Future<void> _loadInternal() async {
    try {
      final options = InterpreterOptions()
        ..threads = threads ?? max(1, min(4, Platform.numberOfProcessors - 1));
      _interpreter = await Interpreter.fromAsset(
        modelPath,
        options: options,
      );
      _inputShape = _interpreter!.getInputTensor(0).shape;
      _outputShape = _interpreter!.getOutputTensor(0).shape;
      _outputBuffer = _buildOutputBuffer(_outputShape!);
      _isLoaded = true;
    } catch (e) {
      _loadFuture = null;
      rethrow;
    }
  }

  Future<T> runQueued<T>(
    T Function(Interpreter interpreter, Object output) action,
  ) {
    if (!_isLoaded || _interpreter == null || _outputBuffer == null) {
      throw StateError('Interpreter not loaded.');
    }
    final outputBuffer = _outputBuffer!;
    final future = _queue.then((_) => action(_interpreter!, outputBuffer));
    _queue = future.then((_) => null, onError: (_) => null);
    return future;
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _outputBuffer = null;
    _inputShape = null;
    _outputShape = null;
    _isLoaded = false;
    _loadFuture = null;
    _queue = Future.value();
  }

  Object _buildOutputBuffer(List<int> shape) {
    if (shape.isEmpty) {
      throw StateError('Output tensor shape is empty.');
    }
    if (shape.any((dim) => dim <= 0)) {
      throw StateError('Output tensor has dynamic or invalid shape: $shape');
    }
    final elementCount = shape.fold(1, (acc, dim) => acc * dim);
    if (elementCount <= 0) {
      throw StateError('Output tensor has invalid element count: $shape');
    }
    // Create output buffer - TFLite interpreter expects it wrapped in a List
    // if it's multi-dimensional, but we wrap it for consistency
    final buffer = List<double>.filled(elementCount, 0.0);
    return [buffer]; // Wrap in List for TFLite interpreter.run()
  }
}
