import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:tflite_flutter/tflite_flutter.dart';

class InferenceEngine {
  final String modelPath;
  final int numClasses;
  final int? threads;

  Interpreter? _interpreter;
  Float32List? _outputBuffer;
  bool _isLoaded = false;
  Future<void>? _loadFuture;
  Future<void> _queue = Future.value();

  InferenceEngine({
    required this.modelPath,
    required this.numClasses,
    this.threads,
  });

  bool get isLoaded => _isLoaded;

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
      _outputBuffer = Float32List(numClasses);
      _isLoaded = true;
    } catch (e) {
      _loadFuture = null;
      rethrow;
    }
  }

  Future<T> runQueued<T>(
    T Function(Interpreter interpreter, Float32List output) action,
  ) {
    final future = _queue.then((_) => action(_interpreter!, _outputBuffer!));
    _queue = future.then((_) => null, onError: (_) => null);
    return future;
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _outputBuffer = null;
    _isLoaded = false;
    _loadFuture = null;
    _queue = Future.value();
  }
}
