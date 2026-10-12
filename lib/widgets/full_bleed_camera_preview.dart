import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Fills the available space by cropping the camera image, without stretching.
class FullBleedCameraPreview extends StatelessWidget {
  const FullBleedCameraPreview({super.key, required this.controller});

  final CameraController controller;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<CameraValue>(
      valueListenable: controller,
      builder: (context, value, _) {
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
}
