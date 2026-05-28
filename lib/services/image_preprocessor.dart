import 'dart:isolate';
import 'dart:math' as math;
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
    final input = await fromBytesDetailed(bytes);
    return input.tensor;
  }

  Future<PreprocessedInput> fromBytesDetailed(Uint8List bytes) async {
    return compute(
      _preprocessImageBytesIsolate,
      _PreprocessBytesRequest(
        TransferableTypedData.fromList([bytes]),
        inputSize,
      ),
    );
  }

  Future<Float32List> fromCameraFrame(CameraFrame frame) async {
    final input = await fromCameraFrameDetailed(frame);
    return input.tensor;
  }

  Future<PreprocessedInput> fromCameraFrameDetailed(CameraFrame frame) async {
    return compute(
      _preprocessCameraFrameIsolate,
      _CameraPreprocessRequest.fromFrame(frame, inputSize),
    );
  }
}

@immutable
class PreprocessedInput {
  final Float32List tensor;
  final int sourceWidth;
  final int sourceHeight;
  final int inputSize;
  final int contentLeft;
  final int contentTop;
  final int contentWidth;
  final int contentHeight;

  const PreprocessedInput({
    required this.tensor,
    required this.sourceWidth,
    required this.sourceHeight,
    required this.inputSize,
    required this.contentLeft,
    required this.contentTop,
    required this.contentWidth,
    required this.contentHeight,
  });
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

PreprocessedInput _preprocessImageBytesIsolate(
    _PreprocessBytesRequest request) {
  final bytes = request.bytes.materialize().asUint8List();
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw Exception('Cannot decode image');
  }

  return _letterboxImageToFloat32(
    img.bakeOrientation(decoded),
    request.inputSize,
  );
}

PreprocessedInput _preprocessCameraFrameIsolate(
  _CameraPreprocessRequest request,
) {
  switch (request.format) {
    case CameraFrameFormat.bgra8888:
      return _bgraToLetterboxFloat32(
        bytes: request.plane0.materialize().asUint8List(),
        width: request.width,
        height: request.height,
        bytesPerRow: request.bytesPerRow0,
        inputSize: request.inputSize,
      );
    case CameraFrameFormat.yuv420:
      return _yuv420ToLetterboxFloat32(
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
      return _letterboxImageToFloat32(
        img.bakeOrientation(decoded),
        request.inputSize,
      );
  }
}

PreprocessedInput _letterboxImageToFloat32(img.Image source, int inputSize) {
  final layout = _letterboxLayout(source.width, source.height, inputSize);
  final resized = img.copyResize(
    source,
    width: layout.contentWidth,
    height: layout.contentHeight,
    interpolation: img.Interpolation.linear,
  );
  final buffer = _grayTensor(inputSize);

  for (var y = 0; y < resized.height; y++) {
    for (var x = 0; x < resized.width; x++) {
      final pixel = resized.getPixel(x, y);
      final dstIndex =
          (((layout.contentTop + y) * inputSize) + layout.contentLeft + x) * 3;
      buffer[dstIndex] = pixel.r / 255.0;
      buffer[dstIndex + 1] = pixel.g / 255.0;
      buffer[dstIndex + 2] = pixel.b / 255.0;
    }
  }

  return PreprocessedInput(
    tensor: buffer,
    sourceWidth: source.width,
    sourceHeight: source.height,
    inputSize: inputSize,
    contentLeft: layout.contentLeft,
    contentTop: layout.contentTop,
    contentWidth: layout.contentWidth,
    contentHeight: layout.contentHeight,
  );
}

PreprocessedInput _bgraToLetterboxFloat32({
  required Uint8List bytes,
  required int width,
  required int height,
  required int bytesPerRow,
  required int inputSize,
}) {
  final layout = _letterboxLayout(width, height, inputSize);
  final buffer = _grayTensor(inputSize);
  final xRatio = width / layout.contentWidth;
  final yRatio = height / layout.contentHeight;

  for (var y = 0; y < layout.contentHeight; y++) {
    final srcY = math.min((y * yRatio).floor(), height - 1);
    final rowOffset = srcY * bytesPerRow;
    for (var x = 0; x < layout.contentWidth; x++) {
      final srcX = math.min((x * xRatio).floor(), width - 1);
      final pixelIndex = rowOffset + (srcX * 4);
      final b = bytes[pixelIndex];
      final g = bytes[pixelIndex + 1];
      final r = bytes[pixelIndex + 2];
      final dstIndex =
          (((layout.contentTop + y) * inputSize) + layout.contentLeft + x) * 3;
      buffer[dstIndex] = r / 255.0;
      buffer[dstIndex + 1] = g / 255.0;
      buffer[dstIndex + 2] = b / 255.0;
    }
  }

  return PreprocessedInput(
    tensor: buffer,
    sourceWidth: width,
    sourceHeight: height,
    inputSize: inputSize,
    contentLeft: layout.contentLeft,
    contentTop: layout.contentTop,
    contentWidth: layout.contentWidth,
    contentHeight: layout.contentHeight,
  );
}

PreprocessedInput _yuv420ToLetterboxFloat32({
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
  final layout = _letterboxLayout(width, height, inputSize);
  final buffer = _grayTensor(inputSize);
  final xRatio = width / layout.contentWidth;
  final yRatio = height / layout.contentHeight;

  for (var y = 0; y < layout.contentHeight; y++) {
    final srcY = math.min((y * yRatio).floor(), height - 1);
    final yRowOffset = srcY * yRowStride;
    final uRowOffset = (srcY >> 1) * uRowStride;
    final vRowOffset = (srcY >> 1) * vRowStride;
    for (var x = 0; x < layout.contentWidth; x++) {
      final srcX = math.min((x * xRatio).floor(), width - 1);
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

      final dstIndex =
          (((layout.contentTop + y) * inputSize) + layout.contentLeft + x) * 3;
      buffer[dstIndex] = r / 255.0;
      buffer[dstIndex + 1] = g / 255.0;
      buffer[dstIndex + 2] = b / 255.0;
    }
  }

  return PreprocessedInput(
    tensor: buffer,
    sourceWidth: width,
    sourceHeight: height,
    inputSize: inputSize,
    contentLeft: layout.contentLeft,
    contentTop: layout.contentTop,
    contentWidth: layout.contentWidth,
    contentHeight: layout.contentHeight,
  );
}

Float32List _grayTensor(int inputSize) {
  final buffer = Float32List(inputSize * inputSize * 3);
  buffer.fillRange(0, buffer.length, 114.0 / 255.0);
  return buffer;
}

_LetterboxLayout _letterboxLayout(int width, int height, int inputSize) {
  final scale = math.min(inputSize / width, inputSize / height);
  final contentWidth = math.max(1, (width * scale).round());
  final contentHeight = math.max(1, (height * scale).round());
  return _LetterboxLayout(
    contentLeft: ((inputSize - contentWidth) / 2).round(),
    contentTop: ((inputSize - contentHeight) / 2).round(),
    contentWidth: contentWidth,
    contentHeight: contentHeight,
  );
}

class _LetterboxLayout {
  final int contentLeft;
  final int contentTop;
  final int contentWidth;
  final int contentHeight;

  const _LetterboxLayout({
    required this.contentLeft,
    required this.contentTop,
    required this.contentWidth,
    required this.contentHeight,
  });
}
