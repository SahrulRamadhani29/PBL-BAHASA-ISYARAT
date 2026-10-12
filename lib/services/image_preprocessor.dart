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

  // Landmark bounds are expanded by 30% and 20% per side. The small minimum
  // prevents a noisy, tiny detection from being enlarged into a false pose.
  static const _contextPaddingScale = 1.60;
  static const _tightPaddingScale = 1.40;
  static const _contextMinimumSideFraction = 0.28;
  static const _tightMinimumSideFraction = 0.22;

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
        paddingScale: _contextPaddingScale,
        minimumSideFraction: _contextMinimumSideFraction,
      );
      final tightBounds = _squareCropAroundBounds(
        orientedSize,
        bounds,
        paddingScale: _tightPaddingScale,
        minimumSideFraction: _tightMinimumSideFraction,
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
      context: _cropAroundHand(
        oriented,
        bounds,
        paddingScale: _contextPaddingScale,
        minimumSideFraction: _contextMinimumSideFraction,
      ),
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
          (x) => <double>[_pixelLuminance(resized, x, y).toDouble()],
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
    double minimumSideFraction = 0,
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
    final longestSide = imageSize.width > imageSize.height
        ? imageSize.width
        : imageSize.height;
    final minimumSide = (shortestSide * minimumSideFraction).clamp(
      1.0,
      shortestSide,
    );
    final side = requestedSide.clamp(minimumSide, longestSide);
    // Keep the hand centred even at a frame edge. Sampling outside the image
    // is filled with background instead of shifting and distorting the crop.
    final x = (left + right - side) / 2;
    final y = (top + bottom - side) / 2;
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
    final paddingLuminance = _cameraBorderLuminance(
      cameraImage,
      rotationDegrees: rotationDegrees,
      mirrorHorizontally: mirrorHorizontally,
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
            if (orientedX < 0 ||
                orientedX >= 1 ||
                orientedY < 0 ||
                orientedY >= 1) {
              sum += paddingLuminance;
              continue;
            }
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

  static int _cameraBorderLuminance(
    CameraImage cameraImage, {
    required int rotationDegrees,
    required bool mirrorHorizontally,
  }) {
    const points = <Offset>[
      Offset(0.02, 0.02),
      Offset(0.50, 0.02),
      Offset(0.98, 0.02),
      Offset(0.02, 0.50),
      Offset(0.98, 0.50),
      Offset(0.02, 0.98),
      Offset(0.50, 0.98),
      Offset(0.98, 0.98),
    ];
    final plane = cameraImage.planes.first;
    final pixelStride = plane.bytesPerPixel ?? 1;
    final values =
        points
            .map((point) {
              final sensorPoint = _orientedToSensorPoint(
                point,
                rotationDegrees: rotationDegrees,
                mirroredHorizontally: mirrorHorizontally,
              );
              final x = (sensorPoint.dx * cameraImage.width).floor().clamp(
                0,
                cameraImage.width - 1,
              );
              final y = (sensorPoint.dy * cameraImage.height).floor().clamp(
                0,
                cameraImage.height - 1,
              );
              return plane.bytes[y * plane.bytesPerRow + x * pixelStride];
            })
            .toList(growable: false)
          ..sort();
    return (values[3] + values[4]) ~/ 2;
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
    double minimumSideFraction = 0,
  }) {
    final crop = _squareCropAroundBounds(
      Size(source.width.toDouble(), source.height.toDouble()),
      normalizedCrop,
      paddingScale: paddingScale,
      minimumSideFraction: minimumSideFraction,
    );
    return _cropImageWithPadding(source, crop);
  }

  static img.Image _cropImageWithPadding(img.Image source, Rect crop) {
    final side = crop.width
        .round()
        .clamp(1, source.width + source.height)
        .toInt();
    final startX = crop.left.round();
    final startY = crop.top.round();
    final paddingLuminance = _imageBorderLuminance(source);
    final output = img.Image(width: side, height: side, numChannels: 1);
    for (var y = 0; y < side; y++) {
      final sourceY = startY + y;
      for (var x = 0; x < side; x++) {
        final sourceX = startX + x;
        final luminance =
            sourceX >= 0 &&
                sourceX < source.width &&
                sourceY >= 0 &&
                sourceY < source.height
            ? _pixelLuminance(source, sourceX, sourceY)
            : paddingLuminance;
        output.setPixelR(x, y, luminance);
      }
    }
    return output;
  }

  static num _imageBorderLuminance(img.Image source) {
    final maxX = source.width - 1;
    final maxY = source.height - 1;
    final values = <num>[
      _pixelLuminance(source, 0, 0),
      _pixelLuminance(source, maxX ~/ 2, 0),
      _pixelLuminance(source, maxX, 0),
      _pixelLuminance(source, 0, maxY ~/ 2),
      _pixelLuminance(source, maxX, maxY ~/ 2),
      _pixelLuminance(source, 0, maxY),
      _pixelLuminance(source, maxX ~/ 2, maxY),
      _pixelLuminance(source, maxX, maxY),
    ]..sort();
    return (values[3] + values[4]) / 2;
  }

  static num _pixelLuminance(img.Image source, int x, int y) {
    final pixel = source.getPixel(x, y);
    return source.numChannels == 1 ? pixel.r : pixel.luminance;
  }

  static img.Image _cropAroundLandmarks(
    img.Image source,
    List<Offset> normalizedLandmarks,
  ) {
    return _cropAroundHand(
      source,
      _boundsForPoints(normalizedLandmarks),
      paddingScale: _tightPaddingScale,
      minimumSideFraction: _tightMinimumSideFraction,
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
