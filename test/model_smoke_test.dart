import 'dart:convert';

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:pbl_bahasa_isyarat/services/image_preprocessor.dart';

CameraImage _syntheticYuvFrame({
  required int width,
  required int height,
  required int rotationDegrees,
  required bool mirroredHorizontally,
  required Rect brightRect,
}) {
  final luminance = List<int>.filled(width * height, 8);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final sensorPoint = Offset((x + 0.5) / width, (y + 0.5) / height);
      final rotated = switch (rotationDegrees) {
        90 => Offset(1 - sensorPoint.dy, sensorPoint.dx),
        180 => Offset(1 - sensorPoint.dx, 1 - sensorPoint.dy),
        270 => Offset(sensorPoint.dy, 1 - sensorPoint.dx),
        _ => sensorPoint,
      };
      final oriented = mirroredHorizontally
          ? Offset(1 - rotated.dx, rotated.dy)
          : rotated;
      if (brightRect.contains(oriented)) luminance[y * width + x] = 240;
    }
  }
  final uvWidth = (width + 1) ~/ 2;
  final uvHeight = (height + 1) ~/ 2;
  final uv = Uint8List.fromList(List<int>.filled(uvWidth * uvHeight, 127));

  // Test-only constructor for a synthetic YUV frame.
  // ignore: deprecated_member_use
  return CameraImage.fromPlatformData({
    'format': 35,
    'height': height,
    'width': width,
    'planes': [
      {
        'bytes': Uint8List.fromList(luminance),
        'bytesPerPixel': 1,
        'bytesPerRow': width,
      },
      {'bytes': uv, 'bytesPerPixel': 1, 'bytesPerRow': uvWidth},
      {'bytes': uv, 'bytesPerPixel': 1, 'bytesPerRow': uvWidth},
    ],
  });
}

List<Offset> _mediaPipeLandmarksFor(
  Rect finalOrientedRect, {
  required bool mirroredHorizontally,
}) {
  return List<Offset>.generate(21, (index) {
    final finalPoint = Offset(
      finalOrientedRect.left + finalOrientedRect.width * (index % 7) / 6,
      finalOrientedRect.top + finalOrientedRect.height * (index ~/ 7) / 2,
    );
    return mirroredHorizontally
        ? Offset(1 - finalPoint.dx, finalPoint.dy)
        : finalPoint;
  }, growable: false);
}

