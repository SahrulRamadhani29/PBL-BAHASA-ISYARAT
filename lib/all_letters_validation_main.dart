import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import 'services/image_preprocessor.dart';
import 'services/sign_classifier.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _ValidationApp());
}

class _ValidationApp extends StatefulWidget {
  const _ValidationApp();

  @override
  State<_ValidationApp> createState() => _ValidationAppState();
}

class _ValidationAppState extends State<_ValidationApp> {
  String _status = 'Menyiapkan model...';
  int _completed = 0;
  int _normalCorrect = 0;
  int _mirroredCorrect = 0;
  int _cameraCorrect = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _runValidation());
  }

  Future<void> _runValidation() async {
    final report = <String, Object?>{
      'started_at': DateTime.now().toUtc().toIso8601String(),
      'results': <String, Object?>{},
    };
    try {
      final labelsData = await rootBundle.loadString(
        'assets/models/labels.json',
      );
      final labelsJson = jsonDecode(labelsData) as Map<String, dynamic>;
      final labels = List<String>.from(labelsJson['labels'] as List<dynamic>);
      final referencesData = await rootBundle.loadString(
        'assets/models/landmark_references.json',
      );
      final referencesJson = jsonDecode(referencesData) as Map<String, dynamic>;
      final references = referencesJson['labels'] as Map<String, dynamic>;
      final classifier = SignClassifier.instance;
      await classifier.initialize().timeout(const Duration(seconds: 30));
      final results = report['results']! as Map<String, Object?>;
      const paddingCandidates = <double>[1.0, 1.2, 1.4, 1.6, 1.8, 2.0, 2.4];
      final paddingCorrect = <String, int>{
        for (final padding in paddingCandidates) '$padding': 0,
      };

      for (final expected in labels) {
        if (mounted) setState(() => _status = 'Menguji huruf $expected...');
        try {
          final imageData = await rootBundle.load(
            'assets/signs/${expected.toLowerCase()}.png',
          );
          final image = ImagePreprocessor.decodeFileBytes(
            imageData.buffer.asUint8List(),
          );
          final normal = await classifier
              .classifyImage(image)
              .timeout(const Duration(seconds: 10));
          final mirrored = await classifier
              .classifyImage(img.flipHorizontal(img.Image.from(image)))
              .timeout(const Duration(seconds: 10));
          final cameraInput = _cameraFrameFromPortraitImage(image);
          final referencePoints = (references[expected] as List<dynamic>)
              .map((point) {
                final coordinates = point as List<dynamic>;
                return Offset(
                  (coordinates[0] as num).toDouble(),
                  (coordinates[1] as num).toDouble(),
                );
              })
              .toList(growable: false);
          final cameraLandmarks = referencePoints
              .map((point) {
                return Offset(point.dx, (60 + point.dy * 240) / 360);
              })
              .toList(growable: false);
          final camera = await classifier
              .classifyCameraFrame(
                cameraInput,
                rotationDegrees: 270,
                mirrorHorizontally: false,
                normalizedLandmarks: cameraLandmarks,
              )
              .timeout(const Duration(seconds: 10));
          final paddingResults = <String, Object?>{};
          for (final padding in paddingCandidates) {
            final prediction = await classifier
                .classifyImage(
                  _cropAroundPoints(image, referencePoints, padding),
                )
                .timeout(const Duration(seconds: 10));
            final key = '$padding';
            if (prediction.label == expected) {
              paddingCorrect[key] = paddingCorrect[key]! + 1;
            }
            paddingResults[key] = <String, Object?>{
              'label': prediction.label,
              'confidence': prediction.confidence,
              'correct': prediction.label == expected,
            };
          }
          if (normal.label == expected) _normalCorrect++;
          if (mirrored.label == expected) _mirroredCorrect++;
          if (camera.label == expected) _cameraCorrect++;
          results[expected] = <String, Object?>{
            'normal_label': normal.label,
            'normal_confidence': normal.confidence,
            'normal_correct': normal.label == expected,
            'mirrored_label': mirrored.label,
            'mirrored_confidence': mirrored.confidence,
            'mirrored_correct': mirrored.label == expected,
            'camera_label': camera.label,
            'camera_confidence': camera.confidence,
            'camera_correct': camera.label == expected,
            'padding_results': paddingResults,
          };
          if (expected == 'C') {
            await _writeCameraInputs(classifier);
          }
        } catch (error, stackTrace) {
          results[expected] = <String, Object?>{
            'error': '$error',
            'stack_trace': '$stackTrace',
          };
        }
        _completed++;
        if (mounted) setState(() {});
      }
      report['finished_at'] = DateTime.now().toUtc().toIso8601String();
      report['normal_correct'] = _normalCorrect;
      report['mirrored_correct'] = _mirroredCorrect;
      report['camera_correct'] = _cameraCorrect;
      report['padding_correct'] = paddingCorrect;
      report['total'] = labels.length;
      await _writeReport(report);
      if (mounted) setState(() => _status = 'VALIDASI SELESAI');
    } catch (error, stackTrace) {
      report['fatal_error'] = '$error';
      report['stack_trace'] = '$stackTrace';
      await _writeReport(report);
      if (mounted) setState(() => _status = 'GAGAL: $error');
    }
  }

  Future<void> _writeReport(Map<String, Object?> report) async {
    final directory = await getApplicationDocumentsDirectory();
    await File(
      '${directory.path}${Platform.pathSeparator}all_letters_validation.json',
    ).writeAsString(
      const JsonEncoder.withIndent('  ').convert(report),
      flush: true,
    );
  }

  Future<void> _writeCameraInputs(SignClassifier classifier) async {
    final directory = await getApplicationDocumentsDirectory();
    final context = classifier.lastContextInputPng;
    final tight = classifier.lastTightInputPng;
    if (context != null) {
      await File('${directory.path}/validation_c_context.png')
          .writeAsBytes(context, flush: true);
    }
    if (tight != null) {
      await File('${directory.path}/validation_c_tight.png')
          .writeAsBytes(tight, flush: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.fact_check_outlined, size: 64),
                  const SizedBox(height: 20),
                  Text(
                    _status,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  LinearProgressIndicator(value: _completed / 24),
                  const SizedBox(height: 12),
                  Text('$_completed/24 huruf'),
                  Text('Normal benar: $_normalCorrect'),
                  Text('Mirror benar: $_mirroredCorrect'),
                  Text('Pipeline kamera benar: $_cameraCorrect'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

img.Image _cropAroundPoints(
  img.Image source,
  List<Offset> points,
  double padding,
) {
  final left = points.map((point) => point.dx).reduce(math.min) * source.width;
  final right = points.map((point) => point.dx).reduce(math.max) * source.width;
  final top = points.map((point) => point.dy).reduce(math.min) * source.height;
  final bottom =
      points.map((point) => point.dy).reduce(math.max) * source.height;
  final requestedSide = math.max(right - left, bottom - top) * padding;
  final side = requestedSide
      .round()
      .clamp(1, math.min(source.width, source.height))
      .toInt();
  final x = ((left + right - side) / 2)
      .round()
      .clamp(0, source.width - side)
      .toInt();
  final y = ((top + bottom - side) / 2)
      .round()
      .clamp(0, source.height - side)
      .toInt();
  return img.copyCrop(source, x: x, y: y, width: side, height: side);
}

CameraImage _cameraFrameFromPortraitImage(img.Image source) {
  const sensorWidth = 360;
  const sensorHeight = 240;
  const orientedWidth = 240;
  const orientedHeight = 360;
  const imageTop = 60;
  final resized = img.copyResize(
    img.grayscale(source),
    width: orientedWidth,
    height: orientedWidth,
    interpolation: img.Interpolation.average,
  );
  final background = resized.getPixel(0, 0).r.toInt();
  final luminance = Uint8List(sensorWidth * sensorHeight);
  for (var sensorY = 0; sensorY < sensorHeight; sensorY++) {
    for (var sensorX = 0; sensorX < sensorWidth; sensorX++) {
      // Forward rotation 270: sensor (x,y) -> oriented (y, 1-x).
      final orientedX = ((sensorY + 0.5) / sensorHeight * orientedWidth)
          .floor();
      final orientedY = ((1 - (sensorX + 0.5) / sensorWidth) * orientedHeight)
          .floor();
      final sourceY = orientedY - imageTop;
      luminance[sensorY * sensorWidth +
          sensorX] = sourceY >= 0 && sourceY < resized.height
          ? resized
                .getPixel(orientedX.clamp(0, resized.width - 1), sourceY)
                .r
                .toInt()
          : background;
    }
  }
  final chroma = Uint8List((sensorWidth ~/ 2) * (sensorHeight ~/ 2))
    ..fillRange(0, (sensorWidth ~/ 2) * (sensorHeight ~/ 2), 128);

  // Test-only constructor for an Android-compatible YUV420 frame.
  // ignore: deprecated_member_use
  return CameraImage.fromPlatformData({
    'format': 35,
    'height': sensorHeight,
    'width': sensorWidth,
    'planes': [
      {'bytes': luminance, 'bytesPerPixel': 1, 'bytesPerRow': sensorWidth},
      {'bytes': chroma, 'bytesPerPixel': 1, 'bytesPerRow': sensorWidth ~/ 2},
      {'bytes': chroma, 'bytesPerPixel': 1, 'bytesPerRow': sensorWidth ~/ 2},
    ],
  });
}
