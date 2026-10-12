import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:camera_android_camerax/camera_android_camerax.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/foundation.dart';

/// Refreshes the preview dimensions after CameraX binds or unbinds a use case.
///
/// CameraX 0.7.4+7 reports previewSize only during initialization, even though
/// adding video capture can select a different native preview resolution.
/// Image-analysis frame dimensions are not a substitute for preview dimensions.
Future<void> synchronizeCameraPreviewSize(
  CameraController controller, {
  required bool Function() isCurrent,
}) async {
  if (!isCurrent()) return;
  final platform = CameraPlatform.instance;
  if (platform is! AndroidCameraCameraX) return;

  // This compatibility access is isolated here and the plugin version is pinned.
  // Remove it when CameraX and CameraController propagate resolution changes.
  // ignore: invalid_use_of_visible_for_testing_member
  final nativePreview = platform.preview;
  if (nativePreview == null) return;

  try {
    final resolutionInfo = await nativePreview.getResolutionInfo();
    // A camera switch or disposal may have completed during the native request.
    // ignore: invalid_use_of_visible_for_testing_member
    if (!isCurrent() || !identical(nativePreview, platform.preview)) return;
    if (resolutionInfo == null || !controller.value.isInitialized) return;

    final resolution = resolutionInfo.resolution;
    if (resolution.width <= 0 || resolution.height <= 0) return;
    final previewSize = Size(
      resolution.width.toDouble(),
      resolution.height.toDouble(),
    );
    if (controller.value.previewSize != previewSize) {
      controller.value = controller.value.copyWith(previewSize: previewSize);
    }
  } catch (error) {
    // A failed metadata request must not turn a successful recording into an
    // apparent start/stop failure or leave a recording running invisibly.
    if (kDebugMode) debugPrint('Preview-size refresh failed: $error');
  }
}
