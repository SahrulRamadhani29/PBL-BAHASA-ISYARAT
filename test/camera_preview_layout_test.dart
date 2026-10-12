import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pbl_bahasa_isyarat/widgets/full_bleed_camera_preview.dart';

const _viewportKey = ValueKey('preview-viewport');
const _nativePreviewKey = ValueKey('native-preview');

class _PreviewController extends CameraController {
  _PreviewController(CameraLensDirection direction)
    : super(
        CameraDescription(
          name: direction.name,
          lensDirection: direction,
          sensorOrientation: direction == CameraLensDirection.front ? 270 : 90,
        ),
        ResolutionPreset.medium,
        enableAudio: false,
      );

  // Use CameraPreview's real layout and orientation handling, replacing only
  // the native texture. No physical camera or platform channels are needed.
  @override
  Widget buildPreview() {
    return const ColoredBox(
      key: _nativePreviewKey,
      color: Colors.green,
      child: Center(child: SizedBox.square(dimension: 80)),
    );
  }
}

CameraValue _state(
  CameraDescription description, {
  Size? previewSize = const Size(720, 480),
  bool initialized = true,
  DeviceOrientation orientation = DeviceOrientation.portraitUp,
  DeviceOrientation? captureOrientation,
  DeviceOrientation? recordingOrientation,
  DeviceOrientation? pausedOrientation,
  bool recording = false,
  bool streaming = false,
}) {
  return CameraValue(
    description: description,
    isInitialized: initialized,
    previewSize: previewSize,
    isRecordingVideo: recording,
    isStreamingImages: streaming,
    isTakingPicture: false,
    isRecordingPaused: false,
    flashMode: FlashMode.auto,
    exposureMode: ExposureMode.auto,
    focusMode: FocusMode.auto,
    exposurePointSupported: false,
    focusPointSupported: false,
    deviceOrientation: orientation,
    lockedCaptureOrientation: captureOrientation,
    recordingOrientation: recordingOrientation,
    isPreviewPaused: pausedOrientation != null,
    previewPauseOrientation: pausedOrientation,
  );
}

Future<void> _mount(
  WidgetTester tester,
  _PreviewController controller,
  Size viewport,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Center(
        child: SizedBox(
          key: _viewportKey,
          width: viewport.width,
          height: viewport.height,
          child: FullBleedCameraPreview(controller: controller),
        ),
      ),
    ),
  );
}

void _expectUndistortedCover(
  WidgetTester tester, {
  required Size viewport,
  required Size source,
}) {
  final fitted = tester.renderObject<RenderFittedBox>(find.byType(FittedBox));
  final viewportBox = tester.renderObject<RenderBox>(find.byKey(_viewportKey));
  final native = tester.renderObject<RenderBox>(find.byKey(_nativePreviewKey));
  expect(tester.getSize(find.byType(CameraPreview)), source);
  expect(fitted.child!.size, source);
  expect(fitted.size, viewport);

  // Rotation may exchange or negate axes, but their lengths must remain
  // identical. Unequal values would deform a circle into an ellipse.
  final matrix = native.getTransformTo(viewportBox);
  final values = matrix.storage;
  final scaleX = math.sqrt(values[0] * values[0] + values[1] * values[1]);
  final scaleY = math.sqrt(values[4] * values[4] + values[5] * values[5]);
  final expectedScale = math.max(
    viewport.width / source.width,
    viewport.height / source.height,
  );
  expect(scaleX, closeTo(expectedScale, 0.000001));
  expect(scaleY, closeTo(expectedScale, 0.000001));
  expect(scaleX, closeTo(scaleY, 0.000001));

  final sourceTransform = fitted.child!.getTransformTo(viewportBox);
  final visibleImage = MatrixUtils.transformRect(
    sourceTransform,
    Offset.zero & source,
  );
  expect(visibleImage.left, lessThanOrEqualTo(0.000001));
  expect(visibleImage.top, lessThanOrEqualTo(0.000001));
  expect(visibleImage.right, greaterThanOrEqualTo(viewport.width - 0.000001));
  expect(visibleImage.bottom, greaterThanOrEqualTo(viewport.height - 0.000001));
  expect(visibleImage.center.dx, closeTo(viewport.width / 2, 0.000001));
  expect(visibleImage.center.dy, closeTo(viewport.height / 2, 0.000001));
  expect(tester.widget<FittedBox>(find.byType(FittedBox)).fit, BoxFit.cover);
  expect(find.byType(ClipRect), findsOneWidget);
  expect(tester.takeException(), isNull);
}

