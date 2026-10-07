package com.divinebytes.ngoda

import android.nfc.Tag
import android.nfc.tech.IsoDep
import android.util.Log
import java.io.IOException
import java.nio.charset.StandardCharsets
import android.nfc.TagLostException

class TapReader {

    companion object {
        private const val TAG = "NgodaTapReader"

        private const val NFC_TIMEOUT_MS = 3_000
        private const val MAX_ATTEMPTS = 3
        private const val RETRY_DELAY_MS = 150L

        private const val STATUS_OK_SW1 = 0x90
        private const val STATUS_OK_SW2 = 0x00

        private val SELECT_APDU = byteArrayOf(
            0x00.toByte(),
            0xA4.toByte(),
            0x04.toByte(),
            0x00.toByte(),
            0x05.toByte(),
            0xF2.toByte(),
            0x22.toByte(),
            0x22.toByte(),
            0x22.toByte(),
            0x22.toByte(),
        )
    }

    fun readPayload(tag: Tag): String? {
        val isoDep = IsoDep.get(tag)

        if (isoDep == null) {
            Log.w(TAG, "NFC tag does not support IsoDep")

            return null
        }

        return try {
            isoDep.timeout = NFC_TIMEOUT_MS

            Log.d(TAG, "Connecting to NFC device")

            isoDep.connect()

            if (!isoDep.isConnected) {
                Log.w(TAG, "IsoDep connection was not established")

                return null
            }

            Log.d(TAG, "IsoDep connection established")

            val response = transceiveWithRetry(
                isoDep = isoDep,
                command = SELECT_APDU,
            ) ?: return null

            parseResponse(response)
        } catch (e: IOException) {
            Log.e(
                TAG,
                "NFC communication failed",
                e,
            )

            null
        } catch (e: SecurityException) {
            Log.e(
                TAG,
                "NFC access was rejected",
                e,
            )

            null
        } catch (e: Exception) {
            Log.e(
                TAG,
                "Unexpected NFC reader error",
                e,
            )

            null
        } finally {
            closeQuietly(isoDep)
        }
    }

    private fun transceiveWithRetry(
        isoDep: IsoDep,
        command: ByteArray,
    ): ByteArray? {
        for (attempt in 1..3) {
            try {
                Log.d(
                    TAG,
                    "Sending NFC command, attempt $attempt",
                )

                return isoDep.transceive(command)
            } catch (e: TagLostException) {
                Log.w(
                    TAG,
                    "NFC device moved out of range",
                    e,
                )

                return null
            } catch (e: IOException) {
                Log.w(
                    TAG,
                    "NFC transceive failed on attempt $attempt",
                    e,
                )

                if (attempt < 3) {
                    try {
                        Thread.sleep(100)
                    } catch (_: InterruptedException) {
                        Thread.currentThread().interrupt()
                        return null
                    }
                }
            }
        }

        return null
    }

    private fun parseResponse(
        response: ByteArray,
    ): String? {
        if (response.size < 2) {
            Log.w(
                TAG,
                "NFC response does not contain status bytes",
            )

            return null
        }

        val sw1 =
            response[response.lastIndex - 1].toInt() and 0xFF

        val sw2 =
            response[response.lastIndex].toInt() and 0xFF

        if (
            sw1 != STATUS_OK_SW1 ||
            sw2 != STATUS_OK_SW2
        ) {
            Log.w(
                TAG,
                "NFC command failed with status " +
                    "%02X%02X".format(sw1, sw2),
            )

            return null
        }

        val payloadLength = response.size - 2

        if (payloadLength == 0) {
            Log.w(TAG, "NFC response payload is empty")

            return null
        }

        val payloadBytes = response.copyOfRange(
            0,
            payloadLength,
        )

        return try {
            payloadBytes.toString(
                StandardCharsets.UTF_8,
            )
        } catch (e: Exception) {
            Log.e(
                TAG,
                "Unable to decode NFC payload",
                e,
            )

            null
        }
    }

    private fun sleepBeforeRetry(): Boolean {
        return try {
            Thread.sleep(RETRY_DELAY_MS)

            true
        } catch (e: InterruptedException) {
            Thread.currentThread().interrupt()

            Log.w(
                TAG,
                "NFC retry was interrupted",
                e,
            )

            false
        }
    }

    private fun closeQuietly(
        isoDep: IsoDep,
    ) {
        try {
            if (isoDep.isConnected) {
                isoDep.close()

                Log.d(TAG, "IsoDep connection closed")
            }
        } catch (e: IOException) {
            Log.w(
                TAG,
                "Unable to close IsoDep connection",
                e,
            )
        }
    }
}