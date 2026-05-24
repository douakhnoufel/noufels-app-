import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

enum CameraFrameFormat { yuv420, bgra8888, jpeg }

@immutable
class CameraFrame {
  final int width;
  final int height;
  final CameraFrameFormat format;
  final Uint8List plane0;
  final Uint8List? plane1;
  final Uint8List? plane2;
  final int bytesPerRow0;
  final int bytesPerRow1;
  final int bytesPerRow2;
  final int bytesPerPixel1;
  final int bytesPerPixel2;

  const CameraFrame._({
    required this.width,
    required this.height,
    required this.format,
    required this.plane0,
    this.plane1,
    this.plane2,
    this.bytesPerRow0 = 0,
    this.bytesPerRow1 = 0,
    this.bytesPerRow2 = 0,
    this.bytesPerPixel1 = 0,
    this.bytesPerPixel2 = 0,
  });

  factory CameraFrame.jpeg({
    required int width,
    required int height,
    required Uint8List bytes,
  }) {
    return CameraFrame._(
      width: width,
      height: height,
      format: CameraFrameFormat.jpeg,
      plane0: bytes,
    );
  }

  factory CameraFrame.bgra8888({
    required int width,
    required int height,
    required Uint8List bytes,
    required int bytesPerRow,
  }) {
    return CameraFrame._(
      width: width,
      height: height,
      format: CameraFrameFormat.bgra8888,
      plane0: bytes,
      bytesPerRow0: bytesPerRow,
    );
  }

  factory CameraFrame.yuv420({
    required int width,
    required int height,
    required Uint8List yPlane,
    required Uint8List uPlane,
    required Uint8List vPlane,
    required int yRowStride,
    required int uRowStride,
    required int vRowStride,
    required int uPixelStride,
    required int vPixelStride,
  }) {
    return CameraFrame._(
      width: width,
      height: height,
      format: CameraFrameFormat.yuv420,
      plane0: yPlane,
      plane1: uPlane,
      plane2: vPlane,
      bytesPerRow0: yRowStride,
      bytesPerRow1: uRowStride,
      bytesPerRow2: vRowStride,
      bytesPerPixel1: uPixelStride,
      bytesPerPixel2: vPixelStride,
    );
  }
}

class ImagePreprocessor {
  final int inputSize;
  const ImagePreprocessor({required this.inputSize});

  Future<Float32List> fromBytes(Uint8List bytes) async {
    return compute(
      _preprocessImageBytesIsolate,
      _PreprocessBytesRequest(
        TransferableTypedData.fromList([bytes]),
        inputSize,
      ),
    );
  }

  Future<Float32List> fromCameraFrame(CameraFrame frame) async {
    return compute(
      _preprocessCameraFrameIsolate,
      _CameraPreprocessRequest.fromFrame(frame, inputSize),
    );
  }
}

@immutable
class _PreprocessBytesRequest {
  final TransferableTypedData bytes;
  final int inputSize;
  const _PreprocessBytesRequest(this.bytes, this.inputSize);
}

@immutable
class _CameraPreprocessRequest {
  final int width;
  final int height;
  final int inputSize;
  final CameraFrameFormat format;
  final TransferableTypedData plane0;
  final TransferableTypedData? plane1;
  final TransferableTypedData? plane2;
  final int bytesPerRow0;
  final int bytesPerRow1;
  final int bytesPerRow2;
  final int bytesPerPixel1;
  final int bytesPerPixel2;

  const _CameraPreprocessRequest({
    required this.width,
    required this.height,
    required this.inputSize,
    required this.format,
    required this.plane0,
    this.plane1,
    this.plane2,
    required this.bytesPerRow0,
    required this.bytesPerRow1,
    required this.bytesPerRow2,
    required this.bytesPerPixel1,
    required this.bytesPerPixel2,
  });

  factory _CameraPreprocessRequest.fromFrame(
    CameraFrame frame,
    int inputSize,
  ) {
    return _CameraPreprocessRequest(
      width: frame.width,
      height: frame.height,
      inputSize: inputSize,
      format: frame.format,
      plane0: TransferableTypedData.fromList([frame.plane0]),
      plane1: frame.plane1 == null
          ? null
          : TransferableTypedData.fromList([frame.plane1!]),
      plane2: frame.plane2 == null
          ? null
          : TransferableTypedData.fromList([frame.plane2!]),
      bytesPerRow0: frame.bytesPerRow0,
      bytesPerRow1: frame.bytesPerRow1,
      bytesPerRow2: frame.bytesPerRow2,
      bytesPerPixel1: frame.bytesPerPixel1,
      bytesPerPixel2: frame.bytesPerPixel2,
    );
  }
}

