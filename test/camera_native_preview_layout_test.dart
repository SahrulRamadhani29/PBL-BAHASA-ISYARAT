import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pbl_bahasa_isyarat/services/camera_preview_size.dart';
import 'package:pbl_bahasa_isyarat/widgets/full_bleed_camera_preview.dart';

const _viewportKey = ValueKey('native-preview-viewport');

CameraController _controller({
  CameraLensDirection lens = CameraLensDirection.front,
  int sensor = 270,
}) {
  final controller = CameraController(
    CameraDescription(
      name: '${lens.name}-$sensor',
      lensDirection: lens,
      sensorOrientation: sensor,
    ),
    ResolutionPreset.medium,
    enableAudio: false,
  );
  // Setting a value avoids opening a native camera in a host widget test.
  controller.value = controller.value.copyWith(
    isInitialized: true,
    previewSize: const Size(720, 480),
  );
  return controller;
}

CameraPreviewGeometry _geometry({
  Size buffer = const Size(720, 480),
  Rect? crop,
  int rotation = 270,
  bool mirrored = false,
  bool automatic = false,
  bool cameraTransform = true,
}) => CameraPreviewGeometry(
  bufferSize: buffer,
  cropRect: crop ?? Offset.zero & buffer,
  rotationDegrees: rotation,
  mirrored: mirrored,
  handlesCropAndRotation: automatic,
  hasCameraTransform: cameraTransform,
);

