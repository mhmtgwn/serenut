package com.serenut.pos

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
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
            else -> {
                result.notImplemented()
            }
        }
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

            smsManager.sendTextMessage(phone, null, message, null, null)
            result.success(true)
        } catch (e: SecurityException) {
            result.error("PERMISSION_DENIED", "Security exception: ${e.message}", null)
        } catch (e: Exception) {
            result.error("SEND_FAILED", "Failed to send SMS: ${e.message}", null)
        }
    }

    private fun hasPermission(permission: String): Boolean {
        return ContextCompat.checkSelfPermission(context, permission) == PackageManager.PERMISSION_GRANTED
    }
}
