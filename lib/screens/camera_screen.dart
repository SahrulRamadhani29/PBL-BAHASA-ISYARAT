import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hand_landmarker/hand_landmarker.dart';
import 'package:path_provider/path_provider.dart';

import '../models/sign_prediction.dart';
import '../services/image_preprocessor.dart';
import '../services/sign_classifier.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key, this.cameraEnabled = true});

  final bool cameraEnabled;

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {
  static const _handDetectionInterval = Duration(milliseconds: 320);
  static const _analysisInterval = Duration(milliseconds: 260);
  static const _minimumConfidence = 0.60;
  static const _stableFramesRequired = 2;
  static const _handPresenceWindow = Duration(milliseconds: 800);
  static const _handDetectionTimeout = Duration(seconds: 2);
  static final _supportedLabels = 'ABCDEFGHIKLMNOPQRSTUVWXY'.split('');

  CameraController? _controller;
  HandLandmarkerPlugin? _handLandmarker;
  StreamSubscription<List<Hand>>? _handSubscription;
  List<CameraDescription> _cameras = const [];
  int _cameraIndex = 0;
  bool _isInitializing = true;
  bool _isSessionActive = false;
  bool _isTargetAnalysisActive = false;
  bool _isTargetAnalysisStarting = false;
  bool _isProcessingFrame = false;
  bool _isHandDetectionPending = false;
  bool _handDetected = false;
  String? _cameraError;
  DateTime? _lastHandDetectionAt;
  DateTime? _lastAnalysisAt;
  DateTime? _lastHandSeenAt;
  List<Offset>? _latestHandLandmarks;
  String? _candidateLabel;
  int _candidateCount = 0;
  String? _lastCommittedLabel;
  int _releaseFrameCount = 0;
  final List<String> _sessionLetters = [];
  final List<String> _validationPredictions = [];
  String _selectedTarget = '';
  String? _latestTargetPrediction;
  double? _latestTargetConfidence;
  String? _savedVideoPath;
  int _analysisGeneration = 0;
  DateTime? _lastCameraDiagnosticAt;
  int? _lastFrameWidth;
  int? _lastFrameHeight;
  int? _lastFrameRotation;
  bool? _lastFrameMirrored;

  bool get _isAnalysisActive => _isSessionActive || _isTargetAnalysisActive;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.cameraEnabled) {
      unawaited(_initializeCameras());
    } else {
      _isInitializing = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!widget.cameraEnabled) return;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      unawaited(_disposeCamera());
    } else if (state == AppLifecycleState.resumed && _controller == null) {
      unawaited(_initializeCameras());
    }
  }

  Future<void> _initializeCameras() async {
    if (mounted) {
      setState(() {
        _isInitializing = true;
        _cameraError = null;
      });
    }
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        throw StateError('Kamera tidak ditemukan pada perangkat ini.');
      }
      final frontIndex = _cameras.indexWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
      );
      if (frontIndex >= 0 && _controller == null) _cameraIndex = frontIndex;
      await _openCamera(_cameras[_cameraIndex]);
    } on CameraException catch (error) {
      _setCameraError(_friendlyCameraError(error));
    } catch (error) {
      _setCameraError('$error');
    } finally {
      if (mounted) setState(() => _isInitializing = false);
    }
  }

  Future<void> _openCamera(CameraDescription description) async {
    await _disposeCamera();
    final controller = CameraController(
      description,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );
    await controller.initialize();
    if (!mounted) {
      await controller.dispose();
      return;
    }
    setState(() => _controller = controller);
    if (_selectedTarget.isNotEmpty) {
      await _startTargetAnalysis(resetResults: false);
    }
  }

  void _initializeHandLandmarker() {
    if (_handLandmarker != null) return;
    _handSubscription?.cancel();
    _handLandmarker?.dispose();
    final landmarker = HandLandmarkerPlugin.create(
      numHands: 1,
      minHandDetectionConfidence: 0.35,
      delegate: HandLandmarkerDelegate.cpu,
    );
    _handLandmarker = landmarker;
    _handSubscription = landmarker.landmarkStream.listen(
      _acceptHandLandmarks,
      onError: (Object error) {
        _isHandDetectionPending = false;
        if (mounted) _showMessage('Hand detector gagal: $error');
      },
    );
  }

  void _acceptHandLandmarks(List<Hand> hands) {
    _isHandDetectionPending = false;
    if (!mounted || !_isAnalysisActive) return;
    final now = DateTime.now();
    final detectedHands = hands.where((hand) => hand.landmarks.isNotEmpty);
    final detected = detectedHands.isNotEmpty;
    if (detected) {
      _lastHandSeenAt = now;
      final landmarks = detectedHands.first.landmarks;
      _latestHandLandmarks = List<Offset>.unmodifiable(
        landmarks.map(
          (landmark) =>
              Offset(landmark.x.clamp(0.0, 1.0), landmark.y.clamp(0.0, 1.0)),
        ),
      );
    }
    final recentlyDetected =
        _lastHandSeenAt != null &&
        now.difference(_lastHandSeenAt!) <= _handPresenceWindow;
    if (!recentlyDetected) {
      _resetUnstablePrediction();
    }
    if (_handDetected != recentlyDetected) {
      setState(() => _handDetected = recentlyDetected);
    }
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2 ||
        _isSessionActive ||
        _isTargetAnalysisStarting ||
        _isInitializing) {
      return;
    }
    setState(() => _isInitializing = true);
    _cameraIndex = (_cameraIndex + 1) % _cameras.length;
    try {
      await _openCamera(_cameras[_cameraIndex]);
    } catch (error) {
      _setCameraError('$error');
    } finally {
      if (mounted) setState(() => _isInitializing = false);
    }
  }

  Future<void> _startSession() async {
    final controller = _controller;
    if (_selectedTarget.isNotEmpty ||
        controller == null ||
        !controller.value.isInitialized) {
      return;
    }
    try {
      await SignClassifier.instance.initialize();
      _initializeHandLandmarker();
      setState(() {
        _resetRecognitionState(clearFreeResults: true);
        _savedVideoPath = null;
        _isTargetAnalysisActive = false;
        _isSessionActive = true;
      });
      await controller.startVideoRecording(onAvailable: _onCameraFrame);
    } catch (error) {
      if (mounted) {
        setState(() => _isSessionActive = false);
        _showMessage('Tidak dapat memulai kamera: $error');
      }
    }
  }

  Future<void> _handleTargetChanged(String target) async {
    if (_isSessionActive || target == _selectedTarget) return;

    if (target.isEmpty) {
      setState(() {
        _selectedTarget = '';
        _isTargetAnalysisActive = false;
        _isTargetAnalysisStarting = true;
        _resetRecognitionState(clearTargetResults: true);
      });
      try {
        await _stopTargetImageStream();
      } finally {
        if (mounted) setState(() => _isTargetAnalysisStarting = false);
      }
      return;
    }

    final streamAlreadyActive =
        _isTargetAnalysisActive &&
        (_controller?.value.isStreamingImages ?? false);
    setState(() {
      _selectedTarget = target;
      _resetRecognitionState(clearTargetResults: true);
    });
    if (!streamAlreadyActive) {
      await _startTargetAnalysis(resetResults: false);
    }
  }

  Future<void> _startTargetAnalysis({bool resetResults = true}) async {
    final controller = _controller;
    if (_selectedTarget.isEmpty ||
        _isSessionActive ||
        _isTargetAnalysisStarting ||
        controller == null ||
        !controller.value.isInitialized) {
      return;
    }

    if (controller.value.isStreamingImages) {
      if (mounted) setState(() => _isTargetAnalysisActive = true);
      return;
    }

    if (mounted) {
      setState(() => _isTargetAnalysisStarting = true);
    } else {
      _isTargetAnalysisStarting = true;
    }
    try {
      await SignClassifier.instance.initialize();
      _initializeHandLandmarker();
      if (resetResults && mounted) {
        setState(() => _resetRecognitionState(clearTargetResults: true));
      }
      await controller.startImageStream(_onCameraFrame);
      if (!mounted || controller != _controller) return;
      if (_selectedTarget.isEmpty) {
        await controller.stopImageStream();
        return;
      }
      setState(() => _isTargetAnalysisActive = true);
    } catch (error) {
      if (mounted) {
        setState(() => _isTargetAnalysisActive = false);
        _showMessage('Deteksi otomatis tidak dapat dimulai: $error');
      }
    } finally {
      if (mounted) {
        setState(() => _isTargetAnalysisStarting = false);
      } else {
        _isTargetAnalysisStarting = false;
      }
    }
  }

  Future<void> _stopTargetImageStream() async {
    final controller = _controller;
    if (controller == null || !controller.value.isStreamingImages) return;
    try {
      await controller.stopImageStream();
    } catch (error) {
      if (mounted) _showMessage('Deteksi otomatis gagal dihentikan: $error');
    }
  }

  void _resetTargetResults() {
    if (_selectedTarget.isEmpty) return;
    setState(() => _resetRecognitionState(clearTargetResults: true));
  }

  void _resetRecognitionState({
    bool clearFreeResults = false,
    bool clearTargetResults = false,
  }) {
    if (clearFreeResults) _sessionLetters.clear();
    if (clearTargetResults) _validationPredictions.clear();
    _candidateLabel = null;
    _candidateCount = 0;
    _lastCommittedLabel = null;
    _releaseFrameCount = 0;
    _handDetected = false;
    _lastHandDetectionAt = null;
    _lastAnalysisAt = null;
    _lastHandSeenAt = null;
    _latestHandLandmarks = null;
    _isHandDetectionPending = false;
    _latestTargetPrediction = null;
    _latestTargetConfidence = null;
    _analysisGeneration++;
  }

  void _onCameraFrame(CameraImage cameraImage) {
    if (!_isAnalysisActive) return;
    final controller = _controller;
    if (controller == null) return;
    final rotation = ImagePreprocessor.effectivePortraitRotation(
      frameWidth: cameraImage.width,
      frameHeight: cameraImage.height,
      requestedRotationDegrees: _imageRotation(controller),
    );
    final now = DateTime.now();
    if (_isHandDetectionPending &&
        _lastHandDetectionAt != null &&
        now.difference(_lastHandDetectionAt!) >= _handDetectionTimeout) {
      _isHandDetectionPending = false;
    }
    if (!_isHandDetectionPending &&
        (_lastHandDetectionAt == null ||
            now.difference(_lastHandDetectionAt!) >= _handDetectionInterval)) {
      _lastHandDetectionAt = now;
      _isHandDetectionPending = true;
      try {
        _handLandmarker?.processFrame(cameraImage, rotation);
      } catch (error) {
        _isHandDetectionPending = false;
        if (mounted) {
          _showMessage('Hand detector gagal memproses frame: $error');
        }
      }
    }
    final handIsFresh =
        _lastHandSeenAt != null &&
        now.difference(_lastHandSeenAt!) <= _handPresenceWindow;
    if (!handIsFresh) {
      _latestHandLandmarks = null;
      _resetUnstablePrediction();
      return;
    }
    if (_isProcessingFrame) return;
    if (_lastAnalysisAt != null &&
        now.difference(_lastAnalysisAt!) < _analysisInterval) {
      return;
    }
    _lastAnalysisAt = now;
    _isProcessingFrame = true;
    final analysisGeneration = _analysisGeneration;

    final mirror =
        controller.description.lensDirection == CameraLensDirection.front;
    _lastFrameWidth = cameraImage.width;
    _lastFrameHeight = cameraImage.height;
    _lastFrameRotation = rotation;
    _lastFrameMirrored = mirror;
    final landmarks = _latestHandLandmarks;
    if (landmarks == null || landmarks.length != 21) {
      _isProcessingFrame = false;
      return;
    }
    SignClassifier.instance
        .classifyCameraFrame(
          cameraImage,
          rotationDegrees: rotation,
          mirrorHorizontally: mirror,
          normalizedLandmarks: landmarks,
        )
        .then((prediction) => _acceptPrediction(prediction, analysisGeneration))
        .catchError((Object error) {
          if (mounted) _showMessage('Frame gagal diproses: $error');
        })
        .whenComplete(() => _isProcessingFrame = false);
  }

  void _acceptPrediction(SignPrediction prediction, int analysisGeneration) {
    if (!mounted ||
        !_isAnalysisActive ||
        analysisGeneration != _analysisGeneration) {
      return;
    }
    unawaited(_saveCameraDiagnostic(prediction));

    if (_isTargetAnalysisActive) {
      setState(() {
        _latestTargetPrediction = prediction.label;
        _latestTargetConfidence = prediction.confidence;
      });
    }

    if (prediction.confidence < _minimumConfidence) {
      _candidateLabel = null;
      _candidateCount = 0;
      _releaseFrameCount++;
      return;
    }
    if (_lastCommittedLabel != null &&
        prediction.label != _lastCommittedLabel) {
      _releaseFrameCount++;
    }
    if (_candidateLabel == prediction.label) {
      _candidateCount++;
    } else {
      _candidateLabel = prediction.label;
      _candidateCount = 1;
    }
    final mayRepeatLastLetter =
        prediction.label == _lastCommittedLabel && _releaseFrameCount >= 2;
    if (_candidateCount >= _stableFramesRequired) {
      if (prediction.label != _lastCommittedLabel || mayRepeatLastLetter) {
        setState(() {
          if (_isSessionActive) {
            _sessionLetters.add(prediction.label);
          } else if (_isTargetAnalysisActive) {
            _validationPredictions.add(prediction.label);
          }
        });
        _lastCommittedLabel = prediction.label;
        _releaseFrameCount = 0;
      }
      _candidateCount = 0;
    }
  }

  void _resetUnstablePrediction() {
    _candidateLabel = null;
    _candidateCount = 0;
    _releaseFrameCount++;
  }

  Future<void> _saveCameraDiagnostic(SignPrediction finalPrediction) async {
    if (!kDebugMode) return;
    final now = DateTime.now();
    if (_lastCameraDiagnosticAt != null &&
        now.difference(_lastCameraDiagnosticAt!) < const Duration(seconds: 1)) {
      return;
    }
    _lastCameraDiagnosticAt = now;
    try {
      final classifier = SignClassifier.instance;
      final contextPng = classifier.lastContextInputPng;
      if (contextPng == null) return;
      final tightPng = classifier.lastTightInputPng;
      final metadata = <String, Object?>{
        'final_prediction': _predictionJson(finalPrediction),
        'context_prediction': _predictionJson(classifier.lastContextPrediction),
        'tight_prediction': _predictionJson(classifier.lastTightPrediction),
        'landmark_prediction': _predictionJson(
          classifier.lastLandmarkPrediction,
        ),
        'sensor_orientation': _controller?.description.sensorOrientation,
        'device_orientation': _controller?.value.deviceOrientation.name,
        'lens_direction': _controller?.description.lensDirection.name,
        'frame_width': _lastFrameWidth,
        'frame_height': _lastFrameHeight,
        'rotation_degrees': _lastFrameRotation,
        'mirrored': _lastFrameMirrored,
        'mediapipe_landmarks': _latestHandLandmarks
            ?.map((point) => <double>[point.dx, point.dy])
            .toList(growable: false),
      };
      final documents = await getApplicationDocumentsDirectory();
      final directory = Directory(
        '${documents.path}${Platform.pathSeparator}camera_diagnostic',
      );
      await directory.create(recursive: true);
      await File(
        '${directory.path}${Platform.pathSeparator}model_input_context.png',
      ).writeAsBytes(contextPng, flush: true);
      final tightPath =
          '${directory.path}${Platform.pathSeparator}model_input_tight.png';
      if (tightPng != null) {
        await File(tightPath).writeAsBytes(tightPng, flush: true);
      } else {
        final staleTightFile = File(tightPath);
        if (await staleTightFile.exists()) await staleTightFile.delete();
      }
      await File('${directory.path}${Platform.pathSeparator}metadata.json')
          .writeAsString(
            const JsonEncoder.withIndent('  ').convert(metadata),
            flush: true,
          );
    } catch (_) {
      _lastCameraDiagnosticAt = null;
    }
  }

  static Map<String, Object?>? _predictionJson(SignPrediction? prediction) {
    if (prediction == null) return null;
    return <String, Object?>{
      'label': prediction.label,
      'confidence': prediction.confidence,
    };
  }

  Future<void> _endSession() async {
    final controller = _controller;
    String? videoPath;
    try {
      if (controller?.value.isRecordingVideo ?? false) {
        final recording = await controller!.stopVideoRecording();
        videoPath = await _saveRecording(recording);
      } else if (controller?.value.isStreamingImages ?? false) {
        await controller!.stopImageStream();
      }
    } catch (error) {
      if (mounted) _showMessage('Rekaman video gagal disimpan: $error');
    }
    if (!mounted) return;
    setState(() {
      _isSessionActive = false;
      _isProcessingFrame = false;
      _handDetected = false;
      _latestHandLandmarks = null;
      _savedVideoPath = videoPath;
      _analysisGeneration++;
    });
    await _showSessionResult();
  }

  Future<String> _saveRecording(XFile recording) async {
    final documents = await getApplicationDocumentsDirectory();
    final recordingsDirectory = Directory(
      '${documents.path}${Platform.pathSeparator}recordings',
    );
    await recordingsDirectory.create(recursive: true);
    final timestamp = DateTime.now().toUtc().toIso8601String().replaceAll(
      RegExp('[:.]'),
      '-',
    );
    final destination =
        '${recordingsDirectory.path}${Platform.pathSeparator}asl_session_$timestamp.mp4';
    await File(recording.path).copy(destination);
    return destination;
  }

  Future<void> _showSessionResult() {
    final target = _selectedTarget;
    final displayedPredictions = target.isEmpty
        ? _sessionLetters
        : _validationPredictions;
    final sequence = displayedPredictions.join();
    final validationTotal = _validationPredictions.length;
    final validationCorrect = target.isEmpty
        ? 0
        : _validationPredictions.where((label) => label == target).length;
    final validationAccuracy = validationTotal == 0
        ? 0.0
        : validationCorrect / validationTotal * 100;
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.task_alt_rounded,
              size: 52,
              color: Color(0xFF0D5C46),
            ),
            const SizedBox(height: 12),
            Text(
              target.isEmpty ? 'Hasil sesi' : 'Hasil uji target $target',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              sequence.isEmpty ? 'Belum ada huruf yang stabil.' : sequence,
              textAlign: TextAlign.center,
              style: sequence.isEmpty
                  ? Theme.of(context).textTheme.bodyLarge
                  : Theme.of(context).textTheme.displayMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      letterSpacing: 6,
                    ),
            ),
            if (displayedPredictions.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                target.isEmpty
                    ? '${displayedPredictions.length} huruf dikenali tanpa spasi'
                    : '${displayedPredictions.length} percobaan stabil direkam',
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: displayedPredictions
                    .map((letter) => Chip(label: Text(letter)))
                    .toList(),
              ),
            ],
            if (target.isNotEmpty) ...[
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFE0EFE9),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  validationTotal == 0
                      ? 'Validasi target $target: belum ada prediksi stabil.'
                      : 'Validasi target $target: $validationCorrect/$validationTotal benar (${validationAccuracy.toStringAsFixed(1)}%).',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
            const SizedBox(height: 16),
            Text(
              _savedVideoPath == null
                  ? 'Video tidak berhasil disimpan.'
                  : 'Video tersimpan di:\n$_savedVideoPath',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  int _imageRotation(CameraController controller) {
    const deviceDegrees = <DeviceOrientation, int>{
      DeviceOrientation.portraitUp: 0,
      DeviceOrientation.landscapeLeft: 90,
      DeviceOrientation.portraitDown: 180,
      DeviceOrientation.landscapeRight: 270,
    };
    final captureOrientation =
        controller.value.lockedCaptureOrientation ??
        controller.value.deviceOrientation;
    final device = deviceDegrees[captureOrientation] ?? 0;
    final sensor = controller.description.sensorOrientation;
    return controller.description.lensDirection == CameraLensDirection.front
        ? (sensor + device) % 360
        : (sensor - device + 360) % 360;
  }

  Future<void> _disposeCamera() async {
    final controller = _controller;
    _controller = null;
    _isSessionActive = false;
    _isTargetAnalysisActive = false;
    _isTargetAnalysisStarting = false;
    _isHandDetectionPending = false;
    _analysisGeneration++;
    await _handSubscription?.cancel();
    _handSubscription = null;
    _handLandmarker?.dispose();
    _handLandmarker = null;
    if (controller == null) return;
    if (controller.value.isRecordingVideo) {
      final recording = await controller.stopVideoRecording();
      _savedVideoPath = await _saveRecording(recording);
    } else if (controller.value.isStreamingImages) {
      await controller.stopImageStream();
    }
    await controller.dispose();
  }

  void _setCameraError(String message) {
    if (!mounted) return;
    setState(() => _cameraError = message);
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _friendlyCameraError(CameraException error) {
    return switch (error.code) {
      'CameraAccessDenied' =>
        'Izin kamera ditolak. Aktifkan izin dari pengaturan.',
      'CameraAccessDeniedWithoutPrompt' =>
        'Izin kamera diblokir. Aktifkan izin dari pengaturan.',
      _ => 'Kamera gagal dibuka: ${error.description ?? error.code}',
    };
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_disposeCamera());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isTargetMode = _selectedTarget.isNotEmpty;
    final eventCount = _selectedTarget.isEmpty
        ? _sessionLetters.length
        : _validationPredictions.length;
    final validationCorrect = isTargetMode
        ? _validationPredictions
              .where((label) => label == _selectedTarget)
              .length
        : 0;
    return ColoredBox(
      key: const PageStorageKey('camera'),
      color: const Color(0xFF101714),
      child: Stack(
        fit: StackFit.expand,
        children: [
          _buildCameraPreview(),
          const IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0, 0.24, 0.62, 1],
                  colors: [
                    Color(0xB8000000),
                    Color(0x18000000),
                    Color(0x08000000),
                    Color(0xD9000000),
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            minimum: const EdgeInsets.fromLTRB(16, 12, 16, 102),
            child: Column(
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Kamera Latihan',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.5,
                            ),
                          ),
                          Text(
                            'Tangan boleh di mana saja dalam frame',
                            style: TextStyle(
                              color: Color(0xFFDDE8E3),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _RoundCameraButton(
                      tooltip: 'Ganti kamera',
                      onPressed:
                          _cameras.length > 1 &&
                              !_isSessionActive &&
                              !_isTargetAnalysisStarting
                          ? _switchCamera
                          : null,
                      icon: Icons.cameraswitch_rounded,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(child: _buildModeSelector()),
                    const SizedBox(width: 10),
                    _StatusPill(
                      active: _isAnalysisActive,
                      handDetected: _handDetected,
                    ),
                  ],
                ),
                const Spacer(),
                _LiveResultCard(
                  active: _isAnalysisActive,
                  handDetected: _handDetected,
                  eventCount: eventCount,
                  target: _selectedTarget,
                  latestPrediction: _latestTargetPrediction,
                  latestConfidence: _latestTargetConfidence,
                  correctCount: validationCorrect,
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  height: 58,
                  child: isTargetMode
                      ? FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFE6A23C),
                            foregroundColor: const Color(0xFF1A160D),
                          ),
                          onPressed: _resetTargetResults,
                          icon: const Icon(Icons.refresh_rounded),
                          label: Text('Reset hasil uji $_selectedTarget'),
                        )
                      : _isSessionActive
                      ? FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFC83B31),
                            foregroundColor: Colors.white,
                          ),
                          onPressed: _endSession,
                          icon: const Icon(Icons.stop_circle_rounded),
                          label: const Text('Akhiri dan lihat hasil'),
                        )
                      : FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF16A374),
                            foregroundColor: Colors.white,
                          ),
                          onPressed:
                              (_controller?.value.isInitialized ?? false) &&
                                  !_isTargetAnalysisStarting
                              ? _startSession
                              : null,
                          icon: const Icon(Icons.play_circle_fill_rounded),
                          label: const Text('Mulai latihan bebas'),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeSelector() {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: _selectedTarget,
            isExpanded: true,
            dropdownColor: const Color(0xFF17231F),
            borderRadius: BorderRadius.circular(18),
            iconEnabledColor: Colors.white,
            iconDisabledColor: Colors.white38,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
            items: [
              const DropdownMenuItem(
                value: '',
                child: Text('MODE: LATIHAN BEBAS'),
              ),
              ..._supportedLabels.map(
                (label) => DropdownMenuItem(
                  value: label,
                  child: Text('MODE UJI: HURUF $label'),
                ),
              ),
            ],
            onChanged: _isSessionActive || _isTargetAnalysisStarting
                ? null
                : (value) => unawaited(_handleTargetChanged(value ?? '')),
          ),
        ),
      ),
    );
  }

  Widget _buildCameraPreview() {
    if (!widget.cameraEnabled) {
      return const Center(
        child: Text(
          'Kamera dinonaktifkan untuk pengujian.',
          style: TextStyle(color: Colors.white),
        ),
      );
    }
    if (_isInitializing) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF65E6A7)),
      );
    }
    if (_cameraError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.no_photography_outlined,
                color: Colors.white,
                size: 48,
              ),
              const SizedBox(height: 12),
              Text(
                _cameraError!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
                onPressed: _initializeCameras,
                child: const Text('Coba lagi'),
              ),
            ],
          ),
        ),
      );
    }
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const Center(
        child: Text(
          'Kamera belum siap.',
          style: TextStyle(color: Colors.white),
        ),
      );
    }
    return _CoverCameraPreview(controller: controller);
  }
}

