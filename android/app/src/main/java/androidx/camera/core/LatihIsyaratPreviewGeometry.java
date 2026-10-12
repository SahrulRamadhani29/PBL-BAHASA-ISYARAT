package androidx.camera.core;

import android.graphics.Rect;
import android.os.Handler;
import android.os.Looper;
import androidx.annotation.Nullable;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.TimeoutException;
import java.util.concurrent.atomic.AtomicReference;

/**
 * Reads the actual surface transform. The CameraX package is intentional:
 * mCurrentSurfaceRequest is package-private in the pinned CameraX 1.6.1.
 * Keeping this access at compile time avoids reflection and camera heuristics.
 */
public final class LatihIsyaratPreviewGeometry {
  private static final Handler MAIN = new Handler(Looper.getMainLooper());

  private LatihIsyaratPreviewGeometry() {}

  @Nullable
  public static Map<String, Object> read(
      Preview preview, boolean handlesCropAndRotation, long timeoutMs) {
    final CompletableFuture<Map<String, Object>> result = new CompletableFuture<>();
    final AtomicReference<SurfaceRequest> requestReference = new AtomicReference<>();
    MAIN.post(
        () -> {
          if (result.isDone()) return;
          try {
            final SurfaceRequest request = preview.mCurrentSurfaceRequest;
            if (request == null) {
              result.complete(null);
              return;
            }
            requestReference.set(request);
            request.setTransformationInfoListener(
                MAIN::post,
                info -> {
                  if (info == null || result.isDone()) return;
                  if (preview.mCurrentSurfaceRequest != request) {
                    result.complete(null);
                    return;
                  }
                  try {
                    final Rect crop = info.getCropRect();
                    final android.util.Size resolution = request.getResolution();
                    final Map<String, Object> geometry = new HashMap<>();
                    geometry.put("width", resolution.getWidth());
                    geometry.put("height", resolution.getHeight());
                    geometry.put("rotation_degrees", info.getRotationDegrees());
                    geometry.put("crop_left", crop.left);
                    geometry.put("crop_top", crop.top);
                    geometry.put("crop_right", crop.right);
                    geometry.put("crop_bottom", crop.bottom);
                    geometry.put("mirrored", info.isMirroring());
                    geometry.put("handles_crop_and_rotation", handlesCropAndRotation);
                    geometry.put("has_camera_transform", info.hasCameraTransform());
                    result.complete(geometry);
                  } catch (RuntimeException error) {
                    result.completeExceptionally(error);
                  }
                });
          } catch (RuntimeException error) {
            result.completeExceptionally(error);
          }
        });

    try {
      return result.get(timeoutMs, TimeUnit.MILLISECONDS);
    } catch (InterruptedException error) {
      result.complete(null);
      Thread.currentThread().interrupt();
      return null;
    } catch (TimeoutException error) {
      result.complete(null);
      return null;
    } catch (Exception error) {
      return null;
    } finally {
      MAIN.post(
          () -> {
            final SurfaceRequest request = requestReference.get();
            if (request != null) request.clearTransformationInfoListener();
          });
    }
  }
}