void main() {
  for (final direction in [
    CameraLensDirection.front,
    CameraLensDirection.back,
  ]) {
    testWidgets(
      'uniform camera cover for ${direction.name} and varied viewports',
      (tester) async {
        final controller = _PreviewController(direction);
        addTearDown(controller.dispose);
        controller.value = _state(controller.description);
        for (final viewport in [
          const Size(360, 580),
          const Size(360, 560),
          const Size(600, 360),
          const Size(500, 500),
        ]) {
          await _mount(tester, controller, viewport);
          _expectUndistortedCover(
            tester,
            viewport: viewport,
            source: const Size(480, 720),
          );
        }
      },
    );

    testWidgets(
      'orientation transitions stay proportional for ${direction.name}',
      (tester) async {
        final controller = _PreviewController(direction);
        addTearDown(controller.dispose);
        const viewport = Size(360, 580);
        controller.value = _state(controller.description);
        await _mount(tester, controller, viewport);

        // Without a capture lock, follow landscape orientation as CameraPreview
        // does. A portrait-only outer size would squeeze the native texture.
        for (final orientation in [
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]) {
          controller.value = _state(
            controller.description,
            orientation: orientation,
            streaming: true,
          );
          await tester.pump();
          _expectUndistortedCover(
            tester,
            viewport: viewport,
            source: const Size(720, 480),
          );
        }

        // A portrait capture lock wins over an orientation event while streaming.
        controller.value = _state(
          controller.description,
          orientation: DeviceOrientation.landscapeLeft,
          captureOrientation: DeviceOrientation.portraitUp,
          streaming: true,
        );
        await tester.pump();
        _expectUndistortedCover(
          tester,
          viewport: viewport,
          source: const Size(480, 720),
        );

        // Recording retains the orientation chosen when it started. It takes
        // precedence over subsequent capture locks and pause states.
        controller.value = _state(
          controller.description,
          captureOrientation: DeviceOrientation.portraitUp,
          recording: true,
          recordingOrientation: DeviceOrientation.landscapeRight,
          pausedOrientation: DeviceOrientation.portraitDown,
          streaming: true,
        );
        await tester.pump();
        _expectUndistortedCover(
          tester,
          viewport: viewport,
          source: const Size(720, 480),
        );

        controller.value = _state(
          controller.description,
          orientation: DeviceOrientation.landscapeRight,
          captureOrientation: DeviceOrientation.portraitUp,
        );
        await tester.pump();
        _expectUndistortedCover(
          tester,
          viewport: viewport,
          source: const Size(480, 720),
        );

        // A paused preview preserves its own orientation until it resumes.
        controller.value = _state(
          controller.description,
          captureOrientation: DeviceOrientation.portraitUp,
          pausedOrientation: DeviceOrientation.landscapeLeft,
        );
        await tester.pump();
        _expectUndistortedCover(
          tester,
          viewport: viewport,
          source: const Size(720, 480),
        );
        controller.value = _state(controller.description);
        await tester.pump();
        _expectUndistortedCover(
          tester,
          viewport: viewport,
          source: const Size(480, 720),
        );
      },
    );

    testWidgets('new preview resolution rebuilds cover for ${direction.name}', (
      tester,
    ) async {
      final controller = _PreviewController(direction);
      addTearDown(controller.dispose);
      const viewport = Size(360, 580);
      controller.value = _state(controller.description);
      await _mount(tester, controller, viewport);
      for (final size in [
        const Size(720, 480),
        const Size(640, 480),
        const Size(1280, 720),
      ]) {
        controller.value = _state(
          controller.description,
          previewSize: size,
          captureOrientation: DeviceOrientation.portraitUp,
          recording: true,
          recordingOrientation: DeviceOrientation.portraitUp,
          streaming: true,
        );
        await tester.pump();
        _expectUndistortedCover(
          tester,
          viewport: viewport,
          source: Size(size.height, size.width),
        );
      }
    });
  }

  testWidgets('unavailable preview never uses a stretched fallback', (
    tester,
  ) async {
    final controller = _PreviewController(CameraLensDirection.front);
    addTearDown(controller.dispose);
    const viewport = Size(360, 580);
    await _mount(tester, controller, viewport);
    expect(find.byType(CameraPreview), findsNothing);
    for (final size in <Size?>[
      null,
      Size.zero,
      const Size(-1, 480),
      const Size(double.infinity, 480),
      const Size(640, double.nan),
    ]) {
      controller.value = _state(controller.description, previewSize: size);
      await tester.pump();
      expect(find.byType(CameraPreview), findsNothing);
      expect(find.byType(FittedBox), findsNothing);
      expect(tester.getSize(find.byKey(_viewportKey)), viewport);
      expect(tester.takeException(), isNull);
    }
    controller.value = _state(controller.description);
    await tester.pump();
    _expectUndistortedCover(
      tester,
      viewport: viewport,
      source: const Size(480, 720),
    );
  });
}
