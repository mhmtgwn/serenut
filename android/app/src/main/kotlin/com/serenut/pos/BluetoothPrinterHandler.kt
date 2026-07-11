package com.serenut.pos

import android.app.Activity
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Handler
import android.os.Looper
import android.os.Message
import android.util.Log
import com.android.print.sdk.PrinterInstance
import com.android.print.sdk.PrinterConstants
import com.android.print.sdk.PrinterConstants.Command
import com.android.print.sdk.Barcode
import com.android.print.sdk.bluetooth.BluetoothPort
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.text.SimpleDateFormat
import java.util.*

/**
 * Android Print SDK Bluetooth Handler
 * SDK'nın orijinal pattern'ini takip eder
 */
class BluetoothPrinterHandler(private val context: Context) : MethodChannel.MethodCallHandler {
    
    companion object {
        private const val TAG = "BluetoothPrinter"
        const val CONNECT_DEVICE = 1
        const val ENABLE_BT = 2
    }
    
    private var bluetoothAdapter: BluetoothAdapter? = null
    private var printerInstance: PrinterInstance? = null
    private var bluetoothPort: BluetoothPort? = null
    private var isConnected = false
    private var connectionCallback: MethodChannel.Result? = null
    private var hasRegDisconnectReceiver = false
    private val filter = IntentFilter()
    private var currentMac: String? = null
    
    private val handler = object : Handler(Looper.getMainLooper()) {
        override fun handleMessage(msg: Message) {
            Log.d(TAG, "Handler message: ${msg.what}")
            when (msg.what) {
                PrinterConstants.Connect.SUCCESS -> {
                    Log.d(TAG, "✓ Bağlantı başarılı")
                    isConnected = true
                    
                    // SDK örneğindeki gibi printer instance'ı getPrinter() ile al
                    printerInstance = getPrinter()
                    Log.d(TAG, "Printer instance güncellendi: ${printerInstance != null}")
                    
                    // BroadcastReceiver'ı kaydet (SDK örneğindeki gibi)
                    if (!hasRegDisconnectReceiver) {
                        try {
                            context.registerReceiver(disconnectReceiver, filter)
                            hasRegDisconnectReceiver = true
                            Log.d(TAG, "BroadcastReceiver kaydedildi")
                        } catch (e: Exception) {
                            Log.e(TAG, "Receiver kayıt hatası: ${e.message}")
                        }
                    }
                    
                    connectionCallback?.success(true)
                    connectionCallback = null
                }
                PrinterConstants.Connect.FAILED -> {
                    Log.e(TAG, "✗ Bağlantı başarısız")
                    isConnected = false
                    connectionCallback?.success(false)
                    connectionCallback = null
                }
                PrinterConstants.Connect.CLOSED -> {
                    Log.d(TAG, "✗ Bağlantı kapandı")
                    isConnected = false
                    printerInstance = null
                }
                PrinterConstants.Connect.NODEVICE -> {
                    Log.w(TAG, "✗ Kayıtlı cihaz bulunamadı")
                    isConnected = false
                    connectionCallback?.success(false)
                    connectionCallback = null
                }
            }
        }
    }
    
    init {
        bluetoothAdapter = BluetoothAdapter.getDefaultAdapter()
        
        // BroadcastReceiver için IntentFilter ayarla (SDK örneğindeki gibi)
        filter.addAction(BluetoothDevice.ACTION_ACL_DISCONNECTED)
        
        Log.d(TAG, "BluetoothPrinterHandler başlatıldı - SDK Pattern")
    }
    
    // Bağlantı kopma olaylarını dinle (SDK örneğindeki gibi)
    private val disconnectReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            val action = intent?.action
            val device = intent?.getParcelableExtra<BluetoothDevice>(BluetoothDevice.EXTRA_DEVICE)
            
