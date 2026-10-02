package dev.erikengler.campuskoethen

import android.content.Intent
import android.content.pm.PackageManager
import android.nfc.NfcAdapter
import android.nfc.Tag
import android.nfc.TagLostException
import android.nfc.tech.IsoDep
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.IOException
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class MainActivity : FlutterActivity(), MethodChannel.MethodCallHandler {
    companion object {
        private const val CHANNEL = "dev.erikengler.campuskoethen/canteen_balance"
        private const val TRANSCEIVE_TIMEOUT_MS = 5_000
    }

    private val stateLock = Any()
    private val ioExecutor: ExecutorService = Executors.newSingleThreadExecutor()

    private var methodChannel: MethodChannel? = null
    private var pendingExternalTag: Tag? = null
    private var activeIsoDep: IsoDep? = null
    private var pendingStartResult: MethodChannel.Result? = null
    private var readerModeEnabled = false
    private var generation = 0

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).also {
            it.setMethodCallHandler(this)
        }
        captureExternalTag(intent, notifyFlutter = false)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        captureExternalTag(intent, notifyFlutter = true)
    }

    override fun onPause() {
        // Reader mode must never continue as a background scan.
        cancelActiveSession("cancelled")
        super.onPause()
    }

    override fun onDestroy() {
        cancelActiveSession("cancelled")
        methodChannel?.setMethodCallHandler(null)
        methodChannel = null
        ioExecutor.shutdownNow()
        super.onDestroy()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "availability" -> result.success(availability())
            "hasPendingExternalTag" -> result.success(
                synchronized(stateLock) { pendingExternalTag != null },
            )
            "start" -> startSession(call, result)
            "transceive" -> transceive(call.arguments, result)
            "finish" -> {
                finishActiveSession()
                result.success(null)
            }
            "cancel" -> {
                cancelActiveSession("cancelled")
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun availability(): String {
        if (!packageManager.hasSystemFeature(PackageManager.FEATURE_NFC)) {
            return "notSupported"
        }
        val adapter = NfcAdapter.getDefaultAdapter(this) ?: return "notSupported"
        return if (adapter.isEnabled) "available" else "disabled"
    }

    private fun startSession(call: MethodCall, result: MethodChannel.Result) {
        when (availability()) {
            "notSupported" -> {
                result.error("nfc_not_supported", "NFC is not supported.", null)
                return
            }
            "disabled" -> {
                result.error("nfc_disabled", "NFC is disabled.", null)
                return
            }
        }

        val usePendingTag = call.argument<Boolean>("usePendingTag") == true
        val sessionGeneration: Int
        val externalTag: Tag?
        synchronized(stateLock) {
            if (pendingStartResult != null || activeIsoDep != null) {
                result.error("busy", "An NFC read is already active.", null)
                return
            }
            generation += 1
            sessionGeneration = generation
            pendingStartResult = result
            externalTag = if (usePendingTag) pendingExternalTag.also {
                pendingExternalTag = null
            } else null
        }

        if (usePendingTag) {
            if (externalTag == null) {
                completeStartError(sessionGeneration, "no_pending_tag")
                return
            }
            connectTag(externalTag, sessionGeneration)
            return
        }

        val adapter = NfcAdapter.getDefaultAdapter(this)
        if (adapter == null) {
            completeStartError(sessionGeneration, "nfc_not_supported")
            return
        }
        readerModeEnabled = true
        adapter.enableReaderMode(
            this,
            { tag -> connectTag(tag, sessionGeneration) },
            NfcAdapter.FLAG_READER_NFC_A or
                NfcAdapter.FLAG_READER_NFC_B or
                NfcAdapter.FLAG_READER_SKIP_NDEF_CHECK,
            null,
        )
    }

    private fun connectTag(tag: Tag, sessionGeneration: Int) {
        ioExecutor.execute {
            val isoDep = IsoDep.get(tag)
            if (isoDep == null) {
                completeStartError(sessionGeneration, "unsupported_tag")
                return@execute
            }
            try {
                isoDep.timeout = TRANSCEIVE_TIMEOUT_MS
                isoDep.connect()
            } catch (_: TagLostException) {
                closeQuietly(isoDep)
                completeStartError(sessionGeneration, "tag_lost")
                return@execute
            } catch (_: IOException) {
                closeQuietly(isoDep)
                completeStartError(sessionGeneration, "tag_lost")
                return@execute
            }

            val startResult: MethodChannel.Result?
            synchronized(stateLock) {
                if (generation != sessionGeneration || pendingStartResult == null) {
                    closeQuietly(isoDep)
                    return@execute
                }
                activeIsoDep = isoDep
                startResult = pendingStartResult
                pendingStartResult = null
            }
            // Keep reader mode alive while Dart sends both APDUs. Disabling
            // it here disconnects the freshly connected IsoDep tag on some
            // Android devices, so the first transceive looks like a card that
            // was removed too early. finish/cancel/onPause own shutdown.
            runOnUiThread { startResult?.success(null) }
        }
    }

    private fun transceive(arguments: Any?, result: MethodChannel.Result) {
        val command = arguments as? ByteArray
        if (command == null || command.isEmpty()) {
            result.error("invalid_response", "Invalid APDU.", null)
            return
        }
        val sessionGeneration: Int
        val isoDep: IsoDep
        synchronized(stateLock) {
            isoDep = activeIsoDep ?: run {
                result.error("tag_lost", "No connected ISO-DEP tag.", null)
                return
            }
            sessionGeneration = generation
        }

        ioExecutor.execute {
            try {
                val response = isoDep.transceive(command)
                val stillActive = synchronized(stateLock) {
                    generation == sessionGeneration && activeIsoDep === isoDep
                }
                runOnUiThread {
                    if (stillActive) {
                        result.success(response)
                    } else {
                        result.error("cancelled", "NFC session cancelled.", null)
                    }
                }
            } catch (_: TagLostException) {
                completeTransceiveError(result, sessionGeneration, "tag_lost")
            } catch (_: IOException) {
                completeTransceiveError(result, sessionGeneration, "tag_lost")
            }
        }
    }

    private fun completeTransceiveError(
        result: MethodChannel.Result,
        sessionGeneration: Int,
        fallbackCode: String,
    ) {
        val code = synchronized(stateLock) {
            if (generation == sessionGeneration) fallbackCode else "cancelled"
        }
        runOnUiThread { result.error(code, "NFC communication ended.", null) }
    }

    private fun completeStartError(sessionGeneration: Int, code: String) {
        val startResult: MethodChannel.Result?
        synchronized(stateLock) {
            if (generation != sessionGeneration) return
            startResult = pendingStartResult
            pendingStartResult = null
        }
        disableReaderMode()
        runOnUiThread { startResult?.error(code, "NFC session could not start.", null) }
    }

    private fun finishActiveSession() {
        val isoDep: IsoDep?
        synchronized(stateLock) {
            generation += 1
            isoDep = activeIsoDep
            activeIsoDep = null
        }
        disableReaderMode()
        closeQuietly(isoDep)
    }

    private fun cancelActiveSession(code: String) {
        val startResult: MethodChannel.Result?
        val isoDep: IsoDep?
        synchronized(stateLock) {
            generation += 1
            startResult = pendingStartResult
            pendingStartResult = null
            isoDep = activeIsoDep
            activeIsoDep = null
        }
        disableReaderMode()
        closeQuietly(isoDep)
        runOnUiThread { startResult?.error(code, "NFC session cancelled.", null) }
    }

    private fun disableReaderMode() {
        if (!readerModeEnabled) return
        readerModeEnabled = false
        runOnUiThread {
            NfcAdapter.getDefaultAdapter(this)?.disableReaderMode(this)
        }
    }

    private fun captureExternalTag(intent: Intent?, notifyFlutter: Boolean) {
        if (intent?.action != NfcAdapter.ACTION_TECH_DISCOVERED) return
        val tag = readTag(intent) ?: return
        if (IsoDep.get(tag) == null) return
        synchronized(stateLock) { pendingExternalTag = tag }
        if (notifyFlutter) {
            methodChannel?.invokeMethod("externalTagDiscovered", null)
        }
    }

    @Suppress("DEPRECATION")
    private fun readTag(intent: Intent): Tag? = if (Build.VERSION.SDK_INT >= 33) {
        intent.getParcelableExtra(NfcAdapter.EXTRA_TAG, Tag::class.java)
    } else {
        intent.getParcelableExtra(NfcAdapter.EXTRA_TAG)
    }

    private fun closeQuietly(isoDep: IsoDep?) {
        try {
            isoDep?.close()
        } catch (_: IOException) {
            // No raw tag or protocol data is logged.
        }
    }
}