Float32List _preprocessImageBytesIsolate(_PreprocessBytesRequest request) {
  final bytes = request.bytes.materialize().asUint8List();
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw Exception('Cannot decode image');
  }

  final resized = img.copyResize(
    decoded,
    width: request.inputSize,
    height: request.inputSize,
  );
  return _imageToFloat32(resized);
}

Float32List _preprocessCameraFrameIsolate(_CameraPreprocessRequest request) {
  switch (request.format) {
    case CameraFrameFormat.bgra8888:
      return _bgraToFloat32(
        bytes: request.plane0.materialize().asUint8List(),
        width: request.width,
        height: request.height,
        bytesPerRow: request.bytesPerRow0,
        inputSize: request.inputSize,
      );
    case CameraFrameFormat.yuv420:
      return _yuv420ToFloat32(
        yPlane: request.plane0.materialize().asUint8List(),
        uPlane: request.plane1!.materialize().asUint8List(),
        vPlane: request.plane2!.materialize().asUint8List(),
        width: request.width,
        height: request.height,
        yRowStride: request.bytesPerRow0,
        uRowStride: request.bytesPerRow1,
        vRowStride: request.bytesPerRow2,
        uPixelStride: request.bytesPerPixel1,
        vPixelStride: request.bytesPerPixel2,
        inputSize: request.inputSize,
      );
    case CameraFrameFormat.jpeg:
      final bytes = request.plane0.materialize().asUint8List();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) {
        throw Exception('Cannot decode JPEG frame');
      }
      final resized = img.copyResize(
        decoded,
        width: request.inputSize,
        height: request.inputSize,
      );
      return _imageToFloat32(resized);
  }
}

Float32List _imageToFloat32(img.Image resized) {
  final buffer = Float32List(resized.width * resized.height * 3);
  var index = 0;
  for (var y = 0; y < resized.height; y++) {
    for (var x = 0; x < resized.width; x++) {
      final pixel = resized.getPixel(x, y);
      buffer[index++] = pixel.r / 255.0;
      buffer[index++] = pixel.g / 255.0;
      buffer[index++] = pixel.b / 255.0;
    }
  }
  return buffer;
}

Float32List _bgraToFloat32({
  required Uint8List bytes,
  required int width,
  required int height,
  required int bytesPerRow,
  required int inputSize,
}) {
  final buffer = Float32List(inputSize * inputSize * 3);
  final xRatio = width / inputSize;
  final yRatio = height / inputSize;
  var index = 0;
  for (var y = 0; y < inputSize; y++) {
    final srcY = (y * yRatio).floor();
    final rowOffset = srcY * bytesPerRow;
    for (var x = 0; x < inputSize; x++) {
      final srcX = (x * xRatio).floor();
      final pixelIndex = rowOffset + (srcX * 4);
      final b = bytes[pixelIndex];
      final g = bytes[pixelIndex + 1];
      final r = bytes[pixelIndex + 2];
      buffer[index++] = r / 255.0;
      buffer[index++] = g / 255.0;
      buffer[index++] = b / 255.0;
    }
  }
  return buffer;
}

Float32List _yuv420ToFloat32({
  required Uint8List yPlane,
  required Uint8List uPlane,
  required Uint8List vPlane,
  required int width,
  required int height,
  required int yRowStride,
  required int uRowStride,
  required int vRowStride,
  required int uPixelStride,
  required int vPixelStride,
  required int inputSize,
}) {
  final buffer = Float32List(inputSize * inputSize * 3);
  final xRatio = width / inputSize;
  final yRatio = height / inputSize;
  var index = 0;
  for (var y = 0; y < inputSize; y++) {
    final srcY = (y * yRatio).floor();
    final yRowOffset = srcY * yRowStride;
    final uRowOffset = (srcY >> 1) * uRowStride;
    final vRowOffset = (srcY >> 1) * vRowStride;
    for (var x = 0; x < inputSize; x++) {
      final srcX = (x * xRatio).floor();
      final yIndex = yRowOffset + srcX;
      final uIndex = uRowOffset + (srcX >> 1) * uPixelStride;
      final vIndex = vRowOffset + (srcX >> 1) * vPixelStride;

      final yValue = yPlane[yIndex].toDouble();
      final uValue = uPlane[uIndex].toDouble() - 128.0;
      final vValue = vPlane[vIndex].toDouble() - 128.0;

      var r = yValue + 1.402 * vValue;
      var g = yValue - 0.344136 * uValue - 0.714136 * vValue;
      var b = yValue + 1.772 * uValue;

      if (r < 0) r = 0;
      if (g < 0) g = 0;
      if (b < 0) b = 0;
      if (r > 255) r = 255;
      if (g > 255) g = 255;
      if (b > 255) b = 255;

      buffer[index++] = r / 255.0;
      buffer[index++] = g / 255.0;
      buffer[index++] = b / 255.0;
    }
  }
  return buffer;
}
