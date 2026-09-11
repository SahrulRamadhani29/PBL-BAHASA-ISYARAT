import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

import '../models/sign_prediction.dart';
import 'image_preprocessor.dart';

class SignClassifier {
  SignClassifier._();

  static final SignClassifier instance = SignClassifier._();

  static const _modelPath = 'assets/models/model_float16.tflite';
  static const _labelsPath = 'assets/models/labels.json';
  static const _landmarkReferencesPath =
      'assets/models/landmark_references.json';

  Interpreter? _interpreter;
  List<String> _labels = const [];
  Map<String, List<Offset>> _landmarkReferences = const {};
  Future<void>? _initialization;
  img.Image? _lastContextInput;
  img.Image? _lastTightInput;
  SignPrediction? _lastContextPrediction;
  SignPrediction? _lastTightPrediction;
  SignPrediction? _lastLandmarkPrediction;

  bool get isReady => _interpreter != null && _labels.isNotEmpty;
  List<String> get labels => List.unmodifiable(_labels);
  List<int>? get lastContextInputPng =>
      _lastContextInput == null ? null : img.encodePng(_lastContextInput!);
  List<int>? get lastTightInputPng =>
      _lastTightInput == null ? null : img.encodePng(_lastTightInput!);
  SignPrediction? get lastContextPrediction => _lastContextPrediction;
  SignPrediction? get lastTightPrediction => _lastTightPrediction;
  SignPrediction? get lastLandmarkPrediction => _lastLandmarkPrediction;

  Future<void> initialize() => _initialization ??= _load();

  Future<void> _load() async {
    final labelsJson = jsonDecode(await rootBundle.loadString(_labelsPath));
    _labels = List<String>.from(labelsJson['labels'] as List<dynamic>);
    final referencesJson = jsonDecode(
      await rootBundle.loadString(_landmarkReferencesPath),
    ) as Map<String, dynamic>;
    final references = referencesJson['labels'] as Map<String, dynamic>;
    _landmarkReferences = Map<String, List<Offset>>.unmodifiable(
      references.map(
        (label, value) => MapEntry(
          label,
          (value as List<dynamic>)
              .map((point) {
                final coordinates = point as List<dynamic>;
                return Offset(
                  (coordinates[0] as num).toDouble(),
                  (coordinates[1] as num).toDouble(),
                );
              })
              .toList(growable: false),
        ),
      ),
    );

    final options = InterpreterOptions()..threads = 4;
    _interpreter = await Interpreter.fromAsset(_modelPath, options: options);

    final inputShape = _interpreter!.getInputTensor(0).shape;
    final outputShape = _interpreter!.getOutputTensor(0).shape;
    if (!_sameShape(inputShape, const [1, 28, 28, 1]) ||
        !_sameShape(outputShape, <int>[1, _labels.length])) {
      _interpreter!.close();
      _interpreter = null;
      throw StateError(
        'Kontrak model tidak sesuai: input $inputShape, output $outputShape.',
      );
    }
  }

  Future<SignPrediction> classifyFile(String path) async {
    await initialize();
    final bytes = await File(path).readAsBytes();
    final image = ImagePreprocessor.decodeFileBytes(bytes);
    return classifyImage(image);
  }

  Future<SignPrediction> classifyCameraFrame(
    CameraImage cameraImage, {
    required int rotationDegrees,
    required bool mirrorHorizontally,
    required List<Offset> normalizedLandmarks,
  }) async {
    await initialize();
    final crops = ImagePreprocessor.cameraImageToGrayCrops(
      cameraImage,
      rotationDegrees: rotationDegrees,
      mirrorHorizontally: mirrorHorizontally,
      normalizedLandmarks: normalizedLandmarks,
    );
    final contextInput = ImagePreprocessor.toModelImage(crops.context);
    final contextPrediction = _classifyModelImage(contextInput);
    final landmarkPrediction = _classifyLandmarks(crops.orientedLandmarks);
    _lastContextInput = contextInput;
    _lastTightInput = null;
    _lastContextPrediction = contextPrediction;
    _lastTightPrediction = null;
    _lastLandmarkPrediction = landmarkPrediction;
    final landmarksDisagreeStrongly =
        landmarkPrediction != null &&
        landmarkPrediction.confidence >= 0.55 &&
        landmarkPrediction.label != contextPrediction.label;
    if (!landmarksDisagreeStrongly && contextPrediction.confidence >= 0.80) {
      return contextPrediction;
    }

    final tightPrediction = _classifyModelImage(
      _lastTightInput = ImagePreprocessor.toModelImage(crops.tight),
    );
    _lastTightPrediction = tightPrediction;
    if (landmarkPrediction != null &&
        landmarkPrediction.confidence >= 0.55 &&
        tightPrediction.label == landmarkPrediction.label) {
      return _blendPredictions(tightPrediction, landmarkPrediction);
    }
    if (contextPrediction.confidence < 0.80 &&
        tightPrediction.confidence > contextPrediction.confidence) {
      return tightPrediction;
    }
    return contextPrediction;
  }

