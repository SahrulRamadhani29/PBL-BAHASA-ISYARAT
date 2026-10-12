package io.flutter.plugins.camerax;

import android.os.Handler;
import android.os.Looper;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.camera.core.Preview;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodChannel;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/** App-owned bridge for exact CameraX Preview geometry. */
public final class LatihIsyaratPreviewBridge {
  private static final String CHANNEL = "latih_isyarat/camera_preview";
  private static final String METHOD = "getGeometry";
  private static final long TIMEOUT_MS = 1000L;
  private static final ExecutorService WORKER = Executors.newSingleThreadExecutor();
  private static final Handler MAIN = new Handler(Looper.getMainLooper());

  private LatihIsyaratPreviewBridge() {}

  public static void install(
      @NonNull BinaryMessenger messenger,
      @Nullable CameraAndroidCameraxPlugin cameraPlugin) {
    final MethodChannel channel = new MethodChannel(messenger, CHANNEL);
    channel.setMethodCallHandler(
        (call, result) -> {
          if (!METHOD.equals(call.method)) {
            result.notImplemented();
            return;
          }
          final Object argument = call.argument("previewId");
          if (!(argument instanceof Number) || cameraPlugin == null) {
            result.success(null);
            return;
          }
          final long previewId = ((Number) argument).longValue();
          // MethodChannel's default queue is the main thread. Pigeon's instance
          // manager and the plugin's surface-provider map are not thread-safe.
          try {
            final ProxyApiRegistrar registrar = cameraPlugin.proxyApiRegistrar;
            if (registrar == null) {
              result.success(null);
              return;
            }
            final Object instance = registrar.getInstanceManager().getInstance(previewId);
            if (!(instance instanceof Preview)) {
              result.success(null);
              return;
            }
            final Preview preview = (Preview) instance;
            final boolean handlesCropAndRotation =
                registrar.getPigeonApiPreview().surfaceProducerHandlesCropAndRotation(preview);
            WORKER.execute(
                () -> {
                  try {
                    final Map<String, Object> geometry =
                        androidx.camera.core.LatihIsyaratPreviewGeometry.read(
                            preview, handlesCropAndRotation, TIMEOUT_MS);
                    MAIN.post(() -> result.success(geometry));
                  } catch (RuntimeException error) {
                    MAIN.post(
                        () -> result.error("preview_geometry", error.getMessage(), null));
                  }
                });
          } catch (RuntimeException error) {
            result.error("preview_geometry", error.getMessage(), null);
          }
        });
  }
}
