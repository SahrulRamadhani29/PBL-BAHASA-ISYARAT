import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:pbl_bahasa_isyarat/services/image_preprocessor.dart';

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
