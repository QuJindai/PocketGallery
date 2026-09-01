package com.qujindai.pocketgallery_phone_pilot

import android.app.Activity
import android.app.ActivityManager
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.os.BatteryManager
import android.os.Build
import android.os.Debug
import android.os.PowerManager
import android.view.WindowManager
import java.io.File
import java.security.MessageDigest
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

internal class DeviceDiagnosticsHost(
    private val activity: Activity,
) : AutoCloseable {
    private val identityExecutor: ExecutorService =
        Executors.newSingleThreadExecutor { runnable ->
            Thread(runnable, "pocketgallery-device-identity").apply {
                isDaemon = true
            }
        }

    fun identity(callback: (Result<Map<String, Any?>>) -> Unit) {
        try {
            identityExecutor.execute {
                callback(runCatching(::readIdentity))
            }
        } catch (error: RuntimeException) {
            callback(Result.failure(error))
        }
    }

    fun resources(): Map<String, Any?> {
        val reasons = linkedSetOf<String>()
        var availableMemoryBytes: Long? = null
        var totalMemoryBytes: Long? = null
        var lowMemory: Boolean? = null
        var lowMemoryThresholdBytes: Long? = null

        try {
            val manager = activity.getSystemService(ActivityManager::class.java)
                ?: error("Activity manager is unavailable")
            val memoryInfo = ActivityManager.MemoryInfo()
            manager.getMemoryInfo(memoryInfo)
            availableMemoryBytes = memoryInfo.availMem
            totalMemoryBytes = memoryInfo.totalMem
            lowMemory = memoryInfo.lowMemory
            lowMemoryThresholdBytes = memoryInfo.threshold
        } catch (_: RuntimeException) {
            reasons.add("MEMORY_INFO_UNAVAILABLE")
        }

        val processPssKiB = readOrNull(reasons, "PROCESS_PSS_UNAVAILABLE") {
            Debug.getPss().toLong()
        }
        val thermalStatus = readOrNull(reasons, "THERMAL_STATUS_UNAVAILABLE") {
            val powerManager = activity.getSystemService(PowerManager::class.java)
                ?: error("Power manager is unavailable")
            powerManager.currentThermalStatus
        }
        val batteryTemperatureC = readOrNull(
            reasons,
            "BATTERY_TEMPERATURE_UNAVAILABLE",
        ) {
            val battery = activity.registerReceiver(
                null,
                IntentFilter(Intent.ACTION_BATTERY_CHANGED),
            ) ?: error("Battery state is unavailable")
            val tenthsCelsius = battery.getIntExtra(
                BatteryManager.EXTRA_TEMPERATURE,
                Int.MIN_VALUE,
            )
            check(tenthsCelsius != Int.MIN_VALUE) {
                "Battery temperature is unavailable"
            }
            tenthsCelsius / 10.0
        }

        if (availableMemoryBytes == null) {
            reasons.add("AVAILABLE_MEMORY_UNAVAILABLE")
        }
        if (totalMemoryBytes == null) reasons.add("TOTAL_MEMORY_UNAVAILABLE")
        if (lowMemory == null) reasons.add("LOW_MEMORY_UNAVAILABLE")
        if (lowMemoryThresholdBytes == null) {
            reasons.add("LOW_MEMORY_THRESHOLD_UNAVAILABLE")
        }

        return linkedMapOf(
            "capturedAtEpochMs" to System.currentTimeMillis(),
            "processPssKiB" to processPssKiB,
            "availableMemoryBytes" to availableMemoryBytes,
            "totalMemoryBytes" to totalMemoryBytes,
            "lowMemory" to lowMemory,
            "lowMemoryThresholdBytes" to lowMemoryThresholdBytes,
            "thermalStatus" to thermalStatus,
            "batteryTemperatureC" to batteryTemperatureC,
            "unavailableReasons" to reasons.toList(),
        )
    }

    fun keepScreenOn(enabled: Boolean, callback: (Result<Unit>) -> Unit) {
        activity.runOnUiThread {
            callback(
                runCatching {
                    if (enabled) {
                        activity.window.addFlags(
                            WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON,
                        )
                    } else {
                        activity.window.clearFlags(
                            WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON,
                        )
                    }
                },
            )
        }
    }

    override fun close() {
        identityExecutor.shutdownNow()
    }

    private fun readIdentity(): Map<String, Any?> {
        val reasons = linkedSetOf<String>()
        val packageName = readOrNull(reasons, "PACKAGE_NAME_UNAVAILABLE") {
            activity.packageName.takeIf { it.isNotBlank() }
                ?: error("Package name is unavailable")
        }
        val packageInfo = packageName?.let { readPackageInfo(it, reasons) }
        val versionName = packageInfo?.versionName?.takeIf { it.isNotBlank() }
        val versionCode = packageInfo?.longVersionCode
        if (versionName == null) reasons.add("VERSION_NAME_UNAVAILABLE")
        if (versionCode == null) reasons.add("VERSION_CODE_UNAVAILABLE")

        val signerSha256 = signerSha256(packageInfo, reasons)
        val apkSha256 = readOrNull(reasons, "APK_SHA256_UNAVAILABLE") {
            sha256(File(activity.applicationInfo.sourceDir))
        }
        val refreshRateHz = readOrNull(reasons, "REFRESH_RATE_UNAVAILABLE") {
            activity.display?.refreshRate?.toDouble()
                ?: error("Display refresh rate is unavailable")
        }
        val manufacturer = Build.MANUFACTURER.takeIf(String::isNotBlank)
        val model = Build.MODEL.takeIf(String::isNotBlank)
        if (manufacturer == null) reasons.add("MANUFACTURER_UNAVAILABLE")
        if (model == null) reasons.add("MODEL_UNAVAILABLE")

        return linkedMapOf(
            "manufacturer" to manufacturer,
            "model" to model,
            "sdkInt" to Build.VERSION.SDK_INT,
            "refreshRateHz" to refreshRateHz,
            "packageName" to packageName,
            "versionName" to versionName,
            "versionCode" to versionCode,
            "signerSha256" to signerSha256,
            "apkSha256" to apkSha256,
            "unavailableReasons" to reasons.toList(),
        )
    }

    private fun readPackageInfo(
        packageName: String,
        reasons: MutableSet<String>,
    ): PackageInfo? {
        return readOrNull(reasons, "PACKAGE_INFO_UNAVAILABLE") {
            activity.packageManager.getPackageInfo(
                packageName,
                PackageManager.GET_SIGNING_CERTIFICATES,
            )
        }
    }

    private fun signerSha256(
        packageInfo: PackageInfo?,
        reasons: MutableSet<String>,
    ): String? {
        val signers = packageInfo?.signingInfo?.apkContentsSigners
        if (signers == null || signers.isEmpty()) {
            reasons.add("SIGNER_SHA256_UNAVAILABLE")
            return null
        }
        if (signers.size != 1) {
            reasons.add("SIGNER_AMBIGUOUS")
            return null
        }
        return readOrNull(reasons, "SIGNER_SHA256_UNAVAILABLE") {
            sha256(signers.single().toByteArray())
        }
    }

    private fun sha256(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().buffered().use { input ->
            val buffer = ByteArray(8192)
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                if (count > 0) digest.update(buffer, 0, count)
            }
        }
        return digest.digest().toLowerHex()
    }

    private fun sha256(bytes: ByteArray): String {
        return MessageDigest.getInstance("SHA-256")
            .digest(bytes)
            .toLowerHex()
    }

    private fun ByteArray.toLowerHex(): String {
        return joinToString(separator = "") { byte ->
            "%02x".format(byte.toInt() and 0xff)
        }
    }

    private inline fun <T> readOrNull(
        reasons: MutableSet<String>,
        reason: String,
        read: () -> T,
    ): T? {
        return try {
            read()
        } catch (_: Exception) {
            reasons.add(reason)
            null
        }
    }

    companion object {
        const val CHANNEL_NAME = "pocketgallery/device_diagnostics"
    }
}