  SignPrediction classifyImage(
    img.Image image, {
    double cropFraction = 1,
    Rect? normalizedCrop,
  }) {
    final interpreter = _interpreter;
    if (interpreter == null) {
      throw StateError('Model belum siap.');
    }

    final modelImage = ImagePreprocessor.toModelImage(
      image,
      cropFraction: cropFraction,
      normalizedCrop: normalizedCrop,
    );
    return _classifyModelImage(modelImage);
  }

  SignPrediction _classifyModelImage(img.Image modelImage) {
    final interpreter = _interpreter;
    if (interpreter == null) {
      throw StateError('Model belum siap.');
    }

    final input = ImagePreprocessor.modelImageToInput(modelImage);
    final output = <List<double>>[List<double>.filled(_labels.length, 0)];
    interpreter.run(input, output);
    return _predictionFromScores(List<double>.from(output.first));
  }

  SignPrediction _predictionFromScores(List<double> scores) {
    var bestIndex = 0;
    for (var index = 1; index < scores.length; index++) {
      if (scores[index] > scores[bestIndex]) {
        bestIndex = index;
      }
    }
    return SignPrediction(
      label: _labels[bestIndex],
      confidence: scores[bestIndex],
      scores: scores,
    );
  }

  SignPrediction? _classifyLandmarks(List<Offset> landmarks) {
    if (landmarks.length != 21 || _landmarkReferences.isEmpty) return null;
    final feature = _normalizeLandmarks(landmarks);
    final distances = <double>[];
    for (final label in _labels) {
      final reference = _landmarkReferences[label];
      if (reference == null || reference.length != 21) return null;
      final normal = _normalizeLandmarks(reference);
      final mirrored = _normalizeLandmarks(
        reference
            .map((point) => Offset(1 - point.dx, point.dy))
            .toList(growable: false),
      );
      distances.add(
        math.min(
          _meanSquaredDistance(feature, normal),
          _meanSquaredDistance(feature, mirrored),
        ),
      );
    }

    final minimumDistance = distances.reduce(math.min);
    final weights = distances
        .map((distance) => math.exp(-(distance - minimumDistance) / 0.06))
        .toList(growable: false);
    final total = weights.fold<double>(0, (sum, value) => sum + value);
    if (!total.isFinite || total <= 0) return null;
    return _predictionFromScores(
      weights.map((weight) => weight / total).toList(growable: false),
    );
  }

  static List<double> _normalizeLandmarks(List<Offset> landmarks) {
    final wrist = landmarks[0];
    final scale = (landmarks[9] - wrist).distance;
    if (scale <= 0.000001) return List<double>.filled(42, 0);
    return landmarks
        .expand(
          (point) => <double>[
            (point.dx - wrist.dx) / scale,
            (point.dy - wrist.dy) / scale,
          ],
        )
        .toList(growable: false);
  }

  static double _meanSquaredDistance(List<double> a, List<double> b) {
    var sum = 0.0;
    for (var index = 0; index < a.length; index++) {
      final difference = a[index] - b[index];
      sum += difference * difference;
    }
    return sum / a.length;
  }

  SignPrediction _blendPredictions(
    SignPrediction imagePrediction,
    SignPrediction landmarkPrediction,
  ) {
    return _predictionFromScores(
      List<double>.generate(
        _labels.length,
        (index) =>
            imagePrediction.scores[index] * 0.70 +
            landmarkPrediction.scores[index] * 0.30,
        growable: false,
      ),
    );
  }

  void close() {
    _interpreter?.close();
    _interpreter = null;
    _initialization = null;
    _lastContextInput = null;
    _lastTightInput = null;
    _lastContextPrediction = null;
    _lastTightPrediction = null;
    _lastLandmarkPrediction = null;
  }

  static bool _sameShape(List<int> actual, List<int> expected) {
    if (actual.length != expected.length) return false;
    for (var index = 0; index < actual.length; index++) {
      if (actual[index] != expected[index]) return false;
    }
    return true;
  }
}
