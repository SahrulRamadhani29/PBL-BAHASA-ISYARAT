import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../services/camera_preview_size.dart';

/// Fills the available space by cropping the camera image, without stretching.
class FullBleedCameraPreview extends StatelessWidget {
  const FullBleedCameraPreview({super.key, required this.controller});

  final CameraController controller;

  @override
  Widget build(BuildContext context) {
    final geometry = cameraPreviewGeometry(controller);
    return ListenableBuilder(
      listenable: Listenable.merge([controller, geometry]),
      builder: (context, _) {
        final value = controller.value;
        if (value.isInitialized && geometry.value != null) {
          return _nativePreview(geometry.value!);
        }
        final previewSize = value.previewSize;
        if (!value.isInitialized ||
            previewSize == null ||
            !previewSize.width.isFinite ||
            !previewSize.height.isFinite ||
            previewSize.width <= 0 ||
            previewSize.height <= 0) {
          return const SizedBox.expand();
        }

        // Match CameraPreview's orientation precedence, including the fixed
        // orientation of a recording and the orientation of a paused preview.
        // UI orientation alone cannot describe all of those states.
        final orientation = value.isRecordingVideo
            ? value.recordingOrientation!
            : (value.previewPauseOrientation ??
                  value.lockedCaptureOrientation ??
                  value.deviceOrientation);
        final isLandscape =
            orientation == DeviceOrientation.landscapeLeft ||
            orientation == DeviceOrientation.landscapeRight;
        final orientedSize = isLandscape
            ? previewSize
            : Size(previewSize.height, previewSize.width);

        return ClipRect(
          child: FittedBox(
            fit: BoxFit.cover,
            alignment: Alignment.center,
            child: SizedBox(
              width: orientedSize.width,
              height: orientedSize.height,
              // Leave sensor rotation and front-camera mirroring to the
              // camera plugin. Applying either twice changes the image.
              child: CameraPreview(controller),
            ),
          ),
        );
      },
    );
  }

  Widget _nativePreview(CameraPreviewGeometry geometry) {
    Widget preview = Texture(textureId: controller.cameraId);
    if (geometry.transformManually) {
      // Crop in buffer coordinates, then rotate, then mirror in upright
      // coordinates. CameraX may have already applied part of this transform.
      preview = SizedBox.fromSize(
        size: geometry.cropRect.size,
        child: ClipRect(
          child: Stack(
            children: [
              Positioned(
                left: -geometry.cropRect.left,
                top: -geometry.cropRect.top,
                width: geometry.bufferSize.width,
                height: geometry.bufferSize.height,
                child: preview,
              ),
            ],
          ),
        ),
      );
      preview = RotatedBox(
        quarterTurns: geometry.rotationDegrees ~/ 90,
        child: preview,
      );
      if (geometry.mirrored) {
        preview = Transform.scale(scaleX: -1, child: preview);
      }
    }
    // SurfaceTexture automatically applies a direct camera's transform.
    // Bypass CameraPreview/RotatedPreviewDelegate so rotation is never applied
    // twice using the physical sensor after StreamSharing reconfigures it.
    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox.fromSize(size: geometry.uprightSize, child: preview),
      ),
    );
  }
}
