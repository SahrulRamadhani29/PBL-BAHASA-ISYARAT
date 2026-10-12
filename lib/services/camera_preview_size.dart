import 'package:camera/camera.dart';
import 'package:camera_android_camerax/camera_android_camerax.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Exact remaining transform of the CameraX surface, including StreamSharing.
@immutable
class CameraPreviewGeometry {
  const CameraPreviewGeometry({
    required this.bufferSize,
    required this.cropRect,
    required this.rotationDegrees,
    required this.mirrored,
    required this.handlesCropAndRotation,
    required this.hasCameraTransform,
  });

  final Size bufferSize;
  final Rect cropRect;
  final int rotationDegrees;
  final bool mirrored;
  final bool handlesCropAndRotation;
  final bool hasCameraTransform;

  // A GL/StreamSharing surface already applied some of the transform. Its
  // remaining transform still needs applying, even with a SurfaceTexture.
  bool get transformManually => !handlesCropAndRotation || !hasCameraTransform;

  Size get uprightSize => rotationDegrees % 180 == 0
      ? cropRect.size
      : Size(cropRect.height, cropRect.width);

  static CameraPreviewGeometry? fromMap(Map<Object?, Object?> map) {
    double? number(String key) =>
        map[key] is num ? (map[key]! as num).toDouble() : null;
    final width = number('width');
    final height = number('height');
    final rotation = number('rotation_degrees');
    final left = number('crop_left');
    final top = number('crop_top');
    final right = number('crop_right');
    final bottom = number('crop_bottom');
    final values = [width, height, rotation, left, top, right, bottom];
    if (values.any((value) => value == null || !value.isFinite) ||
        width! <= 0 ||
        height! <= 0 ||
        ![0, 90, 180, 270].contains(rotation) ||
        left! < 0 ||
        top! < 0 ||
        right! > width ||
        bottom! > height ||
        right <= left ||
        bottom <= top ||
        map['mirrored'] is! bool ||
        map['handles_crop_and_rotation'] is! bool ||
        map['has_camera_transform'] is! bool) {
      return null;
    }
    return CameraPreviewGeometry(
      bufferSize: Size(width, height),
      cropRect: Rect.fromLTRB(left, top, right, bottom),
      rotationDegrees: rotation!.toInt(),
      mirrored: map['mirrored']! as bool,
      handlesCropAndRotation: map['handles_crop_and_rotation']! as bool,
      hasCameraTransform: map['has_camera_transform']! as bool,
    );
  }

  Map<String, Object> toJson() => {
    'buffer_width': bufferSize.width,
    'buffer_height': bufferSize.height,
    'rotation_degrees': rotationDegrees,
    'mirrored': mirrored,
    'handles_crop_and_rotation': handlesCropAndRotation,
    'has_camera_transform': hasCameraTransform,
    'upright_width': uprightSize.width,
    'upright_height': uprightSize.height,
  };
}

const _geometryChannel = MethodChannel('latih_isyarat/camera_preview');
final _geometry = Expando<ValueNotifier<CameraPreviewGeometry?>>();
final _requestGeneration = Expando<int>();

ValueNotifier<CameraPreviewGeometry?> cameraPreviewGeometry(
  CameraController controller,
) => _geometry[controller] ??= ValueNotifier(null);

/// Reads the native surface transform without rewriting controller.previewSize.
/// The app-owned bridge supplies TransformationInfo omitted by CameraX's API.
Future<void> synchronizeCameraPreviewSize(
  CameraController controller, {
  required bool Function() isCurrent,
}) async {
  if (!isCurrent()) return;
  final platform = CameraPlatform.instance;
  if (platform is! AndroidCameraCameraX) return;

  // ignore: invalid_use_of_visible_for_testing_member
  final nativePreview = platform.preview;
  if (nativePreview == null) return;

  final generation = (_requestGeneration[controller] ?? 0) + 1;
  _requestGeneration[controller] = generation;
  try {
    final identifier = nativePreview.pigeon_instanceManager.getIdentifier(
      nativePreview,
    );
    if (identifier == null) return;
    final map = await _geometryChannel.invokeMapMethod<Object?, Object?>(
      'getGeometry',
      {'previewId': identifier},
    );
    // ignore: invalid_use_of_visible_for_testing_member
    final currentPreview = platform.preview;
    if (!isCurrent() ||
        !identical(nativePreview, currentPreview) ||
        _requestGeneration[controller] != generation ||
        !controller.value.isInitialized ||
        map == null) {
      return;
    }
    final geometry = CameraPreviewGeometry.fromMap(map);
    if (geometry == null) return;
    cameraPreviewGeometry(controller).value = geometry;
    if (kDebugMode) {
      debugPrint('CameraX preview geometry: ${geometry.toJson()}');
    }
  } catch (error) {
    // Keep the plugin preview on older APKs or temporary metadata failures.
    // A metadata failure must not leave a recording running invisibly.
    if (kDebugMode) debugPrint('Preview geometry unavailable: $error');
  }
}
