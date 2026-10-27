package com.serenut.pos

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.telephony.SmsManager
import android.telephony.SubscriptionInfo
import android.telephony.SubscriptionManager
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

class SmsSenderPlugin(private val context: Context) : MethodCallHandler {
    
    companion object {
        private var wakeLock: PowerManager.WakeLock? = null

        fun register(messenger: BinaryMessenger, context: Context) {
            val channel = MethodChannel(messenger, "serenut/sms_sender")
            channel.setMethodCallHandler(SmsSenderPlugin(context))
        }
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "getSmsSimCards" -> {
                getSmsSimCards(result)
            }
            "sendSmsViaSim" -> {
                val phone = call.argument<String>("phone")
                val message = call.argument<String>("message")
                val subscriptionId = call.argument<Int>("subscriptionId")
                
                if (phone == null || message == null) {
                    result.error("INVALID_ARGUMENTS", "Phone or message is null", null)
                    return
                }
                sendSmsViaSim(phone, message, subscriptionId, result)
            }
            "acquireWakeLock" -> {
                val tag = call.argument<String>("tag") ?: "SmsGateway"
                acquireWakeLock(tag)
                result.success(true)
            }
            "releaseWakeLock" -> {
                releaseWakeLock()
                result.success(true)
            }
            "isIgnoringBatteryOptimizations" -> {
                val powerManager = context.getSystemService(Context.POWER_SERVICE) as PowerManager
                val isIgnoring = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    powerManager.isIgnoringBatteryOptimizations(context.packageName)
                } else {
                    true
                }
                result.success(isIgnoring)
            }
            "requestIgnoreBatteryOptimizations" -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                        data = Uri.parse("package:${context.packageName}")
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    context.startActivity(intent)
                    result.success(true)
                } else {
                    result.success(false)
                }
            }
            else -> {
                result.notImplemented()
            }
        }
    }

    private fun acquireWakeLock(tag: String) {
        try {
            val powerManager = context.getSystemService(Context.POWER_SERVICE) as PowerManager
            if (wakeLock == null) {
                wakeLock = powerManager.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "SerenutPOS:$tag")
                wakeLock?.setReferenceCounted(false)
            }
            if (wakeLock?.isHeld != true) {
                // Servis çalıştığı sürece CPU'nun derin uykuya geçmesini önler
                wakeLock?.acquire()
            }
        } catch (_: Exception) {}
    }

    private fun releaseWakeLock() {
        try {
            if (wakeLock != null && wakeLock!!.isHeld) {
                wakeLock?.release()
                wakeLock = null
            }
        } catch (_: Exception) {}
    }

    private fun getSmsSimCards(result: Result) {
        if (!hasPermission(Manifest.permission.READ_PHONE_STATE)) {
            result.error("PERMISSION_DENIED", "READ_PHONE_STATE permission is required", null)
            return
        }

        val simList = ArrayList<Map<String, Any>>()
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP_MR1) {
                val subscriptionManager = SubscriptionManager.from(context)
                val activeSubscriptionInfoList = subscriptionManager.activeSubscriptionInfoList
                if (activeSubscriptionInfoList != null) {
                    for (info in activeSubscriptionInfoList) {
                        val simInfo = HashMap<String, Any>()
                        simInfo["subscriptionId"] = info.subscriptionId
                        simInfo["displayName"] = info.displayName?.toString() ?: "Unknown Operator"
                        simInfo["simSlotIndex"] = info.simSlotIndex
                        simList.add(simInfo)
                    }
                }
            }
            result.success(simList)
        } catch (e: Exception) {
            result.error("READ_FAILED", e.message, null)
        }
    }

    private fun sendSmsViaSim(phone: String, message: String, subscriptionId: Int?, result: Result) {
        if (!hasPermission(Manifest.permission.SEND_SMS)) {
            result.error("PERMISSION_DENIED", "SEND_SMS permission is required", null)
            return
        }

        val cleanPhone = phone.trim().replace(Regex("[^0-9+]"), "")
        if (cleanPhone.isEmpty()) {
            result.error("INVALID_PHONE", "Destination phone number is empty or invalid", null)
            return
        }

        try {
            val smsManager: SmsManager = if (subscriptionId == null) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    context.getSystemService(SmsManager::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    SmsManager.getDefault()
                }
            } else {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    val manager = context.getSystemService(SmsManager::class.java)
                    if (manager != null) {
                        manager.createForSubscriptionId(subscriptionId)
                    } else {
                        @Suppress("DEPRECATION")
                        SmsManager.getSmsManagerForSubscriptionId(subscriptionId)
                    }
                } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP_MR1) {
                    @Suppress("DEPRECATION")
                    SmsManager.getSmsManagerForSubscriptionId(subscriptionId)
                } else {
                    @Suppress("DEPRECATION")
                    SmsManager.getDefault()
                }
            }

            if (smsManager == null) {
                result.error("SIM_NOT_FOUND", "SmsManager could not be created", null)
                return
            }

            val normalizedMessage = normalizeToGsm7(message)
            val parts = smsManager.divideMessage(normalizedMessage)
            if (parts.size > 1) {
                smsManager.sendMultipartTextMessage(cleanPhone, null, parts, null, null)
            } else {
                smsManager.sendTextMessage(cleanPhone, null, normalizedMessage, null, null)
            }
            result.success(true)
        } catch (e: SecurityException) {
            result.error("PERMISSION_DENIED", "Security exception: ${e.message}", null)
        } catch (e: Exception) {
            result.error("SEND_FAILED", "Failed to send SMS: ${e.message}", null)
        }
    }

    private fun normalizeToGsm7(text: String): String {
        return text
            .replace('ı', 'i')
            .replace('İ', 'I')
            .replace('ğ', 'g')
            .replace('Ğ', 'G')
            .replace('ş', 's')
            .replace('Ş', 'S')
            .replace('ç', 'c')
            .replace('Ç', 'C')
            .replace('ö', 'o')
            .replace('Ö', 'O')
            .replace('ü', 'u')
            .replace('Ü', 'U')
    }

    private fun hasPermission(permission: String): Boolean {
        return ContextCompat.checkSelfPermission(context, permission) == PackageManager.PERMISSION_GRANTED
    }
}
