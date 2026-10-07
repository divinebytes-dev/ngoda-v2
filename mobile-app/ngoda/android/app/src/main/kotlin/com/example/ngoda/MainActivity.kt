package com.divinebytes.ngoda

import android.app.PendingIntent
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.IntentFilter
import android.nfc.NfcAdapter
import android.nfc.Tag
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.util.Log
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class MainActivity : FlutterFragmentActivity() {

    companion object {
        private const val TAG = "NgodaNfc"

        private const val METHOD_CHANNEL =
            "ngoda.tap.hce"

        private const val EVENT_CHANNEL =
            "ngoda.tap.events"
    }

    private var nfcAdapter: NfcAdapter? = null

    private var eventSink: EventChannel.EventSink? = null

    /**
     * Used only when NFC data arrives before Flutter starts
     * listening to the EventChannel.
     */
    private var pendingPayload: String? = null

    /**
     * NFC connection and transceive operations must not run
     * on Android's main UI thread.
     */
    private lateinit var nfcExecutor: ExecutorService

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        nfcAdapter = NfcAdapter.getDefaultAdapter(this)

        nfcExecutor =
            Executors.newSingleThreadExecutor()

        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)

        setIntent(intent)

        handleIntent(intent)
    }

    override fun onResume() {
        super.onResume()

        enableForegroundDispatch()
    }

    override fun onPause() {
        disableForegroundDispatch()

        super.onPause()
    }

    override fun onDestroy() {
        eventSink = null

        if (::nfcExecutor.isInitialized) {
            nfcExecutor.shutdownNow()
        }

        super.onDestroy()
    }

    private fun enableForegroundDispatch() {
        val adapter = nfcAdapter

        if (adapter == null) {
            Log.w(
                TAG,
                "NFC is not supported on this device",
            )

            return
        }

        if (!adapter.isEnabled) {
            Log.w(
                TAG,
                "NFC is disabled",
            )

            return
        }

        val intent = Intent(
            this,
            javaClass,
        ).apply {
            addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }

        val pendingIntentFlags =
            if (
                Build.VERSION.SDK_INT >=
                Build.VERSION_CODES.S
            ) {
                PendingIntent.FLAG_MUTABLE or
                    PendingIntent.FLAG_UPDATE_CURRENT
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            }

        val pendingIntent =
            PendingIntent.getActivity(
                this,
                0,
                intent,
                pendingIntentFlags,
            )

        val intentFilters = arrayOf(
            IntentFilter(
                NfcAdapter.ACTION_TECH_DISCOVERED,
            ),
        )

        val technologyLists = arrayOf(
            arrayOf(
                "android.nfc.tech.IsoDep",
            ),
        )

        try {
            adapter.enableForegroundDispatch(
                this,
                pendingIntent,
                intentFilters,
                technologyLists,
            )

            Log.d(
                TAG,
                "NFC foreground dispatch enabled",
            )
        } catch (e: IllegalStateException) {
            Log.e(
                TAG,
                "Unable to enable NFC foreground dispatch",
                e,
            )
        }
    }

    private fun disableForegroundDispatch() {
        val adapter = nfcAdapter ?: return

        try {
            adapter.disableForegroundDispatch(this)

            Log.d(
                TAG,
                "NFC foreground dispatch disabled",
            )
        } catch (e: IllegalStateException) {
            Log.w(
                TAG,
                "Unable to disable NFC foreground dispatch",
                e,
            )
        }
    }

    private fun handleIntent(intent: Intent?) {
        if (intent == null) {
            return
        }

        val action = intent.action

        if (
            action != NfcAdapter.ACTION_TECH_DISCOVERED &&
            action != NfcAdapter.ACTION_TAG_DISCOVERED
        ) {
            return
        }

        val tag = extractTag(intent) ?: run {
            Log.w(
                TAG,
                "NFC intent did not contain a tag",
            )

            return
        }

        if (!::nfcExecutor.isInitialized) {
            Log.e(
                TAG,
                "NFC executor is not initialized",
            )

            return
        }

        nfcExecutor.execute {
            try {
                Log.d(
                    TAG,
                    "Reading NFC payload",
                )

                val payload =
                    TapReader().readPayload(tag)

                if (payload.isNullOrBlank()) {
                    Log.w(
                        TAG,
                        "No NFC payload was received",
                    )

                    return@execute
                }

                runOnUiThread {
                    deliverPayload(payload)
                }
            } catch (e: Exception) {
                Log.e(
                    TAG,
                    "Unable to process NFC tag",
                    e,
                )
            }
        }
    }

    private fun extractTag(intent: Intent): Tag? {
        return if (
            Build.VERSION.SDK_INT >=
            Build.VERSION_CODES.TIRAMISU
        ) {
            intent.getParcelableExtra(
                NfcAdapter.EXTRA_TAG,
                Tag::class.java,
            )
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra(
                NfcAdapter.EXTRA_TAG,
            )
        }
    }

    /**
     * Sends the payload directly when Flutter is listening.
     *
     * The payload is stored only when there is no active
     * EventChannel listener. This prevents the same payload
     * from being delivered again when Flutter resubscribes.
     */
    private fun deliverPayload(payload: String) {
        val currentSink = eventSink

        if (currentSink != null) {
            currentSink.success(payload)

            Log.d(
                TAG,
                "NFC payload delivered to Flutter",
            )
        } else {
            pendingPayload = payload

            Log.d(
                TAG,
                "NFC payload stored until Flutter listens",
            )
        }
    }

    override fun configureFlutterEngine(
        flutterEngine: FlutterEngine,
    ) {
        super.configureFlutterEngine(flutterEngine)

        configureEventChannel(flutterEngine)

        configureMethodChannel(flutterEngine)
    }

    private fun configureEventChannel(
        flutterEngine: FlutterEngine,
    ) {
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            EVENT_CHANNEL,
        ).setStreamHandler(
            object : EventChannel.StreamHandler {

                override fun onListen(
                    arguments: Any?,
                    events: EventChannel.EventSink?,
                ) {
                    eventSink = events

                    val payload = pendingPayload

                    if (
                        events != null &&
                        !payload.isNullOrBlank()
                    ) {
                        /*
                         * Clear before sending so that Flutter
                         * resubscription cannot receive it twice.
                         */
                        pendingPayload = null

                        events.success(payload)

                        Log.d(
                            TAG,
                            "Pending NFC payload delivered",
                        )
                    }
                }

                override fun onCancel(
                    arguments: Any?,
                ) {
                    eventSink = null

                    Log.d(
                        TAG,
                        "Flutter NFC event listener cancelled",
                    )
                }
            },
        )
    }

    private fun configureMethodChannel(
        flutterEngine: FlutterEngine,
    ) {
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            METHOD_CHANNEL,
        ).setMethodCallHandler { call, result ->

            when (call.method) {
                "setPayload" -> {
                    val payload =
                        call.argument<String>("payload")

                    if (payload.isNullOrBlank()) {
                        result.error(
                            "INVALID_PAYLOAD",
                            "NFC payload cannot be empty",
                            null,
                        )

                        return@setMethodCallHandler
                    }

                    TapHostApduService.payload =
                        payload

                    result.success(true)
                }

                "clearPayload" -> {
                    TapHostApduService.payload = ""

                    result.success(true)
                }

                "getPayload" -> {
                    /*
                     * This is mainly a recovery mechanism when
                     * an NFC payload arrived before Flutter was
                     * ready to listen.
                     */
                    val payload = pendingPayload

                    pendingPayload = null

                    result.success(payload)
                }

                "isNfcSupported" -> {
                    result.success(
                        nfcAdapter != null,
                    )
                }

                "isNfcEnabled" -> {
                    result.success(
                        nfcAdapter?.isEnabled == true,
                    )
                }

                "openNfcSettings" -> {
                    openNfcSettings(result)
                }

                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun openNfcSettings(
        result: MethodChannel.Result,
    ) {
        if (nfcAdapter == null) {
            result.error(
                "NFC_NOT_SUPPORTED",
                "This device does not support NFC",
                null,
            )

            return
        }

        try {
            startActivity(
                Intent(Settings.ACTION_NFC_SETTINGS),
            )

            result.success(true)
        } catch (e: ActivityNotFoundException) {
            Log.w(
                TAG,
                "Dedicated NFC settings are unavailable",
                e,
            )

            try {
                startActivity(
                    Intent(Settings.ACTION_WIRELESS_SETTINGS),
                )

                result.success(true)
            } catch (fallbackException: Exception) {
                Log.e(
                    TAG,
                    "Unable to open wireless settings",
                    fallbackException,
                )

                result.error(
                    "NFC_SETTINGS_UNAVAILABLE",
                    "Unable to open NFC settings",
                    null,
                )
            }
        } catch (e: Exception) {
            Log.e(
                TAG,
                "Unable to open NFC settings",
                e,
            )

            result.error(
                "NFC_SETTINGS_UNAVAILABLE",
                "Unable to open NFC settings",
                null,
            )
        }
    }
}