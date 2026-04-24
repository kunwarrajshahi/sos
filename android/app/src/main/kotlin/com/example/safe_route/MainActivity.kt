package com.example.safe_route

import android.Manifest
import android.app.Activity
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.Build
import android.os.BatteryManager
import android.os.Bundle
import android.telephony.SmsManager
import android.telephony.SubscriptionManager
import android.view.WindowManager
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val smsChannelName = "safe_route/sms"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
            val keyguardManager = getSystemService(KEYGUARD_SERVICE) as android.app.KeyguardManager
            keyguardManager.requestDismissKeyguard(this, null)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
            )
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            smsChannelName,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "sendDirectSms" -> {
                    val phoneNumber = call.argument<String>("phoneNumber")
                    val message = call.argument<String>("message")
                    val subscriptionId = call.argument<Int>("subscriptionId")

                    if (phoneNumber.isNullOrBlank() || message.isNullOrBlank()) {
                        result.success(
                            mapOf(
                                "success" to false,
                                "errorMessage" to "Missing phone number or message.",
                            ),
                        )
                        return@setMethodCallHandler
                    }

                    sendDirectSms(
                        phoneNumber = phoneNumber,
                        message = message,
                        subscriptionId = subscriptionId,
                        result = result,
                    )
                }

                "getSmsSubscriptions" -> {
                    result.success(getSmsSubscriptions())
                }

                "getBatteryLevel" -> {
                    result.success(getBatteryLevel())
                }

                "launchEmergencyCall" -> {
                    val phoneNumber = call.argument<String>("phoneNumber")
                    if (phoneNumber.isNullOrBlank()) {
                        result.success(
                            mapOf(
                                "success" to false,
                                "usedActionCall" to false,
                                "errorMessage" to "Missing phone number.",
                            ),
                        )
                        return@setMethodCallHandler
                    }

                    result.success(launchEmergencyCall(phoneNumber))
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun sendDirectSms(
        phoneNumber: String,
        message: String,
        subscriptionId: Int?,
        result: MethodChannel.Result,
    ) {
        if (
            ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.SEND_SMS,
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            result.success(
                mapOf(
                    "success" to false,
                    "errorMessage" to "SEND_SMS permission not granted.",
                ),
            )
            return
        }

        val smsManager = getSmsManager(subscriptionId)
        val action = "com.example.safe_route.SMS_SENT.${System.nanoTime()}"
        val sentIntent = Intent(action)
        val pendingIntentFlags =
            PendingIntent.FLAG_UPDATE_CURRENT or
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    PendingIntent.FLAG_IMMUTABLE
                } else {
                    0
                }
        val sentPendingIntent = PendingIntent.getBroadcast(
            this,
            action.hashCode(),
            sentIntent,
            pendingIntentFlags,
        )

        var completed = false
        var receiver: BroadcastReceiver? = null

        fun finish(payload: Map<String, Any?>) {
            if (completed) {
                return
            }
            completed = true
            try {
                if (receiver != null) {
                    unregisterReceiver(receiver)
                }
            } catch (_: Exception) {
            }
            result.success(payload)
        }

        receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                val errorMessage =
                    when (resultCode) {
                        Activity.RESULT_OK -> null
                        SmsManager.RESULT_ERROR_GENERIC_FAILURE ->
                            "Generic SMS failure."
                        SmsManager.RESULT_ERROR_NO_SERVICE ->
                            "No mobile service available."
                        SmsManager.RESULT_ERROR_NULL_PDU ->
                            "SMS payload was invalid."
                        SmsManager.RESULT_ERROR_RADIO_OFF ->
                            "Device radio is off."
                        else -> "Direct SMS failed with code $resultCode."
                    }

                finish(
                    mapOf(
                        "success" to (resultCode == Activity.RESULT_OK),
                        "errorCode" to resultCode,
                        "errorMessage" to errorMessage,
                    ),
                )
            }
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(receiver, IntentFilter(action), RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("DEPRECATION")
            registerReceiver(receiver, IntentFilter(action))
        }

        try {
            smsManager.sendTextMessage(phoneNumber, null, message, sentPendingIntent, null)
        } catch (e: Exception) {
            finish(
                mapOf(
                    "success" to false,
                    "errorMessage" to (e.message ?: "Direct SMS failed."),
                ),
            )
        }
    }

    private fun getSmsManager(subscriptionId: Int?): SmsManager {
        if (
            subscriptionId != null &&
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP_MR1
        ) {
            return SmsManager.getSmsManagerForSubscriptionId(subscriptionId)
        }
        return SmsManager.getDefault()
    }

    private fun getSmsSubscriptions(): List<Map<String, Any?>> {
        if (
            Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP_MR1 ||
            ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.READ_PHONE_STATE,
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            return emptyList()
        }

        val subscriptionManager = getSystemService(SubscriptionManager::class.java)
        val defaultSmsSubscriptionId = SubscriptionManager.getDefaultSmsSubscriptionId()
        val activeSubscriptions = try {
            subscriptionManager.activeSubscriptionInfoList ?: emptyList()
        } catch (_: SecurityException) {
            emptyList()
        }

        return activeSubscriptions.map { info ->
            mapOf(
                "subscriptionId" to info.subscriptionId,
                "displayName" to (info.displayName?.toString() ?: "SIM"),
                "carrierName" to (info.carrierName?.toString() ?: ""),
                "simSlotIndex" to info.simSlotIndex,
                "isDefault" to (info.subscriptionId == defaultSmsSubscriptionId),
            )
        }
    }

    private fun getBatteryLevel(): Int? {
        val batteryManager = getSystemService(BATTERY_SERVICE) as? BatteryManager
        val level =
            batteryManager?.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
                ?: return null
        return if (level in 0..100) level else null
    }

    private fun launchEmergencyCall(phoneNumber: String): Map<String, Any?> {
        return try {
            val hasCallPermission =
                ContextCompat.checkSelfPermission(
                    this,
                    Manifest.permission.CALL_PHONE,
                ) == PackageManager.PERMISSION_GRANTED

            val action =
                if (hasCallPermission) {
                    Intent.ACTION_CALL
                } else {
                    Intent.ACTION_DIAL
                }

            val intent =
                Intent(action).apply {
                    data = android.net.Uri.parse("tel:$phoneNumber")
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
            startActivity(intent)
            mapOf(
                "success" to true,
                "usedActionCall" to hasCallPermission,
                "errorMessage" to null,
            )
        } catch (e: Exception) {
            mapOf(
                "success" to false,
                "usedActionCall" to false,
                "errorMessage" to (e.message ?: "Failed to launch emergency call."),
            )
        }
    }
}