Future<void> _mount(
  WidgetTester tester,
  CameraController controller,
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

/// Expected position calculated from the native contract, independently of
/// widget transforms: crop buffer first, rotate clockwise, then mirror upright.
Offset _expectedManualPoint(
  Offset bufferPoint,
  CameraPreviewGeometry geometry,
) {
  final x = bufferPoint.dx - geometry.cropRect.left;
  final y = bufferPoint.dy - geometry.cropRect.top;
  final width = geometry.cropRect.width;
  final height = geometry.cropRect.height;
  final rotated = switch (geometry.rotationDegrees) {
    0 => Offset(x, y),
    90 => Offset(height - y, x),
    180 => Offset(width - x, height - y),
    270 => Offset(y, width - x),
    _ => throw StateError('Unsupported test rotation'),
  };
  return geometry.mirrored
      ? Offset(geometry.uprightSize.width - rotated.dx, rotated.dy)
      : rotated;
}

void _expectPointNear(Offset actual, Offset expected) {
  expect(actual.dx, closeTo(expected.dx, 0.000001));
  expect(actual.dy, closeTo(expected.dy, 0.000001));
}

void _expectNativeGeometry(
  WidgetTester tester, {
  required CameraPreviewGeometry geometry,
  required Size viewport,
}) {
  final fitted = tester.renderObject<RenderFittedBox>(find.byType(FittedBox));
  final texture = tester.renderObject<RenderBox>(find.byType(Texture));
  final viewportBox = tester.renderObject<RenderBox>(find.byKey(_viewportKey));
  final transform = texture.getTransformTo(viewportBox);
  final values = transform.storage;
  final scaleX = math.sqrt(values[0] * values[0] + values[1] * values[1]);
  final scaleY = math.sqrt(values[4] * values[4] + values[5] * values[5]);
  final sourceSize = geometry.uprightSize;
  final scale = math.max(
    viewport.width / sourceSize.width,
    viewport.height / sourceSize.height,
  );
  final coverOffset = Offset(
    (viewport.width - sourceSize.width * scale) / 2,
    (viewport.height - sourceSize.height * scale) / 2,
  );

  expect(fitted.size, viewport);
  expect(fitted.child!.size, sourceSize);
  expect(
    texture.size,
    geometry.transformManually ? geometry.bufferSize : sourceSize,
  );
  expect(scaleX, closeTo(scale, 0.000001));
  expect(scaleY, closeTo(scale, 0.000001));
  expect(scaleX, closeTo(scaleY, 0.000001));
  expect(tester.widget<FittedBox>(find.byType(FittedBox)).fit, BoxFit.cover);
  expect(find.byType(CameraPreview), findsNothing);

  final sourceTransform = fitted.child!.getTransformTo(viewportBox);
  final imageBounds = MatrixUtils.transformRect(
    sourceTransform,
    Offset.zero & sourceSize,
  );
  expect(imageBounds.left, lessThanOrEqualTo(0.000001));
  expect(imageBounds.top, lessThanOrEqualTo(0.000001));
  expect(imageBounds.right, greaterThanOrEqualTo(viewport.width - 0.000001));
  expect(imageBounds.bottom, greaterThanOrEqualTo(viewport.height - 0.000001));

  if (geometry.transformManually) {
    // Corners and center check axis directions, mirroring order and crop
    // offsets, beyond checking only the aspect ratio of the outer container.
    final crop = geometry.cropRect;
    for (final point in [
      crop.topLeft,
      crop.topRight,
      crop.bottomLeft,
      crop.bottomRight,
      crop.center,
    ]) {
      final expected =
          _expectedManualPoint(point, geometry) * scale + coverOffset;
      _expectPointNear(MatrixUtils.transformPoint(transform, point), expected);
    }
    final determinant = values[0] * values[5] - values[1] * values[4];
    expect(
      determinant,
      closeTo((geometry.mirrored ? -1 : 1) * scale * scale, 0.000001),
    );
    expect(find.byType(RotatedBox), findsOneWidget);
  } else {
    // The engine transforms a direct SurfaceTexture camera. No Dart rotation,
    // crop displacement or mirror may be applied for a second time.
    expect(find.byType(RotatedBox), findsNothing);
    expect(find.byType(Transform), findsNothing);
    expect(values[0], closeTo(scale, 0.000001));
    expect(values[1], closeTo(0, 0.000001));
    expect(values[4], closeTo(0, 0.000001));
    expect(values[5], closeTo(scale, 0.000001));
    _expectPointNear(
      MatrixUtils.transformPoint(transform, Offset.zero),
      coverOffset,
    );
  }
  expect(tester.takeException(), isNull);
}

void main() {
  for (final lens in [CameraLensDirection.front, CameraLensDirection.back]) {
    testWidgets('${lens.name}: native landscape buffer stays proportional', (
      tester,
    ) async {
      final controller = _controller(lens: lens);
      addTearDown(controller.dispose);
      final geometry = _geometry(mirrored: lens == CameraLensDirection.front);
      cameraPreviewGeometry(controller).value = geometry;
      expect(geometry.uprightSize, const Size(480, 720));
      for (final viewport in [
        const Size(360, 580),
        const Size(600, 360),
        const Size(500, 500),
      ]) {
        await _mount(tester, controller, viewport);
        _expectNativeGeometry(tester, geometry: geometry, viewport: viewport);
      }
    });
  }

  testWidgets('already portrait StreamSharing buffer is not rotated again', (
    tester,
  ) async {
    final controller = _controller(sensor: 270);
    addTearDown(controller.dispose);
    const viewport = Size(360, 580);
    await _mount(tester, controller, viewport);
    for (final mirrored in [false, true]) {
      final geometry = _geometry(
        buffer: const Size(480, 720),
        rotation: 0,
        mirrored: mirrored,
        cameraTransform: false,
      );
      cameraPreviewGeometry(controller).value = geometry;
      await tester.pump();
      _expectNativeGeometry(tester, geometry: geometry, viewport: viewport);
      expect(geometry.uprightSize, const Size(480, 720));
    }
  });

  testWidgets('all remaining rotations and mirrors follow native coordinates', (
    tester,
  ) async {
    final controller = _controller(sensor: 0);
    addTearDown(controller.dispose);
    const viewport = Size(360, 580);
    cameraPreviewGeometry(controller).value = _geometry();
    await _mount(tester, controller, viewport);
    for (final rotation in [0, 90, 180, 270]) {
      for (final mirrored in [false, true]) {
        final geometry = _geometry(rotation: rotation, mirrored: mirrored);
        cameraPreviewGeometry(controller).value = geometry;
        await tester.pump();
        _expectNativeGeometry(tester, geometry: geometry, viewport: viewport);
      }
    }
  });

  testWidgets('automatic direct camera texture gets no extra transforms', (
    tester,
  ) async {
    final controller = _controller(sensor: 180);
    addTearDown(controller.dispose);
    const viewport = Size(360, 580);
    cameraPreviewGeometry(controller).value = _geometry();
    await _mount(tester, controller, viewport);
    for (final rotation in [0, 90, 180, 270]) {
      final geometry = _geometry(
        rotation: rotation,
        mirrored: true,
        automatic: true,
      );
      cameraPreviewGeometry(controller).value = geometry;
      await tester.pump();
      expect(geometry.transformManually, isFalse);
      _expectNativeGeometry(tester, geometry: geometry, viewport: viewport);
    }
  });

  testWidgets('SurfaceTexture copied by GL applies only remaining transform', (
    tester,
  ) async {
    final controller = _controller();
    addTearDown(controller.dispose);
    const viewport = Size(360, 580);
    final geometry = _geometry(
      buffer: const Size(480, 720),
      crop: const Rect.fromLTWH(40, 70, 400, 600),
      rotation: 180,
      mirrored: true,
      automatic: true,
      cameraTransform: false,
    );
    cameraPreviewGeometry(controller).value = geometry;
    await _mount(tester, controller, viewport);
    expect(geometry.transformManually, isTrue);
    _expectNativeGeometry(tester, geometry: geometry, viewport: viewport);
  });

  testWidgets('non-full crop retains offsets and ratio through rotation', (
    tester,
  ) async {
    final controller = _controller();
    addTearDown(controller.dispose);
    const viewport = Size(360, 580);
    cameraPreviewGeometry(controller).value = _geometry();
    await _mount(tester, controller, viewport);
    for (final rotation in [0, 90, 180, 270]) {
      for (final mirrored in [false, true]) {
        final geometry = _geometry(
          crop: const Rect.fromLTWH(70, 30, 480, 300),
          rotation: rotation,
          mirrored: mirrored,
        );
        cameraPreviewGeometry(controller).value = geometry;
        await tester.pump();
        _expectNativeGeometry(tester, geometry: geometry, viewport: viewport);
      }
    }
  });

  testWidgets('recording transitions preserve upright scene dimensions', (
    tester,
  ) async {
    final controller = _controller();
    addTearDown(controller.dispose);
    const viewport = Size(360, 580);
    final initial = _geometry(mirrored: true);
    final recording = _geometry(
      buffer: const Size(480, 720),
      rotation: 0,
      mirrored: false,
      cameraTransform: false,
    );
    cameraPreviewGeometry(controller).value = initial;
    await _mount(tester, controller, viewport);
    for (final geometry in [initial, recording, initial]) {
      cameraPreviewGeometry(controller).value = geometry;
      await tester.pump();
      expect(geometry.uprightSize, const Size(480, 720));
      _expectNativeGeometry(tester, geometry: geometry, viewport: viewport);
    }
  });
}