double _averageBrightness(img.Image image) {
  var total = 0.0;
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      total += image.getPixel(x, y).r;
    }
  }
  return total / (image.width * image.height);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('assets model, label, dan preprocessing tersedia', () async {
    final model = await rootBundle.load('assets/models/model_float16.tflite');
    final labelsData = await rootBundle.loadString('assets/models/labels.json');
    final labelsJson = jsonDecode(labelsData) as Map<String, dynamic>;
    final labels = List<String>.from(labelsJson['labels'] as List<dynamic>);
    final referencesData = await rootBundle.loadString(
      'assets/models/landmark_references.json',
    );
    final referencesJson = jsonDecode(referencesData) as Map<String, dynamic>;
    final references = referencesJson['labels'] as Map<String, dynamic>;
    final imageData = await rootBundle.load('assets/signs/a.png');
    final image = ImagePreprocessor.decodeFileBytes(
      imageData.buffer.asUint8List(),
    );
    final input = ImagePreprocessor.toModelInput(image);

    expect(model.lengthInBytes, greaterThan(5 * 1024 * 1024));
    expect(labels, hasLength(24));
    expect(references.keys.toSet(), labels.toSet());
    expect(
      references.values.every(
        (points) => (points as List<dynamic>).length == 21,
      ),
      isTrue,
    );
    expect(input, hasLength(1));
    expect(input.first, hasLength(28));
    expect(input.first.first, hasLength(28));
    expect(input.first.first.first, hasLength(1));
  });

  test('koordinat landmark mengikuti rotasi dan mirror input kamera', () {
    final points = ImagePreprocessor.orientNormalizedPoints(
      const [Offset(0.2, 0.3)],
      rotationDegrees: 270,
      mirrorHorizontally: true,
    );

    expect(points.single.dx, closeTo(0.7, 0.000001));
    expect(points.single.dy, closeTo(0.8, 0.000001));
  });

  test('rotasi kamera tidak memutar ulang buffer yang sudah portrait', () {
    expect(
      ImagePreprocessor.effectivePortraitRotation(
        frameWidth: 640,
        frameHeight: 480,
        requestedRotationDegrees: 270,
      ),
      270,
    );
    expect(
      ImagePreprocessor.effectivePortraitRotation(
        frameWidth: 480,
        frameHeight: 640,
        requestedRotationDegrees: 270,
      ),
      0,
    );
  });

  test('landmark MediaPipe tidak diputar dua kali saat crop kamera', () {
    // Test-only constructor for a synthetic YUV frame.
    // ignore: deprecated_member_use
    final cameraImage = CameraImage.fromPlatformData({
      'format': 35,
      'height': 8,
      'width': 12,
      'planes': [
        {
          'bytes': Uint8List.fromList(List<int>.filled(96, 127)),
          'bytesPerPixel': 1,
          'bytesPerRow': 12,
        },
        {
          'bytes': Uint8List.fromList(List<int>.filled(24, 127)),
          'bytesPerPixel': 1,
          'bytesPerRow': 6,
        },
        {
          'bytes': Uint8List.fromList(List<int>.filled(24, 127)),
          'bytesPerPixel': 1,
          'bytesPerRow': 6,
        },
      ],
    });
    final mediaPipePoints = List<Offset>.generate(
      21,
      (index) => Offset(0.20 + index * 0.01, 0.30 + index * 0.005),
    );

    final crops = ImagePreprocessor.cameraImageToGrayCrops(
      cameraImage,
      rotationDegrees: 270,
      mirrorHorizontally: true,
      normalizedLandmarks: mediaPipePoints,
    );

    expect(crops.orientedLandmarks.first.dx, closeTo(0.80, 0.000001));
    expect(crops.orientedLandmarks.first.dy, closeTo(0.30, 0.000001));
  });

  test('sampler YUV cepat tetap mengambil tangan setelah rotasi kamera', () {
    final luminance = List<int>.filled(12 * 8, 0);
    for (var y = 2; y <= 6; y++) {
      for (var x = 1; x <= 3; x++) {
        luminance[y * 12 + x] = 255;
      }
    }
    // Rotasi 270 memetakan area sensor tersebut ke bagian bawah frame
    // portrait yang menjadi koordinat keluaran MediaPipe.
    // ignore: deprecated_member_use
    final cameraImage = CameraImage.fromPlatformData({
      'format': 35,
      'height': 8,
      'width': 12,
      'planes': [
        {
          'bytes': Uint8List.fromList(luminance),
          'bytesPerPixel': 1,
          'bytesPerRow': 12,
        },
        {
          'bytes': Uint8List.fromList(List<int>.filled(24, 127)),
          'bytesPerPixel': 1,
          'bytesPerRow': 6,
        },
        {
          'bytes': Uint8List.fromList(List<int>.filled(24, 127)),
          'bytesPerPixel': 1,
          'bytesPerRow': 6,
        },
      ],
    });
    final points = List<Offset>.generate(
      21,
      (index) => Offset(0.28 + (index % 5) * 0.10, 0.76 + (index ~/ 5) * 0.04),
    );

    final crops = ImagePreprocessor.cameraImageToGrayCrops(
      cameraImage,
      rotationDegrees: 270,
      mirrorHorizontally: false,
      normalizedLandmarks: points,
    );
    final brightness = List<int>.generate(
      28 * 28,
      (index) => crops.context.getPixel(index % 28, index ~/ 28).r.toInt(),
    ).fold<int>(0, (sum, value) => sum + value);

    expect(crops.context.width, 28);
    expect(crops.context.height, 28);
    expect(brightness, greaterThan(10000));
  });

  final cropCases = <({int rotation, bool mirror, Rect hand})>[
    (
      rotation: 0,
      mirror: false,
      hand: const Rect.fromLTRB(0.01, 0.28, 0.27, 0.72),
    ),
    (
      rotation: 0,
      mirror: true,
      hand: const Rect.fromLTRB(0.73, 0.28, 0.99, 0.72),
    ),
    (
      rotation: 90,
      mirror: false,
      hand: const Rect.fromLTRB(0.28, 0.01, 0.72, 0.27),
    ),
    (
      rotation: 90,
      mirror: true,
      hand: const Rect.fromLTRB(0.28, 0.73, 0.72, 0.99),
    ),
    (
      rotation: 180,
      mirror: false,
      hand: const Rect.fromLTRB(0.73, 0.28, 0.99, 0.72),
    ),
    (
      rotation: 180,
      mirror: true,
      hand: const Rect.fromLTRB(0.01, 0.28, 0.27, 0.72),
    ),
    (
      rotation: 270,
      mirror: false,
      hand: const Rect.fromLTRB(0.28, 0.73, 0.72, 0.99),
    ),
    (
      rotation: 270,
      mirror: true,
      hand: const Rect.fromLTRB(0.28, 0.01, 0.72, 0.27),
    ),
  ];
  for (final cropCase in cropCases) {
    test(
      'crop YUV akurat pada rotasi ${cropCase.rotation}, mirror ${cropCase.mirror}, dan tepi frame',
      () {
        final frame = _syntheticYuvFrame(
          width: 64,
          height: 48,
          rotationDegrees: cropCase.rotation,
          mirroredHorizontally: cropCase.mirror,
          brightRect: cropCase.hand,
        );
        final crops = ImagePreprocessor.cameraImageToGrayCrops(
          frame,
          rotationDegrees: cropCase.rotation,
          mirrorHorizontally: cropCase.mirror,
          normalizedLandmarks: _mediaPipeLandmarksFor(
            cropCase.hand,
            mirroredHorizontally: cropCase.mirror,
          ),
        );

        expect(crops.context, hasModelDimensions);
        expect(crops.tight, hasModelDimensions);
        expect(_averageBrightness(crops.context), greaterThan(70));
        expect(_averageBrightness(crops.tight), greaterThan(110));
      },
    );
  }

  test('crop landmark mengikuti tangan yang berada di pinggir frame', () {
    final image = img.Image(width: 100, height: 100, numChannels: 1);
    for (var y = 30; y < 70; y++) {
      for (var x = 78; x < 100; x++) {
        image.setPixelR(x, y, 255);
      }
    }

    final fullFrame = ImagePreprocessor.toModelInput(image);
    final handCrop = ImagePreprocessor.toModelInput(
      image,
      normalizedCrop: const Rect.fromLTRB(0.78, 0.30, 1, 0.70),
    );
    double brightness(List<List<List<List<double>>>> input) => input.first
        .expand((row) => row)
        .fold(0, (sum, pixel) => sum + pixel.first);

    expect(brightness(handCrop), greaterThan(brightness(fullFrame) * 2));
  });

  test('crop kamera dilakukan sebelum rotasi sensor', () {
    final sensorFrame = img.Image(width: 120, height: 80, numChannels: 1);
    for (var y = 20; y < 60; y++) {
      for (var x = 90; x < 115; x++) {
        sensorFrame.setPixelR(x, y, 255);
      }
    }

    final hand = ImagePreprocessor.cropAndOrientSensorImage(
      sensorFrame,
      rotationDegrees: 90,
      mirrorHorizontally: true,
      normalizedCrop: const Rect.fromLTRB(0.75, 0.25, 0.96, 0.75),
    );
    final input = ImagePreprocessor.toModelInput(hand);
    final brightness = input.first
        .expand((row) => row)
        .fold<double>(0, (sum, pixel) => sum + pixel.first);

    expect(hand.width, hand.height);
    expect(brightness, greaterThan(10000));
  });
}

final Matcher hasModelDimensions = predicate<img.Image>(
  (image) => image.width == 28 && image.height == 28,
  'gambar grayscale 28x28',
);
