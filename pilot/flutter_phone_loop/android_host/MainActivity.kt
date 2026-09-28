package com.qujindai.pocketgallery_phone_pilot

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private lateinit var diagnosticsHost: DeviceDiagnosticsHost

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        diagnosticsHost = DeviceDiagnosticsHost(this)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            DeviceDiagnosticsHost.CHANNEL_NAME,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "identity" -> diagnosticsHost.identity { outcome ->
                    runOnUiThread {
                        outcome.fold(
                            onSuccess = result::success,
                            onFailure = { error ->
                                result.error(
                                    "IDENTITY_READ_FAILED",
                                    error.message,
                                    null,
                                )
                            },
                        )
                    }
                }

                "resources" -> result.success(diagnosticsHost.resources())
                "keepScreenOn" -> diagnosticsHost.keepScreenOn(
                    enabled = call.argument<Boolean>("enabled") == true,
                ) { outcome ->
                    outcome.fold(
                        onSuccess = { result.success(null) },
                        onFailure = { error ->
                            result.error(
                                "KEEP_SCREEN_ON_FAILED",
                                error.message,
                                null,
                            )
                        },
                    )
                }

                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        if (::diagnosticsHost.isInitialized) diagnosticsHost.close()
        super.onDestroy()
    }
}
