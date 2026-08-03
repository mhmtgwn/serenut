import re

with open('android/app/src/main/kotlin/com/serenut/pos/BluetoothPrinterHandler.kt', 'r', encoding='utf-8') as f:
    content = f.read()

discovery_receiver = '''    private val discoveryReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            when (intent?.action) {
                BluetoothDevice.ACTION_FOUND -> {
                    val device = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        intent.getParcelableExtra(
                            BluetoothDevice.EXTRA_DEVICE,
                            BluetoothDevice::class.java
                        )
                    } else {
                        @Suppress("DEPRECATION")
                        intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE)
                    }
                    if (device != null && hasBluetoothConnectPermission()) {
                        discoveredDevices[device.address] = mapOf(
                            "name" to (device.name ?: "Ýsimsiz cihaz"),
                            "address" to device.address
                        )
                    }
                }
                BluetoothAdapter.ACTION_DISCOVERY_FINISHED -> finishDiscovery()
            }
        }
    }'''

handler_code = '''
    private val handler = object : Handler(Looper.getMainLooper()) {
        override fun handleMessage(msg: Message) {
            Log.d(TAG, "Handler message: \")
            when (msg.what) {
                PrinterConstants.Connect.SUCCESS -> {
                    Log.d(TAG, "? Baðlantý baþarýlý")
                    isConnected = true
                    
                    // SDK örneðindeki gibi printer instance'ý getPrinter() ile al
                    printerInstance = getPrinter()
                    Log.d(TAG, "Printer instance güncellendi: \")
                    
                    // BroadcastReceiver'ý kaydet (SDK örneðindeki gibi)
                    if (!hasRegDisconnectReceiver) {
                        try {
                            context.registerReceiver(disconnectReceiver, filter)
                            hasRegDisconnectReceiver = true
                            Log.d(TAG, "BroadcastReceiver kaydedildi")
                        } catch (e: Exception) {
                            Log.e(TAG, "Receiver kayýt hatasý: \")
                        }
                    }
                    
                    connectionCallback?.success(true)
                    connectionCallback = null
                }
                PrinterConstants.Connect.FAILED -> {
                    Log.e(TAG, "? Baðlantý baþarýsýz")
                    isConnected = false
                    connectionCallback?.success(false)
                    connectionCallback = null
                }
                PrinterConstants.Connect.CLOSED -> {
                    Log.d(TAG, "? Baðlantý kapandý")
                    isConnected = false
                    if (connectionCallback == null) {
                        printerInstance = null
                    } else {
                        Log.d(TAG, "Baðlantý denemesi sýrasýnda gelen CLOSED (103) yoksayýldý.")
                    }
                }
                PrinterConstants.Connect.NODEVICE -> {
                    Log.w(TAG, "? Kayýtlý cihaz bulunamadý")
                    isConnected = false
                    connectionCallback?.success(false)
                    connectionCallback = null
                }
            }
        }
    }
    
    init {
        bluetoothAdapter = BluetoothAdapter.getDefaultAdapter()
        
        // BroadcastReceiver için IntentFilter ayarla (SDK örneðindeki gibi)
        filter.addAction(BluetoothDevice.ACTION_ACL_DISCONNECTED)
        
        Log.d(TAG, "BluetoothPrinterHandler baþlatýldý - SDK Pattern")
    }
    
    // Baðlantý kopma olaylarýný dinle (SDK örneðindeki gibi)
    private val disconnectReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {'''

start_idx = content.find('    private val discoveryReceiver = object : BroadcastReceiver() {')
if start_idx == -1:
    print('Could not find discoveryReceiver')
    exit(1)

end_idx = content.find('            val action = intent?.action\n            val device = intent?.getParcelableExtra<BluetoothDevice>(BluetoothDevice.EXTRA_DEVICE)', start_idx)

if end_idx == -1:
    print('Could not find end index')
    exit(1)

new_content = content[:start_idx] + discovery_receiver + handler_code + '\n' + content[end_idx:]

with open('android/app/src/main/kotlin/com/serenut/pos/BluetoothPrinterHandler.kt', 'w', encoding='utf-8') as f:
    f.write(new_content)

print('Successfully repaired BluetoothPrinterHandler.kt')
