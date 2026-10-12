package com.example.pbl_bahasa_isyarat

import androidx.annotation.NonNull
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugins.camerax.CameraAndroidCameraxPlugin
import io.flutter.plugins.camerax.LatihIsyaratPreviewBridge

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val cameraPlugin =
            flutterEngine.plugins.get(CameraAndroidCameraxPlugin::class.java)
                as? CameraAndroidCameraxPlugin
        LatihIsyaratPreviewBridge.install(
            flutterEngine.dartExecutor.binaryMessenger,
            cameraPlugin,
        )
    }
}