class _RoundCameraButton extends StatelessWidget {
  const _RoundCameraButton({
    required this.tooltip,
    required this.onPressed,
    required this.icon,
  });

  final String tooltip;
  final VoidCallback? onPressed;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      style: IconButton.styleFrom(
        backgroundColor: Colors.black.withValues(alpha: 0.62),
        foregroundColor: Colors.white,
        disabledBackgroundColor: Colors.black.withValues(alpha: 0.30),
        disabledForegroundColor: Colors.white38,
        minimumSize: const Size.square(48),
      ),
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon),
    );
  }
}

class _CoverCameraPreview extends StatelessWidget {
  const _CoverCameraPreview({required this.controller});

  final CameraController controller;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<CameraValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final previewSize = value.previewSize;
        if (previewSize == null) return CameraPreview(controller);

        // Camera sizes use sensor (landscape) orientation. FittedBox crops the
        // excess while CameraX handles device rotation in its native preview.
        return ClipRect(
          child: FittedBox(
            fit: BoxFit.cover,
            alignment: Alignment.center,
            child: SizedBox(
              width: previewSize.height,
              height: previewSize.width,
              child: CameraPreview(controller),
            ),
          ),
        );
      },
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.active, required this.handDetected});

  final bool active;
  final bool handDetected;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              active && handDetected
                  ? Icons.back_hand_rounded
                  : active
                  ? Icons.search_rounded
                  : Icons.pause_circle_outline,
              size: 11,
              color: active && handDetected
                  ? const Color(0xFF65E6A7)
                  : active
                  ? const Color(0xFFFFC65B)
                  : Colors.white,
            ),
            const SizedBox(width: 7),
            Text(
              active && handDetected
                  ? 'TANGAN TERDETEKSI'
                  : active
                  ? 'CARI TANGAN'
                  : 'SIAP',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LiveResultCard extends StatelessWidget {
  const _LiveResultCard({
    required this.active,
    required this.handDetected,
    required this.eventCount,
    required this.target,
    required this.latestPrediction,
    required this.latestConfidence,
    required this.correctCount,
  });

  final bool active;
  final bool handDetected;
  final int eventCount;
  final String target;
  final String? latestPrediction;
  final double? latestConfidence;
  final int correctCount;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.68),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 62,
              height: 62,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Text(
                target.isNotEmpty
                    ? handDetected
                          ? _predictionIsReliable
                                ? latestPrediction ?? '?'
                                : '?'
                          : '?'
                    : active
                    ? '$eventCount'
                    : '-',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: const Color(0xFF65E6A7),
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _description,
                    style: const TextStyle(
                      color: Color(0xFFDDE8E3),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String get _title {
    if (target.isNotEmpty) {
      if (!active) return 'Deteksi otomatis menunggu kamera';
      if (!handDetected) return 'Tampilkan tangan untuk huruf $target';
      if (latestPrediction == null) return 'Menganalisis target $target';
      if (!_predictionIsReliable) return 'Belum yakin, tahan pose sebentar';
      return latestPrediction == target
          ? 'Benar: terdeteksi $target'
          : 'Belum tepat: terdeteksi $latestPrediction';
    }
    if (!active) {
      return 'Tekan Mulai untuk latihan bebas';
    }
    if (!handDetected) {
      return 'Tampilkan tangan ke kamera';
    }
    return 'Tangan terdeteksi';
  }

  String get _description {
    if (target.isNotEmpty) {
      if (!active) {
        return 'Deteksi dimulai otomatis saat kamera siap; video tidak direkam.';
      }
      if (!handDetected) {
        return 'Tangan boleh di mana saja; pastikan telapak dan jari tidak terpotong.';
      }
      if (latestPrediction == null || latestConfidence == null) {
        return 'Tahan pose sebentar sampai prediksi muncul.';
      }
      final confidence = (latestConfidence! * 100).toStringAsFixed(1);
      if (!_predictionIsReliable) {
        return 'Keyakinan $confidence% masih di bawah 60% dan belum dihitung.';
      }
      return '$correctCount/$eventCount percobaan stabil benar | keyakinan $confidence%';
    }
    if (!active) {
      return 'Semua huruf stabil akan disusun setelah sesi diakhiri.';
    }
    if (!handDetected) {
      return 'Boleh di bagian mana saja; pastikan telapak dan jari tidak terpotong.';
    }
    return '$eventCount huruf tersimpan. Hasil disembunyikan sampai sesi diakhiri.';
  }

  bool get _predictionIsReliable =>
      latestPrediction != null &&
      latestConfidence != null &&
      latestConfidence! >= 0.60;
}
