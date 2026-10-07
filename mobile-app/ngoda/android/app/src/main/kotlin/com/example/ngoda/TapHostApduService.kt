package com.divinebytes.ngoda

import android.nfc.cardemulation.HostApduService
import android.os.Bundle
import android.util.Log
import java.nio.charset.StandardCharsets

class TapHostApduService : HostApduService() {

    companion object {
        private const val TAG = "NgodaHce"

        /**
         * Keep the payload reasonably small for reliable APDU transfer.
         *
         * This should be enough for a compact signed transaction payload.
         * Increase only when testing proves it is necessary.
         */
        private const val MAX_PAYLOAD_BYTES = 1024

        /**
         * Flutter sets this before the user presents the phone for tapping.
         *
         * Volatile ensures the HCE service sees the latest value written
         * through MainActivity's MethodChannel.
         */
        @Volatile
        var payload: String = ""

        private val STATUS_SUCCESS = byteArrayOf(
            0x90.toByte(),
            0x00.toByte(),
        )

        private val STATUS_UNKNOWN_AID = byteArrayOf(
            0x6A.toByte(),
            0x82.toByte(),
        )

        private val STATUS_WRONG_LENGTH = byteArrayOf(
            0x67.toByte(),
            0x00.toByte(),
        )

        private val STATUS_INS_NOT_SUPPORTED = byteArrayOf(
            0x6D.toByte(),
            0x00.toByte(),
        )

        private val STATUS_CLA_NOT_SUPPORTED = byteArrayOf(
            0x6E.toByte(),
            0x00.toByte(),
        )

        private val STATUS_CONDITIONS_NOT_SATISFIED = byteArrayOf(
            0x69.toByte(),
            0x85.toByte(),
        )

        private val STATUS_FAILED = byteArrayOf(
            0x6F.toByte(),
            0x00.toByte(),
        )

        private const val SELECT_CLA = 0x00
        private const val SELECT_INS = 0xA4
        private const val SELECT_P1 = 0x04
        private const val SELECT_P2 = 0x00

        private val AID = byteArrayOf(
            0xF2.toByte(),
            0x22.toByte(),
            0x22.toByte(),
            0x22.toByte(),
            0x22.toByte(),
        )
    }

    override fun processCommandApdu(
        commandApdu: ByteArray?,
        extras: Bundle?,
    ): ByteArray {
        if (commandApdu == null) {
            Log.w(TAG, "Received null APDU")

            return STATUS_WRONG_LENGTH
        }

        if (commandApdu.size < 5) {
            Log.w(
                TAG,
                "APDU is too short: ${commandApdu.size}",
            )

            return STATUS_WRONG_LENGTH
        }

        val cla = commandApdu[0].toInt() and 0xFF
        val ins = commandApdu[1].toInt() and 0xFF
        val p1 = commandApdu[2].toInt() and 0xFF
        val p2 = commandApdu[3].toInt() and 0xFF

        if (cla != SELECT_CLA) {
            Log.w(
                TAG,
                "Unsupported APDU class: ${cla.toHex()}",
            )

            return STATUS_CLA_NOT_SUPPORTED
        }

        if (ins != SELECT_INS) {
            Log.w(
                TAG,
                "Unsupported APDU instruction: ${ins.toHex()}",
            )

            return STATUS_INS_NOT_SUPPORTED
        }

        if (
            p1 != SELECT_P1 ||
            p2 != SELECT_P2
        ) {
            Log.w(
                TAG,
                "Unsupported SELECT parameters: " +
                    "P1=${p1.toHex()}, P2=${p2.toHex()}",
            )

            return STATUS_INS_NOT_SUPPORTED
        }

        val receivedAid = extractAid(commandApdu)
            ?: return STATUS_WRONG_LENGTH

        if (!receivedAid.contentEquals(AID)) {
            Log.w(TAG, "Unknown AID selected")

            return STATUS_UNKNOWN_AID
        }

        val currentPayload = payload

        if (currentPayload.isBlank()) {
            Log.w(TAG, "No active NFC payload")

            return STATUS_CONDITIONS_NOT_SATISFIED
        }

        return try {
            val payloadBytes = currentPayload.toByteArray(
                StandardCharsets.UTF_8,
            )

            if (payloadBytes.isEmpty()) {
                Log.w(TAG, "Encoded NFC payload is empty")

                return STATUS_CONDITIONS_NOT_SATISFIED
            }

            if (payloadBytes.size > MAX_PAYLOAD_BYTES) {
                Log.e(
                    TAG,
                    "NFC payload is too large: " +
                        "${payloadBytes.size} bytes",
                )

                return STATUS_WRONG_LENGTH
            }

            Log.d(
                TAG,
                "Returning NFC payload: " +
                    "${payloadBytes.size} bytes",
            )

            payloadBytes + STATUS_SUCCESS
        } catch (e: Exception) {
            Log.e(
                TAG,
                "Unable to build HCE response",
                e,
            )

            STATUS_FAILED
        }
    }

    private fun extractAid(
        commandApdu: ByteArray,
    ): ByteArray? {
        val aidLength =
            commandApdu[4].toInt() and 0xFF

        if (aidLength == 0) {
            Log.w(TAG, "SELECT APDU contains an empty AID")

            return null
        }

        val aidStart = 5
        val aidEnd = aidStart + aidLength

        if (aidEnd > commandApdu.size) {
            Log.w(
                TAG,
                "Invalid AID length: " +
                    "declared=$aidLength, " +
                    "APDU size=${commandApdu.size}",
            )

            return null
        }

        return commandApdu.copyOfRange(
            aidStart,
            aidEnd,
        )
    }

    override fun onDeactivated(reason: Int) {
        val reasonName = when (reason) {
            DEACTIVATION_LINK_LOSS ->
                "LINK_LOSS"

            DEACTIVATION_DESELECTED ->
                "DESELECTED"

            else ->
                "UNKNOWN"
        }

        Log.d(
            TAG,
            "HCE deactivated: " +
                "$reasonName ($reason)",
        )
    }

    private fun Int.toHex(): String {
        return "0x%02X".format(this)
    }
}