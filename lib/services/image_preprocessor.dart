import 'dart:typed_data';
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;

class CameraFrameCrops {
  const CameraFrameCrops({
    required this.context,
    required this.tight,
    required this.orientedLandmarks,
  });

  final img.Image context;
  final img.Image tight;
  final List<Offset> orientedLandmarks;
}

class ImagePreprocessor {
  const ImagePreprocessor._();

  static int effectivePortraitRotation({
    required int frameWidth,
    required int frameHeight,
    required int requestedRotationDegrees,
  }) {
    final requested = ((requestedRotationDegrees % 360) + 360) % 360;
    if (frameWidth == frameHeight) return requested;
    final swapsDimensions = requested == 90 || requested == 270;
    final outputWidth = swapsDimensions ? frameHeight : frameWidth;
    final outputHeight = swapsDimensions ? frameWidth : frameHeight;
    if (outputHeight >= outputWidth) return requested;

    // Some CameraX/OEM combinations already deliver portrait-oriented buffers.
    return frameHeight > frameWidth ? 0 : requested;
  }

  static img.Image decodeFileBytes(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw const FormatException('Format gambar tidak dapat dibaca.');
    }
    return img.bakeOrientation(decoded);
  }

  static img.Image cameraImageToGray(
    CameraImage cameraImage, {
    required int rotationDegrees,
    required bool mirrorHorizontally,
    Rect? normalizedCrop,
  }) {
    final sensorGray = switch (cameraImage.format.group) {
      ImageFormatGroup.yuv420 ||
      ImageFormatGroup.nv21 => _luminancePlaneToImage(cameraImage),
      ImageFormatGroup.bgra8888 => _bgraToGray(cameraImage),
      _ => throw UnsupportedError(
        'Format kamera ${cameraImage.format.group.name} belum didukung.',
      ),
    };

    return cropAndOrientSensorImage(
      sensorGray,
      rotationDegrees: rotationDegrees,
      mirrorHorizontally: mirrorHorizontally,
      normalizedCrop: normalizedCrop,
    );
  }

  static CameraFrameCrops cameraImageToGrayCrops(
    CameraImage cameraImage, {
    required int rotationDegrees,
    required bool mirrorHorizontally,
    required List<Offset> normalizedLandmarks,
  }) {
    // MediaPipe applies ImageProcessingOptions.rotationDegrees before it
    // returns normalized landmarks. Rotating these points again moves the crop
    // away from the hand. The front-camera mirror is the only remaining
    // transform needed to align landmarks with the model image below.
    final landmarks = orientNormalizedPoints(
      normalizedLandmarks,
      rotationDegrees: 0,
      mirrorHorizontally: mirrorHorizontally,
    );
    final bounds = _boundsForPoints(landmarks);
    if (cameraImage.format.group == ImageFormatGroup.yuv420 ||
        cameraImage.format.group == ImageFormatGroup.nv21) {
      final orientedSize = _orientedSize(
        cameraImage.width,
        cameraImage.height,
        rotationDegrees,
      );
      final contextBounds = _squareCropAroundBounds(
        orientedSize,
        bounds,
        paddingScale: 1.35,
      );
      final tightBounds = _squareCropAroundBounds(
        orientedSize,
        bounds,
        paddingScale: 1.08,
      );
      return CameraFrameCrops(
        context: _sampleLuminanceCrop(
          cameraImage,
          contextBounds,
          rotationDegrees: rotationDegrees,
          mirrorHorizontally: mirrorHorizontally,
        ),
        tight: _sampleLuminanceCrop(
          cameraImage,
          tightBounds,
          rotationDegrees: rotationDegrees,
          mirrorHorizontally: mirrorHorizontally,
        ),
        orientedLandmarks: landmarks,
      );
    }

    if (cameraImage.format.group != ImageFormatGroup.bgra8888) {
      throw UnsupportedError(
        'Format kamera ${cameraImage.format.group.name} belum didukung.',
      );
    }
    var oriented = _bgraToGray(cameraImage);
    if (rotationDegrees != 0) {
      oriented = img.copyRotate(oriented, angle: rotationDegrees.toDouble());
    }
    if (mirrorHorizontally) oriented = img.flipHorizontal(oriented);
    return CameraFrameCrops(
      context: _cropAroundHand(oriented, bounds, paddingScale: 1.35),
      tight: _cropAroundLandmarks(oriented, landmarks),
      orientedLandmarks: landmarks,
    );
  }

  static List<Offset> orientNormalizedPoints(
    List<Offset> points, {
    required int rotationDegrees,
    required bool mirrorHorizontally,
  }) {
    final rotation = ((rotationDegrees % 360) + 360) % 360;
    if (rotation != 0 && rotation != 90 && rotation != 180 && rotation != 270) {
      throw ArgumentError.value(
        rotationDegrees,
        'rotationDegrees',
        'Rotasi harus kelipatan 90 derajat.',
      );
    }

    return List<Offset>.unmodifiable(
      points.map((point) {
        final rotated = switch (rotation) {
          90 => Offset(1 - point.dy, point.dx),
          180 => Offset(1 - point.dx, 1 - point.dy),
          270 => Offset(point.dy, 1 - point.dx),
          _ => point,
        };
        return mirrorHorizontally
            ? Offset(1 - rotated.dx, rotated.dy)
            : rotated;
      }),
    );
  }

  static img.Image cropAndOrientSensorImage(
    img.Image sensorGray, {
    required int rotationDegrees,
    required bool mirrorHorizontally,
    Rect? normalizedCrop,
  }) {
    // MediaPipe reports landmarks in sensor-frame coordinates. Crop before
    // rotating so the region stays aligned with the detected hand.
    final gray = normalizedCrop == null
        ? sensorGray
        : _cropAroundHand(sensorGray, normalizedCrop);
    var oriented = rotationDegrees == 0
        ? gray
        : img.copyRotate(gray, angle: rotationDegrees.toDouble());
    if (mirrorHorizontally) {
      oriented = img.flipHorizontal(oriented);
    }
    return oriented;
  }

  static List<List<List<List<double>>>> toModelInput(
    img.Image source, {
    double cropFraction = 1,
    Rect? normalizedCrop,
  }) {
    return modelImageToInput(
      toModelImage(
        source,
        cropFraction: cropFraction,
        normalizedCrop: normalizedCrop,
      ),
    );
  }

  static img.Image toModelImage(
    img.Image source, {
    double cropFraction = 1,
    Rect? normalizedCrop,
  }) {
    final cropped = normalizedCrop == null
        ? _centerCrop(source, cropFraction)
        : _cropAroundHand(source, normalizedCrop);
    return img.copyResize(
      cropped,
      width: 28,
      height: 28,
      interpolation: img.Interpolation.average,
    );
  }

  static List<List<List<List<double>>>> modelImageToInput(img.Image resized) {
    if (resized.width != 28 || resized.height != 28) {
      throw ArgumentError.value(
        '${resized.width}x${resized.height}',
        'resized',
        'Gambar input model harus berukuran 28x28.',
      );
    }
    return <List<List<List<double>>>>[
      List<List<List<double>>>.generate(
        28,
        (y) => List<List<double>>.generate(
          28,
          (x) => <double>[resized.getPixel(x, y).luminance.toDouble()],
          growable: false,
        ),
        growable: false,
      ),
    ];
  }

  static img.Image _centerCrop(img.Image source, double cropFraction) {
    final shortestSide = source.width < source.height
        ? source.width
        : source.height;
    final side = (shortestSide * cropFraction.clamp(0.1, 1)).round();
    return img.copyCrop(
      source,
      x: (source.width - side) ~/ 2,
      y: (source.height - side) ~/ 2,
      width: side,
      height: side,
    );
  }

  static Rect _boundsForPoints(List<Offset> points) {
    if (points.isEmpty) return const Rect.fromLTWH(0, 0, 1, 1);
    var left = points.first.dx;
    var top = points.first.dy;
    var right = points.first.dx;
    var bottom = points.first.dy;
    for (final point in points.skip(1)) {
      if (point.dx < left) left = point.dx;
      if (point.dy < top) top = point.dy;
      if (point.dx > right) right = point.dx;
      if (point.dy > bottom) bottom = point.dy;
    }
    return Rect.fromLTRB(
      left.clamp(0.0, 1.0),
      top.clamp(0.0, 1.0),
      right.clamp(0.0, 1.0),
      bottom.clamp(0.0, 1.0),
    );
  }

  static Size _orientedSize(int width, int height, int rotationDegrees) {
    final rotation = ((rotationDegrees % 360) + 360) % 360;
    return rotation == 90 || rotation == 270
        ? Size(height.toDouble(), width.toDouble())
        : Size(width.toDouble(), height.toDouble());
  }

  static Rect _squareCropAroundBounds(
    Size imageSize,
    Rect normalizedBounds, {
    required double paddingScale,
  }) {
    final left = normalizedBounds.left.clamp(0.0, 1.0) * imageSize.width;
    final top = normalizedBounds.top.clamp(0.0, 1.0) * imageSize.height;
    final right = normalizedBounds.right.clamp(0.0, 1.0) * imageSize.width;
    final bottom = normalizedBounds.bottom.clamp(0.0, 1.0) * imageSize.height;
    final requestedSide =
        ((right - left).abs() > (bottom - top).abs()
            ? (right - left).abs()
            : (bottom - top).abs()) *
        paddingScale;
    final shortestSide = imageSize.width < imageSize.height
        ? imageSize.width
        : imageSize.height;
    final side = requestedSide.clamp(1.0, shortestSide);
    final maxX = imageSize.width - side;
    final maxY = imageSize.height - side;
    final x = ((left + right - side) / 2).clamp(0.0, maxX);
    final y = ((top + bottom - side) / 2).clamp(0.0, maxY);
    return Rect.fromLTWH(x, y, side, side);
  }

  static img.Image _sampleLuminanceCrop(
    CameraImage cameraImage,
    Rect crop, {
    required int rotationDegrees,
    required bool mirrorHorizontally,
  }) {
    final plane = cameraImage.planes.first;
    final pixelStride = plane.bytesPerPixel ?? 1;
    final orientedSize = _orientedSize(
      cameraImage.width,
      cameraImage.height,
      rotationDegrees,
    );
    final output = img.Image(width: 28, height: 28, numChannels: 1);
    for (var outputY = 0; outputY < 28; outputY++) {
      for (var outputX = 0; outputX < 28; outputX++) {
        var sum = 0;
        for (final sampleY in const <double>[0.25, 0.75]) {
          for (final sampleX in const <double>[0.25, 0.75]) {
            final orientedX =
                (crop.left + (outputX + sampleX) * crop.width / 28) /
                orientedSize.width;
            final orientedY =
                (crop.top + (outputY + sampleY) * crop.height / 28) /
                orientedSize.height;
            final sensorPoint = _orientedToSensorPoint(
              Offset(orientedX, orientedY),
              rotationDegrees: rotationDegrees,
              mirroredHorizontally: mirrorHorizontally,
            );
            final sensorX = (sensorPoint.dx * cameraImage.width).floor().clamp(
              0,
              cameraImage.width - 1,
            );
            final sensorY = (sensorPoint.dy * cameraImage.height).floor().clamp(
              0,
              cameraImage.height - 1,
            );
            sum += plane
                .bytes[sensorY * plane.bytesPerRow + sensorX * pixelStride];
          }
        }
        output.setPixelR(outputX, outputY, sum ~/ 4);
      }
    }
    return output;
  }

  static Offset _orientedToSensorPoint(
    Offset point, {
    required int rotationDegrees,
    required bool mirroredHorizontally,
  }) {
    final rotated = mirroredHorizontally
        ? Offset(1 - point.dx, point.dy)
        : point;
    final rotation = ((rotationDegrees % 360) + 360) % 360;
    return switch (rotation) {
      90 => Offset(rotated.dy, 1 - rotated.dx),
      180 => Offset(1 - rotated.dx, 1 - rotated.dy),
      270 => Offset(1 - rotated.dy, rotated.dx),
      _ => rotated,
    };
  }

  static img.Image _cropAroundHand(
    img.Image source,
    Rect normalizedCrop, {
    double paddingScale = 1.55,
  }) {
    final left = normalizedCrop.left.clamp(0.0, 1.0) * source.width;
    final top = normalizedCrop.top.clamp(0.0, 1.0) * source.height;
    final right = normalizedCrop.right.clamp(0.0, 1.0) * source.width;
    final bottom = normalizedCrop.bottom.clamp(0.0, 1.0) * source.height;
    final handWidth = (right - left).abs();
    final handHeight = (bottom - top).abs();
    final shortestSide = source.width < source.height
        ? source.width
        : source.height;
    final requestedSide =
        ((handWidth > handHeight ? handWidth : handHeight) * paddingScale)
            .round();
    final side = requestedSide.clamp(1, shortestSide);
    final centerX = (left + right) / 2;
    final centerY = (top + bottom) / 2;
    final maxX = source.width - side;
    final maxY = source.height - side;
    final x = (centerX - side / 2).round().clamp(0, maxX);
    final y = (centerY - side / 2).round().clamp(0, maxY);

    return img.copyCrop(source, x: x, y: y, width: side, height: side);
  }

  static img.Image _cropAroundLandmarks(
    img.Image source,
    List<Offset> normalizedLandmarks,
  ) {
    return _cropAroundHand(
      source,
      _boundsForPoints(normalizedLandmarks),
      paddingScale: 1.08,
    );
  }

  static img.Image _luminancePlaneToImage(CameraImage cameraImage) {
    final plane = cameraImage.planes.first;
    final pixelStride = plane.bytesPerPixel ?? 1;
    final output = img.Image(
      width: cameraImage.width,
      height: cameraImage.height,
      numChannels: 1,
    );

    for (var y = 0; y < cameraImage.height; y++) {
      final rowOffset = y * plane.bytesPerRow;
      for (var x = 0; x < cameraImage.width; x++) {
        final value = plane.bytes[rowOffset + (x * pixelStride)];
        output.setPixelR(x, y, value);
      }
    }
    return output;
  }

  static img.Image _bgraToGray(CameraImage cameraImage) {
    final plane = cameraImage.planes.first;
    final source = img.Image.fromBytes(
      width: cameraImage.width,
      height: cameraImage.height,
      bytes: plane.bytes.buffer,
      bytesOffset: plane.bytes.offsetInBytes,
      rowStride: plane.bytesPerRow,
      numChannels: 4,
      order: img.ChannelOrder.bgra,
    );
    return img.grayscale(source);
  }
}
