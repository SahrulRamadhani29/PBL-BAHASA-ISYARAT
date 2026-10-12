import 'dart:async';
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:camera_android_camerax/camera_android_camerax.dart';
// The pinned CameraX API exposes Preview through its public backend instance.
// These detached proxies let us test its native metadata without Android.
// ignore: implementation_imports
import 'package:camera_android_camerax/src/camerax_library.dart'
    show CameraSize, Preview, ResolutionInfo;
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pbl_bahasa_isyarat/services/camera_preview_size.dart';

const _description = CameraDescription(
  name: 'front',
  lensDirection: CameraLensDirection.front,
  sensorOrientation: 270,
);

class _Size extends CameraSize {
  _Size(int width, int height)
    : super.pigeon_detached(width: width, height: height);
}

class _Resolution extends ResolutionInfo {
  _Resolution(int width, int height)
    : super.pigeon_detached(resolution: _Size(width, height));
}

class _Preview extends Preview {
  _Preview(this.readResolution) : super.pigeon_detached();

  final Future<ResolutionInfo?> Function() readResolution;

  @override
  Future<ResolutionInfo?> getResolutionInfo() => readResolution();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CameraPlatform previousPlatform;
  late AndroidCameraCameraX backend;
  late CameraController controller;

  setUp(() {
    previousPlatform = CameraPlatform.instance;
    backend = AndroidCameraCameraX();
    CameraPlatform.instance = backend;
    controller = CameraController(_description, ResolutionPreset.medium);
    controller.value = controller.value.copyWith(
      isInitialized: true,
      previewSize: const Size(720, 480),
    );
  });

  tearDown(() async {
    await controller.dispose();
    await backend.videoRecordingEventStreamQueue.cancel();
    await backend.cameraEventStreamController.close();
    CameraPlatform.instance = previousPlatform;
  });

  test('native preview dimensions follow recording reconfiguration', () async {
    ResolutionInfo? nativeResolution = _Resolution(720, 480);
    backend.preview = _Preview(() async => nativeResolution);

    // Opening, binding video, and unbinding video can choose different ratios.
    for (final size in [
      const Size(720, 480),
      const Size(640, 480),
      const Size(1280, 720),
      const Size(720, 480),
    ]) {
      nativeResolution = _Resolution(size.width.toInt(), size.height.toInt());
      await synchronizeCameraPreviewSize(controller, isCurrent: () => true);
      expect(controller.value.previewSize, size);
    }
  });

  test('inactive controller does not request native metadata', () async {
    var requests = 0;
    backend.preview = _Preview(() async {
      requests++;
      return _Resolution(640, 480);
    });
    await synchronizeCameraPreviewSize(controller, isCurrent: () => false);
    expect(requests, 0);
  });

  test(
    'disposal while awaiting metadata does not update old controller',
    () async {
      final resolution = Completer<ResolutionInfo?>();
      backend.preview = _Preview(() => resolution.future);
      var current = true;
      final pending = synchronizeCameraPreviewSize(
        controller,
        isCurrent: () => current,
      );
      current = false;
      await controller.dispose();
      resolution.complete(_Resolution(640, 480));
      await pending;
      expect(controller.value.previewSize, const Size(720, 480));
    },
  );

  test('camera switch ignores metadata from the previous preview', () async {
    final resolution = Completer<ResolutionInfo?>();
    backend.preview = _Preview(() => resolution.future);
    final pending = synchronizeCameraPreviewSize(
      controller,
      isCurrent: () => true,
    );
    backend.preview = _Preview(() async => _Resolution(1280, 720));
    resolution.complete(_Resolution(640, 480));
    await pending;
    expect(controller.value.previewSize, const Size(720, 480));

    await synchronizeCameraPreviewSize(controller, isCurrent: () => true);
    expect(controller.value.previewSize, const Size(1280, 720));
  });

  test(
    'missing or invalid native dimensions preserve the last valid size',
    () async {
      for (final resolution in [
        null,
        _Resolution(0, 480),
        _Resolution(640, 0),
      ]) {
        backend.preview = _Preview(() async => resolution);
        await synchronizeCameraPreviewSize(controller, isCurrent: () => true);
        expect(controller.value.previewSize, const Size(720, 480));
      }
    },
  );

  test(
    'metadata failure does not fail a successfully started recording',
    () async {
      controller.value = controller.value.copyWith(isRecordingVideo: true);
      backend.preview = _Preview(() async => throw StateError('Camera closed'));
      await synchronizeCameraPreviewSize(controller, isCurrent: () => true);
      expect(controller.value.isRecordingVideo, isTrue);
      expect(controller.value.previewSize, const Size(720, 480));
    },
  );

  test('other camera backends keep their existing preview metadata', () async {
    CameraPlatform.instance = previousPlatform;
    await synchronizeCameraPreviewSize(controller, isCurrent: () => true);
    expect(controller.value.previewSize, const Size(720, 480));
  });
}