            if (action == BluetoothDevice.ACTION_ACL_DISCONNECTED) {
                Log.w(TAG, "Bluetooth bağlantısı koptu: ${device?.address}")
                
                if (device != null && printerInstance != null && 
                    printerInstance!!.isConnected && device.address == currentMac) {
                    
                    // Bağlantıyı kapat
                    try {
                        printerInstance?.closeConnection()
                        printerInstance = null
                    } catch (e: Exception) {
                        Log.e(TAG, "Close error: ${e.message}")
                    }
                    
                    isConnected = false
                    Log.d(TAG, "Device disconnected via broadcast")
                }
            }
        }
    }
    
    // SDK örneğindeki getPrinter() metodu
    private fun getPrinter(): PrinterInstance? {
        if (printerInstance != null && printerInstance!!.isConnected) {
            if (!hasRegDisconnectReceiver) {
                try {
                    context.registerReceiver(disconnectReceiver, filter)
                    hasRegDisconnectReceiver = true
                    Log.d(TAG, "getPrinter() - BroadcastReceiver kaydedildi")
                } catch (e: Exception) {
                    Log.e(TAG, "getPrinter() - Receiver kayıt hatası: ${e.message}")
                }
            }
        }
        return printerInstance
    }
    
    // Cleanup metodu
    fun cleanup() {
        try {
            if (hasRegDisconnectReceiver) {
                context.unregisterReceiver(disconnectReceiver)
                hasRegDisconnectReceiver = false
                Log.d(TAG, "BroadcastReceiver kaldırıldı")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Cleanup error: ${e.message}")
        }
        
        try {
            printerInstance?.closeConnection()
            printerInstance = null
            bluetoothPort = null
        } catch (e: Exception) {
            Log.e(TAG, "Close error: ${e.message}")
        }
    }
    
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isBluetoothAvailable" -> {
                result.success(bluetoothAdapter != null && bluetoothAdapter!!.isEnabled)
            }
            
            "getPairedDevices" -> {
                getPairedDevices(result)
            }
            
            "scanDevices" -> {
                scanDevices(result)
            }
            
            "connect" -> {
                val address = call.argument<String>("address")
                if (address != null) {
                    connectToDevice(address, result)
                } else {
                    result.error("INVALID_ARGUMENT", "Address is required", null)
                }
            }
            
            "autoConnect" -> {
                autoConnectToDevice(result)
            }
            
            "disconnect" -> {
                disconnect(result)
            }
            
            "printRawData" -> {
                val data = call.argument<ByteArray>("data")
                if (data != null) {
                    printRawData(data, result)
                } else {
                    result.error("INVALID_ARGUMENT", "Data is required", null)
                }
            }
            
            "testPrint" -> {
                val protocol = call.argument<String>("protocol") ?: "escpos"
                testPrint(protocol, result)
            }
            
            "getPrinterInfo" -> {
                getPrinterInfo(result)
            }
            
            else -> {
                result.notImplemented()
            }
        }
    }
    
    private fun getPairedDevices(result: MethodChannel.Result) {
        try {
            val pairedDevices = bluetoothAdapter?.bondedDevices
            val deviceList = mutableListOf<Map<String, String>>()
            
            pairedDevices?.forEach { device ->
                deviceList.add(mapOf(
                    "name" to (device.name ?: "Unknown"),
                    "address" to device.address
                ))
            }
            
            result.success(deviceList)
        } catch (e: Exception) {
            result.error("ERROR", "Failed to get paired devices: ${e.message}", null)
        }
    }
    
    private fun scanDevices(result: MethodChannel.Result) {
        // Scanning requires runtime permissions and is complex
        // For now, just return paired devices
        getPairedDevices(result)
    }
    
    private fun connectToDevice(address: String, result: MethodChannel.Result) {
        try {
            Log.d(TAG, "→ Bağlanılıyor: $address")
            
            if (bluetoothAdapter == null) {
                Log.e(TAG, "Bluetooth adapter yok")
                result.error("NO_BLUETOOTH", "Bluetooth adapter not available", null)
                return
            }
            
            // Mevcut bağlantıyı kapat (SDK örneğindeki gibi)
            if (printerInstance != null) {
                Log.d(TAG, "Mevcut bağlantı kapatılıyor...")
                try {
                    printerInstance?.closeConnection()
                    Thread.sleep(500)
                } catch (e: Exception) {
                    Log.w(TAG, "Close error: ${e.message}")
                }
                printerInstance = null
            }
            
            // BroadcastReceiver'ı kaldır
            if (hasRegDisconnectReceiver) {
                try {
                    context.unregisterReceiver(disconnectReceiver)
                    hasRegDisconnectReceiver = false
                } catch (e: Exception) {
                    Log.w(TAG, "Unregister error: ${e.message}")
                }
            }
            
            isConnected = false
            currentMac = address
            connectionCallback = result
            
            // SDK'nın btConnnect metodunu kullan (SDK örneğindeki gibi HER SEFERINDE YENİ INSTANCE)
            Log.d(TAG, "BluetoothPort.btConnnect() çağrılıyor...")
            bluetoothPort = BluetoothPort()
            printerInstance = bluetoothPort!!.btConnnect(context, address, bluetoothAdapter, handler)
            
            // Bağlantı bilgisini kaydet (SDK örneğindeki gibi)
            com.android.print.sdk.util.Utils.saveBtConnInfo(context, address)
            
            // Timeout (5 saniye)
            Handler(Looper.getMainLooper()).postDelayed({
                if (connectionCallback != null) {
                    Log.w(TAG, "⏱ Bağlantı timeout")
                    connectionCallback?.success(false)
                    connectionCallback = null
                }
            }, 5000)
            
        } catch (e: Exception) {
            Log.e(TAG, "✗ Bağlantı hatası: ${e.message}", e)
            isConnected = false
            connectionCallback = null
            result.error("CONNECTION_ERROR", "Failed to connect: ${e.message}", null)
        }
    }
    
    // Otomatik bağlantı (SDK örneğindeki btAutoConn)
    private fun autoConnectToDevice(result: MethodChannel.Result) {
        try {
            Log.d(TAG, "→ Otomatik bağlantı başlatılıyor...")
            
            if (bluetoothAdapter == null) {
                Log.e(TAG, "Bluetooth adapter yok")
                result.error("NO_BLUETOOTH", "Bluetooth adapter not available", null)
                return
            }
            
            connectionCallback = result
            
            // SDK'nın btAutoConn metodunu kullan
            printerInstance = BluetoothPort().btAutoConn(context, bluetoothAdapter, handler)
            
            if (printerInstance == null) {
                Log.w(TAG, "Kayıtlı cihaz bulunamadı")
                handler.obtainMessage(PrinterConstants.Connect.NODEVICE).sendToTarget()
            }
            
            // Timeout
            Handler(Looper.getMainLooper()).postDelayed({
                if (connectionCallback != null) {
                    Log.w(TAG, "⏱ Otomatik bağlantı timeout")
                    connectionCallback?.success(false)
                    connectionCallback = null
                }
            }, 5000)
            
        } catch (e: Exception) {
            Log.e(TAG, "✗ Otomatik bağlantı hatası: ${e.message}", e)
            connectionCallback = null
            result.error("CONNECTION_ERROR", "Auto connect failed: ${e.message}", null)
        }
    }
    
    private fun disconnect(result: MethodChannel.Result) {
        try {
            Log.d(TAG, "→ Bağlanı kesiliyor...")
            
            // Printer'ı kapat
            if (printerInstance != null) {
                printerInstance?.closeConnection()
                printerInstance = null
            }
            
            // BroadcastReceiver'ı kaldır (SDK örneğindeki gibi)
            if (hasRegDisconnectReceiver) {
                try {
                    context.unregisterReceiver(disconnectReceiver)
                    hasRegDisconnectReceiver = false
                    Log.d(TAG, "BroadcastReceiver kaldırıldı")
                } catch (e: Exception) {
                    Log.w(TAG, "Unregister error: ${e.message}")
                }
            }
            
            isConnected = false
            currentMac = null
            
            Log.d(TAG, "✓ Bağlantı kesildi")
            result.success(true)
        } catch (e: Exception) {
            Log.e(TAG, "✗ Disconnect error: ${e.message}", e)
            result.error("DISCONNECT_ERROR", "Failed to disconnect: ${e.message}", null)
        }
    }
    
    private fun printRawData(data: ByteArray, result: MethodChannel.Result) {
        try {
            Log.d(TAG, "printRawData başlıyor... Data size: ${data.size}")
            
            if (printerInstance == null) {
                Log.e(TAG, "printerInstance null!")
                result.error("NOT_CONNECTED", "Printer instance is null", null)
                return
            }
            
            if (!printerInstance!!.isConnected) {
                Log.e(TAG, "Yazıcı bağlı değil!")
                result.error("NOT_CONNECTED", "Printer not connected", null)
                return
            }
            
            // SDK örneğindeki gibi ayrı thread'de yazdır
            Thread {
                try {
                    Log.d(TAG, "sendByteData() çağrılıyor...")
                    printerInstance!!.sendByteData(data)
                    
                    Log.d(TAG, "Yazdırma başarılı!")
                    Handler(Looper.getMainLooper()).post {
                        result.success(true)
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "Yazdırma hatası: ${e.message}", e)
                    Handler(Looper.getMainLooper()).post {
                        result.error("PRINT_ERROR", "Failed to print: ${e.message}", null)
                    }
                }
            }.start()
            
        } catch (e: Exception) {
            Log.e(TAG, "printRawData HATASI: ${e.message}", e)
            result.error("PRINT_ERROR", "Failed to print: ${e.message}", null)
        }
    }
    
    private fun testPrint(protocol: String, result: MethodChannel.Result) {
        try {
            Log.d(TAG, "Test print başlıyor... Protokol: $protocol")
            
            if (printerInstance == null) {
                Log.e(TAG, "printerInstance null!")
                result.error("NOT_CONNECTED", "Printer instance is null", null)
                return
            }
            
            if (!printerInstance!!.isConnected) {
                Log.e(TAG, "Yazıcı bağlı değil!")
                result.error("NOT_CONNECTED", "Printer not connected", null)
                return
            }
            
            Log.d(TAG, "Yazıcı bağlı, protokol: $protocol")
            
            // SDK örneğindeki gibi ayrı thread'de yazdır
            Thread {
                try {
                    when (protocol.lowercase()) {
                        "escpos" -> {
                            Log.d(TAG, "ESC/POS protokolü kullanılıyor")
                            printTextDemo()
                            printBarcodeDemo()
                        }
                        "tspl" -> {
                            Log.d(TAG, "TSPL protokolü kullanılıyor")
                            printTestTSPL()
                        }
                        "cpcl" -> {
                            Log.d(TAG, "CPCL protokolü kullanılıyor")
                            printTestCPCL()
                        }
                        "zpl" -> {
                            Log.d(TAG, "ZPL protokolü kullanılıyor")
                            printTestZPL()
                        }
                        else -> {
                            Log.w(TAG, "Bilinmeyen protokol: $protocol, ESC/POS kullanılıyor")
                            printTextDemo()
                            printBarcodeDemo()
                        }
                    }
                    
                    Log.d(TAG, "Test yazdırma başarılı!")
                    Handler(Looper.getMainLooper()).post {
                        result.success(true)
                    }
                    
                } catch (e: Exception) {
                    Log.e(TAG, "Test yazdırma hatası: ${e.message}", e)
                    Handler(Looper.getMainLooper()).post {
                        result.error("PRINT_ERROR", "Failed to print: ${e.message}", null)
                    }
                }
            }.start()
            
        } catch (e: Exception) {
            Log.e(TAG, "Test print HATASI: ${e.message}", e)
            result.error("PRINT_ERROR", "Failed to print test: ${e.message}", null)
        }
    }
    
    /**
     * SDK PrintUtils.printText() metodunun Kotlin versiyonu
     */
    private fun printTextDemo() {
        val printer = printerInstance ?: return
        
        // Initialize printer
        printer.init()
        
        // Header
        printer.printText("=== BLUETOOTH TEST ===\n")
        printer.setPrinter(Command.PRINT_AND_WAKE_PAPER_BY_LINE, 2)
        
        // Left align
        printer.printText("Sol hizalı metin\n")
        printer.setFont(0, 0, 0, 0)
        printer.setPrinter(Command.ALIGN, 0)
        printer.setPrinter(Command.PRINT_AND_WAKE_PAPER_BY_LINE, 2)
        
        // Center align
        printer.setPrinter(Command.ALIGN, 1)
        printer.printText("Orta hizalı metin\n")
        printer.setPrinter(Command.PRINT_AND_WAKE_PAPER_BY_LINE, 2)
        
        // Right align
        printer.setPrinter(Command.ALIGN, 2)
        printer.printText("Sağ hizalı metin\n")
        printer.setPrinter(Command.PRINT_AND_WAKE_PAPER_BY_LINE, 3)
        
        // Bold text
        printer.setPrinter(Command.ALIGN, 0)
        printer.setFont(0, 0, 1, 0)
        printer.printText("Kalın yazı örneği\n")
        printer.setPrinter(Command.PRINT_AND_WAKE_PAPER_BY_LINE, 2)
        
        // Font sizes
        printer.setFont(0, 0, 0, 0)
        printer.printText("Font boyutları:\n")
        printer.setPrinter(Command.PRINT_AND_WAKE_PAPER_BY_LINE, 2)
        
        for (i in 0..3) {
            printer.setFont(i, i, 0, 0)
            printer.printText("${i + 1}x Boyut\n")
        }
        printer.setPrinter(Command.PRINT_AND_WAKE_PAPER_BY_LINE, 2)
        
        // Text styles (SDK PrintUtils pattern)
        printer.setFont(0, 0, 0, 0)
        printer.printText("Metin stilleri:\n")
        printer.setPrinter(Command.PRINT_AND_WAKE_PAPER_BY_LINE, 1)
        
        printer.setPrintModel(true, false, false, false)
        printer.printText("Kalın\n")
        
        printer.setPrintModel(true, true, false, false)
        printer.printText("Kalın + Yüksek\n")
        
        printer.setPrintModel(true, false, true, false)
        printer.printText("Kalın + Geniş\n")
        
        printer.setPrintModel(false, false, false, true)
        printer.printText("Altı çizili\n")
        
        printer.setFont(0, 0, 0, 0)
        printer.setPrinter(Command.ALIGN, 0)
        printer.setPrinter(Command.PRINT_AND_WAKE_PAPER_BY_LINE, 3)
    }
    
    /**
     * SDK PrintUtils.printBarcode() metodunun Kotlin versiyonu
     */
    private fun printBarcodeDemo() {
        val printer = printerInstance ?: return
        
        printer.printText("BARKOD ÖRNEKLERİ:\n")
        printer.setPrinter(Command.PRINT_AND_WAKE_PAPER_BY_LINE, 2)
        
        // CODE128 (En yaygın)
        printer.printText("CODE128:\n")
        printer.setPrinter(Command.PRINT_AND_WAKE_PAPER_BY_LINE, 1)
        val barcode1 = Barcode(PrinterConstants.BarcodeType.CODE128, 2, 150, 2, "123456789")
        printer.printBarCode(barcode1)
        printer.setPrinter(Command.PRINT_AND_WAKE_PAPER_BY_LINE, 2)
        
        // CODE39
        printer.printText("CODE39:\n")
        printer.setPrinter(Command.PRINT_AND_WAKE_PAPER_BY_LINE, 1)
        val barcode2 = Barcode(PrinterConstants.BarcodeType.CODE39, 2, 150, 2, "123456")
        printer.printBarCode(barcode2)
        printer.setPrinter(Command.PRINT_AND_WAKE_PAPER_BY_LINE, 2)
        
        // Info footer
        printer.printText("--------------------------------\n")
        printer.printText("Protokol: ESC/POS\n")
        printer.printText("Zaman: ${SimpleDateFormat("HH:mm:ss", Locale.getDefault()).format(Date())}\n")
        printer.printText("Durum: OK\n")
        printer.printText("--------------------------------\n")
        printer.setPrinter(Command.PRINT_AND_WAKE_PAPER_BY_LINE, 5)
    }
    
    /**
     * TSPL Protokolü Test Yazdırma (TSC Etiket Yazıcılar)
     */
    private fun printTestTSPL() {
        val printer = printerInstance ?: return
        
        val tspl = StringBuilder()
        
        // Sayfa ayarları
        tspl.append("SIZE 80 mm, 50 mm\n")
        tspl.append("GAP 3 mm, 0 mm\n")
        tspl.append("DIRECTION 0\n")
        tspl.append("REFERENCE 0, 0\n")
        tspl.append("OFFSET 0 mm\n")
        tspl.append("SET PEEL OFF\n")
        tspl.append("SET CUTTER OFF\n")
        tspl.append("SET PARTIAL_CUTTER OFF\n")
        tspl.append("SET TEAR ON\n")
        tspl.append("CLS\n")
        
        // Başlık
        tspl.append("TEXT 100, 50, \"4\", 0, 1, 1, \"TSPL TEST\"\n")
        
        // Ayırıcı çizgi
        tspl.append("BAR 50, 120, 550, 2\n")
        
        // İçerik
        tspl.append("TEXT 50, 150, \"3\", 0, 1, 1, \"Protokol: TSPL\"\n")
        tspl.append("TEXT 50, 200, \"3\", 0, 1, 1, \"Etiket Yazici\"\n")
        tspl.append("TEXT 50, 250, \"3\", 0, 1, 1, \"Zaman: ${SimpleDateFormat("HH:mm:ss", Locale.getDefault()).format(Date())}\"\n")
        
        // Barkod
        tspl.append("BARCODE 100, 320, \"128\", 60, 1, 0, 2, 2, \"123456789\"\n")
        
        // Yazdır
        tspl.append("PRINT 1\n")
        
        printer.sendByteData(tspl.toString().toByteArray())
        Thread.sleep(1500)
    }
    
    /**
     * CPCL Protokolü Test Yazdırma (Zebra Yazıcılar)
     */
    private fun printTestCPCL() {
        val printer = printerInstance ?: return
        
        val cpcl = StringBuilder()
        
        // Sayfa ayarları: ! offset dpi dpi height qty
        cpcl.append("! 0 200 200 400 1\n")
        
        // Başlık (Büyük font)
        cpcl.append("TEXT 7 0 50 40 CPCL TEST\n")
        
        // Ayırıcı çizgi
        cpcl.append("LINE 30 100 570 100 2\n")
        
        // İçerik
        cpcl.append("TEXT 4 0 30 130 Protokol: CPCL\n")
        cpcl.append("TEXT 4 0 30 170 Etiket Yazici\n")
        cpcl.append("TEXT 4 0 30 210 Zaman: ${SimpleDateFormat("HH:mm:ss", Locale.getDefault()).format(Date())}\n")
        
        // Barkod (CODE128)
        cpcl.append("BARCODE 128 1 1 60 30 280 123456789\n")
        
        // Çerçeve
        cpcl.append("BOX 20 20 580 380 2\n")
        
        // Yazdır
        cpcl.append("FORM\n")
        cpcl.append("PRINT\n")
        
        printer.sendByteData(cpcl.toString().toByteArray())
        Thread.sleep(1500)
    }
    
    /**
     * ZPL Protokolü Test Yazdırma (Zebra Etiket Yazıcılar)
     */
    private fun printTestZPL() {
        val printer = printerInstance ?: return
        
        val zpl = StringBuilder()
        
        // ZPL başlangıç
        zpl.append("^XA\n")
        
        // Başlık
        zpl.append("^FO50,50^A0N,60,60^FDZPL TEST^FS\n")
        
        // Ayırıcı çizgi
        zpl.append("^FO50,130^GB500,3,3^FS\n")
        
        // İçerik
        zpl.append("^FO50,160^A0N,40,40^FDProtokol: ZPL^FS\n")
        zpl.append("^FO50,210^A0N,40,40^FDEtiket Yazici^FS\n")
        zpl.append("^FO50,260^A0N,40,40^FDZaman: ${SimpleDateFormat("HH:mm:ss", Locale.getDefault()).format(Date())}^FS\n")
        
        // Barkod (CODE128)
        zpl.append("^FO100,330^BCN,80,Y,N,N^FD123456789^FS\n")
        
        // Çerçeve
        zpl.append("^FO30,30^GB540,450,3^FS\n")
        
        // ZPL bitiş
        zpl.append("^XZ\n")
        
        printer.sendByteData(zpl.toString().toByteArray())
        Thread.sleep(1500)
    }
    
    private fun getPrinterInfo(result: MethodChannel.Result) {
        try {
            val info = mutableMapOf<String, Any>()
            info["model"] = "Bluetooth Printer"
            info["isConnected"] = isConnected
            
            result.success(info)
        } catch (e: Exception) {
            result.error("INFO_ERROR", "Failed to get printer info: ${e.message}", null)
        }
    }
}
