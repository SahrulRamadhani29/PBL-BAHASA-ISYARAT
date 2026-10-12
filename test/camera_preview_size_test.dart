import 'dart:async';

import 'package:camera/camera.dart';
import 'package:camera_android_camerax/camera_android_camerax.dart';
// Detached proxies exercise the pinned backend without an Android camera.
// ignore: implementation_imports
import 'package:camera_android_camerax/src/camerax_library.dart' show Preview;
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pbl_bahasa_isyarat/services/camera_preview_size.dart';

const _channel = MethodChannel('latih_isyarat/camera_preview');
const _description = CameraDescription(
  name: 'front',
  lensDirection: CameraLensDirection.front,
  sensorOrientation: 270,
);

class _Preview extends Preview {
  _Preview() : super.pigeon_detached();
}

class _OtherBackend extends CameraPlatform {}

Map<String, Object?> _nativeGeometry({
  int width = 720,
  int height = 480,
  int rotation = 90,
  Rect? crop,
  bool mirrored = true,
  bool handlesCropAndRotation = true,
  bool hasCameraTransform = true,
}) {
  final bounds =
      crop ?? Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
  return {
    'width': width,
    'height': height,
    'rotation_degrees': rotation,
    'crop_left': bounds.left,
    'crop_top': bounds.top,
    'crop_right': bounds.right,
    'crop_bottom': bounds.bottom,
    'mirrored': mirrored,
    'handles_crop_and_rotation': handlesCropAndRotation,
    'has_camera_transform': hasCameraTransform,
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  var nextPreviewId = 100000;

  late CameraPlatform previousPlatform;
  late AndroidCameraCameraX backend;
  late CameraController controller;
  late List<MethodCall> requests;
  late Future<Object?> Function(MethodCall) readGeometry;

  _Preview registerPreview() {
    final preview = _Preview();
    preview.pigeon_instanceManager.addHostCreatedInstance(
      preview,
      nextPreviewId++,
    );
    return preview;
  }

  setUp(() {
    previousPlatform = CameraPlatform.instance;
    backend = AndroidCameraCameraX();
    CameraPlatform.instance = backend;
    controller = CameraController(_description, ResolutionPreset.medium);
    controller.value = controller.value.copyWith(
      isInitialized: true,
      previewSize: const Size(720, 480),
    );
    backend.preview = registerPreview();
    requests = [];
    readGeometry = (_) async => _nativeGeometry();
    messenger.setMockMethodCallHandler(_channel, (call) async {
      requests.add(call);
      return readGeometry(call);
    });
  });

  tearDown(() async {
    messenger.setMockMethodCallHandler(_channel, null);
    await controller.dispose();
    await backend.videoRecordingEventStreamQueue.cancel();
    await backend.cameraEventStreamController.close();
    CameraPlatform.instance = previousPlatform;
  });

  test(
    'reads exact surface geometry without changing controller size',
    () async {
      final preview = backend.preview!;
      final identifier = preview.pigeon_instanceManager.getIdentifier(preview);
      final notifier = cameraPreviewGeometry(controller);
      var notifications = 0;
      notifier.addListener(() => notifications++);
      readGeometry = (_) async => _nativeGeometry(
        width: 1280,
        height: 720,
        crop: const Rect.fromLTRB(160, 0, 1120, 720),
        rotation: 270,
        handlesCropAndRotation: false,
        hasCameraTransform: false,
      );

      await synchronizeCameraPreviewSize(controller, isCurrent: () => true);

      expect(requests.single.method, 'getGeometry');
      expect(requests.single.arguments, {'previewId': identifier});
      final geometry = notifier.value!;
      expect(geometry.bufferSize, const Size(1280, 720));
      expect(geometry.cropRect, const Rect.fromLTRB(160, 0, 1120, 720));
      expect(geometry.rotationDegrees, 270);
      expect(geometry.uprightSize, const Size(720, 960));
      expect(geometry.mirrored, isTrue);
      expect(geometry.transformManually, isTrue);
      expect(notifications, 1);
      expect(controller.value.previewSize, const Size(720, 480));
    },
  );

  test(
    'recording reconfiguration replaces geometry, not previewSize',
    () async {
      for (final size in [
        const Size(720, 480),
        const Size(640, 480),
        const Size(1280, 720),
        const Size(480, 720),
      ]) {
        readGeometry = (_) async => _nativeGeometry(
          width: size.width.toInt(),
          height: size.height.toInt(),
        );
        await synchronizeCameraPreviewSize(controller, isCurrent: () => true);
        expect(cameraPreviewGeometry(controller).value!.bufferSize, size);
        expect(
          cameraPreviewGeometry(controller).value!.uprightSize,
          Size(size.height, size.width),
        );
        expect(controller.value.previewSize, const Size(720, 480));
      }
    },
  );

  test(
    'corrupted prior portrait size does not infer surface orientation',
    () async {
      controller.value = controller.value.copyWith(
        previewSize: const Size(480, 720),
      );
      readGeometry = (_) async =>
          _nativeGeometry(width: 640, height: 480, rotation: 0);
      await synchronizeCameraPreviewSize(controller, isCurrent: () => true);
      expect(
        cameraPreviewGeometry(controller).value!.uprightSize,
        const Size(640, 480),
      );
      expect(controller.value.previewSize, const Size(480, 720));
    },
  );

  test(
    'inactive, missing, or unregistered previews do not call native',
    () async {
      await synchronizeCameraPreviewSize(controller, isCurrent: () => false);
      backend.preview = null;
      await synchronizeCameraPreviewSize(controller, isCurrent: () => true);
      backend.preview = _Preview();
      await synchronizeCameraPreviewSize(controller, isCurrent: () => true);
      expect(requests, isEmpty);
      expect(cameraPreviewGeometry(controller).value, isNull);
    },
  );

  test('disposal while awaiting metadata ignores old response', () async {
    final response = Completer<Object?>();
    final requested = Completer<void>();
    readGeometry = (_) {
      requested.complete();
      return response.future;
    };
    var current = true;
    final pending = synchronizeCameraPreviewSize(
      controller,
      isCurrent: () => current,
    );
    await requested.future;
    current = false;
    await controller.dispose();
    response.complete(_nativeGeometry());
    await pending;
    expect(cameraPreviewGeometry(controller).value, isNull);
    expect(controller.value.previewSize, const Size(720, 480));
  });

  test('camera switch ignores response from previous native preview', () async {
    final response = Completer<Object?>();
    final requested = Completer<void>();
    readGeometry = (_) {
      requested.complete();
      return response.future;
    };
    final pending = synchronizeCameraPreviewSize(
      controller,
      isCurrent: () => true,
    );
    await requested.future;
    backend.preview = registerPreview();
    response.complete(_nativeGeometry(width: 640, height: 480));
    await pending;
    expect(cameraPreviewGeometry(controller).value, isNull);

    readGeometry = (_) async => _nativeGeometry(width: 1280, height: 720);
    await synchronizeCameraPreviewSize(controller, isCurrent: () => true);
    expect(
      cameraPreviewGeometry(controller).value!.bufferSize,
      const Size(1280, 720),
    );
  });

  test('older concurrent response cannot replace newer geometry', () async {
    final oldResponse = Completer<Object?>();
    final oldRequested = Completer<void>();
    var callCount = 0;
    readGeometry = (_) {
      callCount++;
      if (callCount == 1) {
        oldRequested.complete();
        return oldResponse.future;
      }
      return Future.value(
        _nativeGeometry(width: 1280, height: 720, rotation: 0),
      );
    };
    final pending = synchronizeCameraPreviewSize(
      controller,
      isCurrent: () => true,
    );
    await oldRequested.future;
    await synchronizeCameraPreviewSize(controller, isCurrent: () => true);
    final latest = cameraPreviewGeometry(controller).value;
    oldResponse.complete(_nativeGeometry(width: 640, height: 480));
    await pending;
    expect(cameraPreviewGeometry(controller).value, same(latest));
    expect(latest!.uprightSize, const Size(1280, 720));
  });

  test('missing and invalid responses preserve last valid geometry', () async {
    await synchronizeCameraPreviewSize(controller, isCurrent: () => true);
    final valid = cameraPreviewGeometry(controller).value;
    for (final response in <Object?>[
      null,
      <String, Object?>{},
      {..._nativeGeometry(), 'width': 0},
      {..._nativeGeometry(), 'height': 0},
      {..._nativeGeometry(), 'rotation_degrees': 45},
      {..._nativeGeometry(), 'crop_right': 0},
      {..._nativeGeometry(), 'mirrored': 'true'},
      'invalid native response',
    ]) {
      readGeometry = (_) async => response;
      await synchronizeCameraPreviewSize(controller, isCurrent: () => true);
      expect(cameraPreviewGeometry(controller).value, same(valid));
      expect(controller.value.previewSize, const Size(720, 480));
    }
  });

  test(
    'platform failure preserves valid geometry and active recording',
    () async {
      await synchronizeCameraPreviewSize(controller, isCurrent: () => true);
      final valid = cameraPreviewGeometry(controller).value;
      controller.value = controller.value.copyWith(isRecordingVideo: true);
      readGeometry = (_) async =>
          throw PlatformException(code: 'preview_geometry');
      await synchronizeCameraPreviewSize(controller, isCurrent: () => true);
      expect(controller.value.isRecordingVideo, isTrue);
      expect(controller.value.previewSize, const Size(720, 480));
      expect(cameraPreviewGeometry(controller).value, same(valid));
    },
  );

  test('other backend skips native bridge', () async {
    CameraPlatform.instance = _OtherBackend();
    await synchronizeCameraPreviewSize(controller, isCurrent: () => true);
    expect(requests, isEmpty);
    expect(cameraPreviewGeometry(controller).value, isNull);
    expect(controller.value.previewSize, const Size(720, 480));
  });

  for (final direction in [
    CameraLensDirection.front,
    CameraLensDirection.back,
  ]) {
    for (final sensor in [0, 90, 180, 270]) {
      test(
        'native transform wins for ${direction.name} sensor $sensor',
        () async {
          final deviceController = CameraController(
            CameraDescription(
              name: direction.name,
              lensDirection: direction,
              sensorOrientation: sensor,
            ),
            ResolutionPreset.medium,
          );
          addTearDown(deviceController.dispose);
          deviceController.value = deviceController.value.copyWith(
            isInitialized: true,
            previewSize: const Size(480, 720),
          );
          readGeometry = (_) async => _nativeGeometry(
            width: 640,
            height: 480,
            rotation: 180,
            mirrored: false,
          );
          await synchronizeCameraPreviewSize(
            deviceController,
            isCurrent: () => true,
          );
          final geometry = cameraPreviewGeometry(deviceController).value!;
          expect(geometry.rotationDegrees, 180);
          expect(geometry.uprightSize, const Size(640, 480));
          expect(geometry.mirrored, isFalse);
          expect(deviceController.value.previewSize, const Size(480, 720));
        },
      );
    }
  }

  test('fromMap rejects invalid dimensions, crop, rotation, and flags', () {
    for (final invalid in <Map<String, Object?>>[
      {},
      {..._nativeGeometry(), 'width': 0},
      {..._nativeGeometry(), 'height': -1},
      {..._nativeGeometry(), 'width': double.infinity},
      {..._nativeGeometry(), 'height': double.nan},
      {..._nativeGeometry(), 'rotation_degrees': 45},
      {..._nativeGeometry(), 'rotation_degrees': -90},
      {..._nativeGeometry(), 'rotation_degrees': 360},
      {..._nativeGeometry(), 'rotation_degrees': 90.5},
      {..._nativeGeometry(), 'crop_left': -1},
      {..._nativeGeometry(), 'crop_top': -1},
      {..._nativeGeometry(), 'crop_right': 721},
      {..._nativeGeometry(), 'crop_bottom': 481},
      {..._nativeGeometry(), 'crop_right': 0},
      {..._nativeGeometry(), 'crop_bottom': 0},
      {..._nativeGeometry(), 'crop_left': double.nan},
      {..._nativeGeometry(), 'mirrored': null},
      {..._nativeGeometry(), 'handles_crop_and_rotation': 1},
      {..._nativeGeometry(), 'has_camera_transform': 'true'},
    ]) {
      expect(
        CameraPreviewGeometry.fromMap(invalid),
        isNull,
        reason: '$invalid',
      );
    }
  });

  test('fromMap preserves native transforms for all quarter turns', () {
    for (final rotation in [0, 90, 180, 270]) {
      final geometry = CameraPreviewGeometry.fromMap(
        _nativeGeometry(
          rotation: rotation,
          crop: const Rect.fromLTRB(20, 10, 620, 410),
        ),
      )!;
      expect(geometry.rotationDegrees, rotation);
      expect(
        geometry.uprightSize,
        rotation % 180 == 0 ? const Size(600, 400) : const Size(400, 600),
      );
      expect(geometry.transformManually, isFalse);
    }
  });
}
