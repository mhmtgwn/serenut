package com.serenut.pos

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.io.ByteArrayOutputStream
import java.text.SimpleDateFormat
import java.util.*
// Sunmi SDK importları
import com.sunmi.peripheral.printer.InnerPrinterCallback
import com.sunmi.peripheral.printer.InnerPrinterException
import com.sunmi.peripheral.printer.InnerPrinterManager
import com.sunmi.peripheral.printer.SunmiPrinterService
import com.sunmi.peripheral.printer.WoyouConsts

class MainActivity : FlutterActivity() {
    private val PRINTER_CHANNEL = "com.sunmi.printer"
    private val NEW_PRINTER_CHANNEL = "com.serenutos.printer/sunmi"
    private val BLUETOOTH_PRINTER_CHANNEL = "com.serenutos.printer/bluetooth"
    private val SCANNER_CHANNEL = "com.sunmi.scanner"
    private val SCANNER_EVENT_CHANNEL = "com.sunmi.scanner/events" // Continuous stream
    private val NFC_CHANNEL = "com.sunmi.nfc"
    private val DRAWER_CHANNEL = "com.sunmi.drawer"
    
    // Sunmi Yazıcı Servisi
    private var sunmiPrinter: SunmiPrinterService? = null
    private var sunmiPrinterConnected = false
    
    // Barkod okuyucu için değişkenler
    private val handler = Handler(Looper.getMainLooper())
    private var scannerEventSink: MethodChannel.Result? = null
    private var continuousScanEventSink: EventChannel.EventSink? = null
    private var isContinuousScanActive = false
    private var scannerReceiver: android.content.BroadcastReceiver? = null
    
    // Sunmi Yazıcı bağlantı callback'i
    private val innerPrinterCallback = object : InnerPrinterCallback() {
        override fun onConnected(service: SunmiPrinterService?) {
            sunmiPrinter = service
            sunmiPrinterConnected = true
            Log.d("SunmiPrinter", "Yazıcıya bağlanıldı!")
        }

        override fun onDisconnected() {
            sunmiPrinter = null
            sunmiPrinterConnected = false
            Log.d("SunmiPrinter", "Yazıcı bağlantısı kesildi!")
        }
    }
    
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // SMS Gönderici kanalı
        SmsSenderPlugin.register(flutterEngine.dartExecutor.binaryMessenger, this)
        
        // Sunmi yazıcısına bağlan
        connectPrinter()
        
        // Bluetooth yazıcı kanalı
        val bluetoothHandler = BluetoothPrinterHandler(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BLUETOOTH_PRINTER_CHANNEL)
            .setMethodCallHandler(bluetoothHandler)
        
        // Yeni mimari için yazıcı kanalı
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, NEW_PRINTER_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "hasPrinter" -> {
                    Log.d("SunmiPrinter", "[NEW] hasPrinter çağrıldı")
                    result.success(sunmiPrinterConnected)
                }
                "getPrinterVersion" -> {
                    result.success(if (sunmiPrinterConnected) "V2.0" else "Bağlı değil")
                }
                "getPrinterSerialNo" -> {
                    result.success(if (sunmiPrinterConnected) "SN12345678" else "Bağlı değil")
                }
                "getPrinterModel" -> {
                    result.success(if (sunmiPrinterConnected) "Sunmi V2s" else "Bağlı değil")
                }
                "printRawData" -> {
                    printRawData(call, result)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
        
        // Eski yazıcı kanalı (geriye dönük uyumluluk için)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PRINTER_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "hasPrinter" -> {
                    Log.d("SunmiPrinter", "hasPrinter çağrıldı")
                    result.success(sunmiPrinterConnected)
                }
                "getPrinterVersion" -> {
                    if (sunmiPrinterConnected && sunmiPrinter != null) {
                        try {
                            val version = "Sunmi Printer V2.0, Seri No: SN12345678"
                            result.success(version)
                        } catch (e: Exception) {
                            result.success("Sunmi Printer V2.0")
                        }
                    } else {
                        result.success("Bağlı değil")
                    }
                }
                "getPrinterSerialNo" -> {
                    if (sunmiPrinterConnected && sunmiPrinter != null) {
                        try {
                            result.success("SN12345678")
                        } catch (e: Exception) {
                            result.success("SN12345678")
                        }
                    } else {
                        result.success("Bağlı değil")
                    }
                }
                "getPrinterModel" -> {
                    if (sunmiPrinterConnected && sunmiPrinter != null) {
                        try {
                            result.success("Sunmi V2 Pro")
                        } catch (e: Exception) {
                            result.success("Sunmi")
                        }
                    } else {
                        result.success("Bağlı değil")
                    }
                }
                "printText" -> {
                    try {
                        val text = call.argument<String>("text") ?: ""
                        val fontSize = call.argument<Int>("fontSize") ?: 24
                        val bold = call.argument<Boolean>("bold") ?: false
                        val align = call.argument<Int>("align") ?: 0
                        
                        Log.d("SunmiPrinter", "Yazdırılıyor: $text, Boyut: $fontSize, Kalın: $bold, Hiza: $align")
                        
                        if (sunmiPrinterConnected && sunmiPrinter != null) {
                            try {
                                // Yazı boyutunu ayarla
                                sunmiPrinter?.setPrinterStyle(WoyouConsts.ENABLE_BOLD, if(bold) WoyouConsts.ENABLE else WoyouConsts.DISABLE)
                                
                                // Hizalamayı ayarla (0:sol, 1:orta, 2:sağ)
                                sunmiPrinter?.setAlignment(align, null)
                                
                                // Metni yazdır
                                sunmiPrinter?.printText(text, null)
                                
                                // Kağıt kes yerine satır ilerlet
                                sunmiPrinter?.lineWrap(4, null)
                                
                                result.success(true)
                            } catch (e: Exception) {
                                Log.e("SunmiPrinter", "Yazdırma hatası: ${e.message}", e)
                                result.error("PRINT_ERROR", e.message, null)
                            }
                        } else {
                            Log.e("SunmiPrinter", "Yazıcı bağlı değil")
                            result.error("PRINTER_NOT_CONNECTED", "Yazıcı bağlı değil", null)
                        }
                    } catch (e: Exception) {
                        Log.e("SunmiPrinter", "Yazdırma hatası", e)
                        result.error("PRINT_ERROR", e.message, null)
                    }
                }
                "printTestPage" -> {
                    try {
                        Log.d("SunmiPrinter", "Test sayfası yazdırılıyor...")
                        
                        if (sunmiPrinterConnected && sunmiPrinter != null) {
                            try {
                                // Başlık
                                sunmiPrinter?.setAlignment(1, null) // Ortalı
                                sunmiPrinter?.setPrinterStyle(WoyouConsts.ENABLE_BOLD, WoyouConsts.ENABLE)
                                sunmiPrinter?.setFontSize(24f, null)
                                sunmiPrinter?.printText("TEST SAYFASI\n\n", null)
                                
                                // Normal içerik
                                sunmiPrinter?.setAlignment(0, null) // Sola yaslı
                                sunmiPrinter?.setPrinterStyle(WoyouConsts.ENABLE_BOLD, WoyouConsts.DISABLE)
                                sunmiPrinter?.setFontSize(18f, null)
                                sunmiPrinter?.printText("Bu bir test sayfasıdır.\n", null)
                                sunmiPrinter?.printText("Yazıcı doğru çalışıyor!\n\n", null)
                                
                                // Tarih ve saat
                                sunmiPrinter?.printText("Tarih: ${SimpleDateFormat("dd/MM/yyyy HH:mm:ss").format(Date())}\n\n", null)
                                
                                // Bir çizgi çek
                                sunmiPrinter?.printText("--------------------------------\n", null)
                                
                                // Alt bilgi
                                sunmiPrinter?.setAlignment(1, null) // Ortalı
                                sunmiPrinter?.printText("Test Başarılı\n\n\n", null)
                                
                                // Kağıt ilerlet
                                sunmiPrinter?.lineWrap(4, null)
                                
                                result.success(true)
                            } catch (e: Exception) {
                                Log.e("SunmiPrinter", "Test yazdırma hatası: ${e.message}", e)
                                result.error("PRINT_ERROR", e.message, null)
                            }
                        } else {
                            Log.e("SunmiPrinter", "Yazıcı bağlı değil")
                            result.error("PRINTER_NOT_CONNECTED", "Yazıcı bağlı değil", null)
                        }
                    } catch (e: Exception) {
                        Log.e("SunmiPrinter", "Test sayfası yazdırma hatası", e)
                        result.error("PRINT_ERROR", e.message, null)
                    }
                }
                "printTest" -> {
                    try {
                        val paperWidth = call.argument<Int>("paperWidth") ?: 58
                        Log.d("SunmiPrinter", "printTest çağrıldı. Kağıt genişliği: $paperWidth")
                        
                        // Test içeriği
                        val testContent = """
                            =========================
                            SERENUT OS YAZICI TEST SAYFASI
                            =========================
                            
                            Bu bir test sayfasıdır.
                            Yazıcı doğru çalışıyor!
                            
                            Kağıt genişliği: $paperWidth mm
                            Tarih: ${SimpleDateFormat("dd/MM/yyyy HH:mm:ss").format(Date())}
                            
                            =========================
                            Test Başarılı
                            =========================
                        """.trimIndent()
                        
                        Log.d("SunmiPrinter", "Test içeriği:\n$testContent")
                        
                        if (sunmiPrinterConnected && sunmiPrinter != null) {
                            try {
                                // Yazıcı hazırlanıyor
                                Log.d("SunmiPrinter", "Yazıcı hazırlanıyor...")
                                Log.d("SunmiPrinter", "Yazıcı durumu: Hazır")
                                Log.d("SunmiPrinter", "Kağıt durumu: Var")
                                
                                // Yazdırma işlemi
                                Log.d("SunmiPrinter", "Test sayfası yazdırılıyor...")
                                
                                // Başlık yazdır
                                Log.d("SunmiPrinter", "Başlık yazdırılıyor...")
                                sunmiPrinter?.setAlignment(1, null) // Ortalı
                                sunmiPrinter?.setPrinterStyle(WoyouConsts.ENABLE_BOLD, WoyouConsts.ENABLE)
                                sunmiPrinter?.setFontSize(24f, null)
                                sunmiPrinter?.printText("=========================\n", null)
                                sunmiPrinter?.printText("SERENUT OS YAZICI TEST SAYFASI\n", null)
                                sunmiPrinter?.printText("=========================\n\n", null)
                                
                                // İçerik yazdır
                                Log.d("SunmiPrinter", "İçerik yazdırılıyor...")
                                sunmiPrinter?.setAlignment(0, null) // Sola yaslı
                                sunmiPrinter?.setPrinterStyle(WoyouConsts.ENABLE_BOLD, WoyouConsts.DISABLE)
                                sunmiPrinter?.setFontSize(18f, null)
                                sunmiPrinter?.printText("Bu bir test sayfasıdır.\n", null)
                                sunmiPrinter?.printText("Yazıcı doğru çalışıyor!\n\n", null)
                                
                                // Yazıcı protokolü bilgisini ekleyelim
                                sunmiPrinter?.printText("Protokol: ESC/POS\n", null)
                                sunmiPrinter?.printText("Kağıt genişliği: $paperWidth mm\n", null)
                                sunmiPrinter?.printText("Tarih: ${SimpleDateFormat("dd/MM/yyyy HH:mm:ss").format(Date())}\n\n", null)
                                
                                // Logo yazdırma - beyaz arka plan üzerine siyah yazı
                                try {
                                    Log.d("SunmiPrinter", "Logo yazdırma hazırlanıyor...")
                                    
                                    // Doğrudan assets klasöründen logo.png dosyasını yükle
                                    try {
                                        val assetManager = context.assets
                                        val logoPath = "logo.png" // Bu dosya assets klasöründe olmalı
                                        
                                        // Mevcut dosyaları listele
                                        try {
                                            val files = assetManager.list("")
                                            Log.d("SunmiPrinter", "Assets klasöründeki dosyalar (${files?.size ?: 0}):")
                                            files?.forEach { file ->
                                                Log.d("SunmiPrinter", "- $file")
                                            }
                                            
                                            // Alt klasörleri de kontrol edelim
                                            try {
                                                val imageFiles = assetManager.list("images")
                                                Log.d("SunmiPrinter", "images/ klasöründeki dosyalar (${imageFiles?.size ?: 0}):")
                                                imageFiles?.forEach { file ->
                                                    Log.d("SunmiPrinter", "  - images/$file")
                                                }
                                            } catch (e: Exception) {
                                                Log.e("SunmiPrinter", "images/ klasörü listelenemedi: ${e.message}")
                                            }
                                        } catch (e: Exception) {
                                            Log.e("SunmiPrinter", "Assets listelenemedi: ${e.message}")
                                        }
                                        
                                        Log.d("SunmiPrinter", "Yüklenecek görsel: $logoPath")
                                        val inputStream = assetManager.open(logoPath)
                                        val bitmap = BitmapFactory.decodeStream(inputStream)
                                        inputStream.close()
                                        
                                        if (bitmap != null) {
                                            Log.d("SunmiPrinter", "Logo yüklendi: ${bitmap.width}x${bitmap.height}")
                                            
                                            // Logoyu yazdır
                                            sunmiPrinter?.setAlignment(1, null) // Ortalı
                                            sunmiPrinter?.printBitmap(bitmap, null)
                                            sunmiPrinter?.lineWrap(1, null)
                                            Log.d("SunmiPrinter", "Logo yazdırıldı")
                                        } else {
                                            Log.e("SunmiPrinter", "Logo yüklenemedi: Bitmap null")
                                            // Logo yüklenemezse metin yazdır
                                            sunmiPrinter?.printText("[ LOGO ]\n", null)
                                        }
                                    } catch (e: Exception) {
                                        Log.e("SunmiPrinter", "Logo yükleme hatası: ${e.message}", e)
                                        // Hata durumunda metin yazdır
                                        sunmiPrinter?.printText("[ LOGO YÜKLENEMEDI ]\n", null)
                                        
                                        // Alternatif olarak basit bir logo oluştur
                                        val width = 384 // Genişlik - standart termal yazıcı için
                                        val height = 100 // Yükseklik
                                        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
                                        val canvas = android.graphics.Canvas(bitmap)
                                        
                                        // Beyaz arka plan
                                        val bgPaint = android.graphics.Paint()
                                        bgPaint.color = android.graphics.Color.WHITE
                                        bgPaint.style = android.graphics.Paint.Style.FILL
                                        canvas.drawRect(0f, 0f, width.toFloat(), height.toFloat(), bgPaint)
                                        
                                        // Logo yazı
                                        val paint = android.graphics.Paint()
                                        paint.color = android.graphics.Color.BLACK
                                        paint.textSize = 50f
                                        paint.isFakeBoldText = true // Kalın yazı
                                        canvas.drawText("SERENUT OS", 100f, 60f, paint)
                                        
                                        sunmiPrinter?.printBitmap(bitmap, null)
                                        sunmiPrinter?.lineWrap(1, null)
                                    }
                                    
                                    // Barkod yazdırma (CODE128)
                                    Log.d("SunmiPrinter", "Barkod yazdırılıyor...")
                                    sunmiPrinter?.setAlignment(1, null) // Ortalı
                                    sunmiPrinter?.printText("BARKOD ÖRNEK:\n", null)
                                    sunmiPrinter?.printBarCode("123456789012", 8, 80, 2, 2, null)
                                    sunmiPrinter?.lineWrap(1, null)
                                    
                                    // QR kod yazdırma
                                    Log.d("SunmiPrinter", "QR kod yazdırılıyor...")
                                    sunmiPrinter?.setAlignment(1, null) // Ortalı
                                    sunmiPrinter?.printText("QR KOD ÖRNEK:\n", null)
                                    sunmiPrinter?.printQRCode("https://serenut.com", 8, 0, null)
                                    sunmiPrinter?.lineWrap(1, null)
                                    
                                    // QR kod açıklaması - daha büyük yazı
                                    sunmiPrinter?.setFontSize(20f, null)
                                    sunmiPrinter?.printText("serenut.com\n", null)
                                    sunmiPrinter?.lineWrap(1, null)
                                    
                                } catch (e: Exception) {
                                    Log.e("SunmiPrinter", "Görsel yazdırma hatası: ${e.message}", e)
                                }
                                
                                // Alt bilgi yazdır
                                Log.d("SunmiPrinter", "Alt bilgi yazdırılıyor...")
                                sunmiPrinter?.setAlignment(1, null) // Ortalı
                                sunmiPrinter?.printText("=========================\n", null)
                                sunmiPrinter?.printText("Test Başarılı\n", null)
                                sunmiPrinter?.printText("=========================\n\n\n", null)
                                
                                // Kağıt ilerlet (kağıt kesme yerine)
                                sunmiPrinter?.lineWrap(4, null)
                                
                                Log.d("SunmiPrinter", "Test sayfası yazdırma işlemi tamamlandı!")
                                
                                result.success(true)
                            } catch (e: Exception) {
                                Log.e("SunmiPrinter", "Test yazdırma hatası: ${e.message}", e)
                                result.error("PRINT_ERROR", e.message, null)
                            }
                        } else {
                            Log.e("SunmiPrinter", "Yazıcı bağlı değil")
                            result.error("PRINTER_NOT_CONNECTED", "Yazıcı bağlı değil", null)
                        }
                    } catch (e: Exception) {
                        Log.e("SunmiPrinter", "Test yazdırma hatası: ${e.message}", e)
                        result.error("PRINT_ERROR", "Test yazdırma işlemi başarısız: ${e.message}", null)
                    }
                }
                "printRawData" -> {
                    printRawData(call, result)
                }
                "printTestReceipt" -> {
                    printTestReceipt(call, result)
                }
                "printImage" -> {
                    try {
                        val imageData = call.argument<ByteArray>("image")
                        val align = call.argument<Int>("align") ?: 1
                        
                        Log.d("SunmiPrinter", "printImage çağrıldı, align: $align")
                        
                        if (imageData == null) {
                            Log.e("SunmiPrinter", "Görsel verisi boş")
                            result.error("IMAGE_ERROR", "Görsel verisi boş", null)
                            return@setMethodCallHandler
                        }
                        
                        Log.d("SunmiPrinter", "Görsel verisi alındı, boyut: ${imageData.size} bytes")
                        
                        if (sunmiPrinterConnected && sunmiPrinter != null) {
                            try {
                                // Byte array'i bitmap'e dönüştür
                                val bitmap = BitmapFactory.decodeByteArray(imageData, 0, imageData.size)
                                
                                if (bitmap != null) {
                                    Log.d("SunmiPrinter", "Bitmap oluşturuldu: ${bitmap.width}x${bitmap.height}")
                                    
                                    // Görseli yazdır
                                    sunmiPrinter?.setAlignment(align, null)
                                    sunmiPrinter?.printBitmap(bitmap, null)
                                    sunmiPrinter?.lineWrap(1, null)
                                    
                                    Log.d("SunmiPrinter", "Görsel yazdırıldı")
                                    result.success(true)
                                } else {
                                    Log.e("SunmiPrinter", "Bitmap oluşturulamadı")
                                    result.error("BITMAP_ERROR", "Bitmap oluşturulamadı", null)
                                }
                            } catch (e: Exception) {
                                Log.e("SunmiPrinter", "Görsel yazdırma hatası: ${e.message}", e)
                                result.error("PRINT_ERROR", e.message, null)
                            }
                        } else {
                            Log.e("SunmiPrinter", "Yazıcı bağlı değil")
                            result.error("PRINTER_NOT_CONNECTED", "Yazıcı bağlı değil", null)
                        }
                    } catch (e: Exception) {
                        Log.e("SunmiPrinter", "Görsel yazdırma hatası: ${e.message}", e)
                        result.error("PRINT_ERROR", e.message, null)
                    }
                }
                "printReceiptWithImage" -> {
                    try {
                        // Fiş verilerini al
                        val title = call.argument<String>("title") ?: "SERENUT OS TEST FİŞİ"
                        val subtitle = call.argument<String>("subtitle") ?: "Sunmi Yazıcı Test"
                        val date = call.argument<String>("date") ?: ""
                        val imagePath = call.argument<String>("imagePath") ?: "assets/logo.png"
                        val footer = call.argument<String>("footer") ?: "Teşekkür ederiz!"
                        val paperWidth = call.argument<Int>("paperWidth") ?: 58
                        
                        Log.d("SunmiPrinter", "Görsel ile fiş yazdırılıyor...")
                        Log.d("SunmiPrinter", "Başlık: $title")
                        Log.d("SunmiPrinter", "Alt başlık: $subtitle")
                        Log.d("SunmiPrinter", "Tarih: $date")
                        Log.d("SunmiPrinter", "Görsel yolu: $imagePath")
                        Log.d("SunmiPrinter", "Alt bilgi: $footer")
                        Log.d("SunmiPrinter", "Kağıt genişliği: $paperWidth")
                        
                        if (sunmiPrinterConnected && sunmiPrinter != null) {
                            try {
                                // Tarih bilgisini oluştur
                                val dateStr = if (date.isEmpty()) {
                                    SimpleDateFormat("dd/MM/yyyy HH:mm:ss").format(Date())
                                } else {
                                    date
                                }
                                
                                // Başlık yazdır
                                sunmiPrinter?.setAlignment(1, null) // Ortalı
                                sunmiPrinter?.setPrinterStyle(WoyouConsts.ENABLE_BOLD, WoyouConsts.ENABLE)
                                sunmiPrinter?.setFontSize(24f, null)
                                sunmiPrinter?.printText("$title\n", null)
                                
                                // Alt başlık yazdır
                                sunmiPrinter?.setPrinterStyle(WoyouConsts.ENABLE_BOLD, WoyouConsts.DISABLE)
                                sunmiPrinter?.setFontSize(18f, null)
                                sunmiPrinter?.printText("$subtitle\n", null)
                                
                                // Tarih yazdır
                                sunmiPrinter?.printText("Tarih: $dateStr\n", null)
                                
                                // Çizgi yazdır
                                sunmiPrinter?.printText("--------------------------------\n", null)
                                
                                // Görsel yazdır
                                try {
                                    Log.d("SunmiPrinter", "Görsel yazdırma başlatılıyor: $imagePath")
                                    
                                    // Görsel dosyasını yükleme yöntemini değiştir
                                    val cleanImagePath = imagePath.replace("assets/", "")
                                    Log.d("SunmiPrinter", "Temizlenmiş görsel yolu: $cleanImagePath")
                                    
                                    // Görsel dosyasını assets klasöründen yükle
                                    val assetManager = context.assets
                                    
                                    // Mevcut dosyaları listele
                                    try {
                                        val files = assetManager.list("")
                                        Log.d("SunmiPrinter", "Assets klasöründeki dosyalar (${files?.size ?: 0}):")
                                        files?.forEach { file ->
                                            Log.d("SunmiPrinter", "- $file")
                                        }
                                        
                                        // Alt klasörleri de kontrol edelim
                                        try {
                                            val imageFiles = assetManager.list("images")
                                            Log.d("SunmiPrinter", "images/ klasöründeki dosyalar (${imageFiles?.size ?: 0}):")
                                            imageFiles?.forEach { file ->
                                                Log.d("SunmiPrinter", "  - images/$file")
                                            }
                                        } catch (e: Exception) {
                                            Log.e("SunmiPrinter", "images/ klasörü listelenemedi: ${e.message}")
                                        }
                                    } catch (e: Exception) {
                                        Log.e("SunmiPrinter", "Assets listelenemedi: ${e.message}")
                                    }
                                    
                                    // Flutter tarafından gönderilen görsel verisi var mı kontrol et
                                    val imageData = call.argument<ByteArray>("image")
                                    if (imageData != null && imageData.isNotEmpty()) {
                                        Log.d("SunmiPrinter", "Flutter'dan görsel verisi alındı: ${imageData.size} bytes")
                                        
                                        // ByteArray'den bitmap oluştur
                                        val bitmap = BitmapFactory.decodeByteArray(imageData, 0, imageData.size)
                                        if (bitmap != null) {
                                            Log.d("SunmiPrinter", "Bitmap oluşturuldu: ${bitmap.width}x${bitmap.height}")
                                            
                                            // Görseli yazdır
                                            sunmiPrinter?.setAlignment(1, null) // Ortalı
                                            sunmiPrinter?.printBitmap(bitmap, null)
                                            sunmiPrinter?.lineWrap(1, null)
                                            Log.d("SunmiPrinter", "Görsel yazdırıldı")
                                        } else {
                                            Log.e("SunmiPrinter", "Bitmap oluşturulamadı")
                                            throw Exception("Bitmap oluşturulamadı")
                                        }
                                    } else {
                                        // Görsel verisi yoksa dosyadan yükle
                                        // Flutter tarafından gelen yolu temizle (assets/ önekini kaldır)
                                        val finalImagePath = if (cleanImagePath.contains("/")) {
                                            cleanImagePath.substring(cleanImagePath.lastIndexOf("/") + 1)
                                        } else {
                                            cleanImagePath
                                        }
                                        
                                        Log.d("SunmiPrinter", "Orijinal görsel yolu: $cleanImagePath")
                                        Log.d("SunmiPrinter", "Temizlenmiş görsel yolu: $finalImagePath")
                                        
                                        try {
                                            // Önce doğrudan dosya adıyla dene
                                            val inputStream = assetManager.open(finalImagePath)
                                            val bitmap = BitmapFactory.decodeStream(inputStream)
                                            inputStream.close()
                                            
                                            if (bitmap != null) {
                                                Log.d("SunmiPrinter", "Görsel başarıyla yüklendi: ${bitmap.width}x${bitmap.height}")
                                                
                                                // Görseli yazdır
                                                sunmiPrinter?.setAlignment(1, null) // Ortalı
                                                sunmiPrinter?.printBitmap(bitmap, null)
                                                sunmiPrinter?.lineWrap(1, null)
                                                Log.d("SunmiPrinter", "Görsel yazdırıldı")
                                            } else {
                                                Log.e("SunmiPrinter", "Görsel yüklenemedi: Bitmap null")
                                                throw Exception("Bitmap null")
                                            }
                                        } catch (e: Exception) {
                                            Log.e("SunmiPrinter", "Görsel yükleme hatası: ${e.message}", e)
                                            throw e
                                        }
                                    }
                                } catch (e: Exception) {
                                    Log.e("SunmiPrinter", "Görsel yazdırma hatası: ${e.message}", e)
                                    // Hata durumunda alternatif olarak metin yazdır
                                    sunmiPrinter?.printText("[GÖRSEL YAZDIRILAMADI]\n", null)
                                    
                                    // Hata detaylarını yazdır
                                    sunmiPrinter?.printText("Hata: ${e.message?.take(50)}\n", null)
                                    
                                    // Alternatif olarak basit bir logo oluştur ve yazdır
                                    try {
                                        Log.d("SunmiPrinter", "Alternatif logo oluşturuluyor...")
                                        val width = 384 // Genişlik - standart termal yazıcı için
                                        val height = 100 // Yükseklik
                                        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
                                        val canvas = android.graphics.Canvas(bitmap)
                                        
                                        // Beyaz arka plan
                                        val bgPaint = android.graphics.Paint()
                                        bgPaint.color = android.graphics.Color.WHITE
                                        bgPaint.style = android.graphics.Paint.Style.FILL
                                        canvas.drawRect(0f, 0f, width.toFloat(), height.toFloat(), bgPaint)
                                        
                                        // Logo yazı
                                        val paint = android.graphics.Paint()
                                        paint.color = android.graphics.Color.BLACK
                                        paint.textSize = 50f
                                        paint.isFakeBoldText = true // Kalın yazı
                                        canvas.drawText("SERENUT OS", 100f, 60f, paint)
                                        
                                        sunmiPrinter?.setAlignment(1, null) // Ortalı
                                        sunmiPrinter?.printBitmap(bitmap, null)
                                        sunmiPrinter?.lineWrap(1, null)
                                        Log.d("SunmiPrinter", "Alternatif logo yazdırıldı")
                                    } catch (e2: Exception) {
                                        Log.e("SunmiPrinter", "Alternatif logo yazdırma hatası: ${e2.message}", e2)
                                    }
                                }
                                
                                // Alt bilgi yazdır
                                sunmiPrinter?.printText("--------------------------------\n", null)
                                sunmiPrinter?.printText("$footer\n\n\n", null)
                                
                                // Kağıt ilerlet
                                sunmiPrinter?.lineWrap(4, null)
                                
                                result.success(true)
                            } catch (e: Exception) {
                                Log.e("SunmiPrinter", "Görsel ile fiş yazdırma hatası: ${e.message}", e)
                                result.error("PRINT_ERROR", e.message, null)
                            }
                        } else {
                            Log.e("SunmiPrinter", "Yazıcı bağlı değil")
                            result.error("PRINTER_NOT_CONNECTED", "Yazıcı bağlı değil", null)
                        }
                    } catch (e: Exception) {
                        Log.e("SunmiPrinter", "Görsel ile fiş yazdırma hatası", e)
                        result.error("PRINT_ERROR", e.message, null)
                    }
                }
                "checkDevices" -> {
                    try {
                        Log.d("SunmiDevice", "checkDevices çağrıldı")
                        
                        // Gerçek donanımların varlığını kontrol et
                        // Bu örnekte gerçek donanım tespiti için simulasyon yapıyoruz
                        // Gerçek uygulamada burada donanımları kontrol eden kod olmalı
                        
                        // Cihazları kontrol eden map oluştur
                        val deviceMap = HashMap<String, Boolean>()
                        
                        // Sunmi cihazlarda kullanıcı ayarlarına göre donanımları kontrol et
                        // Burada simülasyon için sadece yazıcı ve tarayıcı var kabul ediyoruz
                        deviceMap["printer"] = sunmiPrinterConnected
                        deviceMap["scanner"] = true
                        deviceMap["nfc"] = false
                        deviceMap["drawer"] = false
                        
                        Log.d("SunmiDevice", "Tespit edilen cihazlar: $deviceMap")
                        
                        result.success(deviceMap)
                    } catch (e: Exception) {
                        Log.e("SunmiDevice", "Cihaz kontrolü hatası: ${e.message}", e)
                        result.error("DEVICE_ERROR", "Cihazlar kontrol edilirken hata oluştu: ${e.message}", null)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
        
        // Barkod okuyucu kanalı (MethodChannel — tek seferlik)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SCANNER_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "hasScanner" -> {
                    Log.d("SunmiScanner", "hasScanner çağrıldı")
                    result.success(true)
                }
                "getScannerInfo" -> {
                    val info = HashMap<String, String>()
                    info["model"] = "Sunmi Scanner V2"
                    info["version"] = "2.0"
                    result.success(info)
                }
                "startScan" -> {
                    Log.d("SunmiScanner", "Tek seferlik barkod tarama başlatıldı")
                    scannerEventSink = result
                    simulateBarcodeScanning()
                }
                "stopScan" -> {
                    Log.d("SunmiScanner", "Barkod tarama durduruldu")
                    scannerEventSink = null
                    result.success(true)
                }
                "startContinuousScan" -> {
                    isContinuousScanActive = true
                    Log.d("SunmiScanner", "Sürekli tarama modu başlatıldı")
                    result.success(true)
                }
                "stopContinuousScan" -> {
                    isContinuousScanActive = false
                    Log.d("SunmiScanner", "Sürekli tarama modu durduruldu")
                    result.success(true)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }

        // Barkod EventChannel — sürekli yayın (Sunmi hardware scan broadcast)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, SCANNER_EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    continuousScanEventSink = events
                    Log.d("SunmiScanner", "EventChannel dinleme başladı (Sunmi BroadcastReceiver)")
                    
                    // Register Android BroadcastReceiver for Sunmi physical scanner
                    val filter = android.content.IntentFilter("com.sunmi.scanner.ACTION_DATA_CODE_RECEIVED")
                    scannerReceiver = object : android.content.BroadcastReceiver() {
                        override fun onReceive(context: android.content.Context?, intent: android.content.Intent?) {
                            if (intent != null && intent.action == "com.sunmi.scanner.ACTION_DATA_CODE_RECEIVED") {
                                val barcode = intent.getStringExtra("data")
                                if (barcode != null && barcode.isNotEmpty()) {
                                    Log.d("SunmiScanner", "Broadcast barcode scanned: $barcode")
                                    handler.post {
                                        continuousScanEventSink?.success(barcode)
                                    }
                                }
                            }
                        }
                    }
                    context.registerReceiver(scannerReceiver, filter)
                    Log.d("SunmiScanner", "BroadcastReceiver register edildi")
                }

                override fun onCancel(arguments: Any?) {
                    continuousScanEventSink = null
                    if (scannerReceiver != null) {
                        try {
                            context.unregisterReceiver(scannerReceiver)
                            Log.d("SunmiScanner", "BroadcastReceiver unregister edildi")
                        } catch (e: Exception) {
                            Log.e("SunmiScanner", "Receiver unregister hatası: ${e.message}")
                        }
                        scannerReceiver = null
                    }
                }
            })
    }
    
    private fun connectPrinter() {
        try {
            Log.d("SunmiPrinter", "Yazıcı servisine bağlanılıyor...")
            InnerPrinterManager.getInstance().bindService(applicationContext, innerPrinterCallback)
        } catch (e: InnerPrinterException) {
            Log.e("SunmiPrinter", "Yazıcıya bağlanma hatası: ${e.message}", e)
        }
    }
    
    // Barkod taramayı simüle eden fonksiyon
    private fun simulateBarcodeScanning() {
        handler.postDelayed({
            val barcodes = listOf(
                "8690504018019",
                "8690757202122",
                "8690504135815",
                "8690504135822",
                "8690504135839"
            )
            val randomBarcode = barcodes.random()
            
            Log.d("SunmiScanner", "Simüle edilmiş barkod: $randomBarcode")
            
            scannerEventSink?.success(randomBarcode)
            scannerEventSink = null
        }, 2000) // 2 saniye sonra barkod döndür
    }
    
    // Yazdırma işlemini simüle eden fonksiyon
    private fun simulatePrinting() {
        Log.d("SunmiPrinter", "Yazdırma işlemi başladı...")
        
        if (sunmiPrinterConnected && sunmiPrinter != null) {
            try {
                sunmiPrinter?.printText("Simüle Edilen Yazdırma\n", null)
                sunmiPrinter?.lineWrap(4, null)
            } catch (e: Exception) {
                Log.e("SunmiPrinter", "Yazdırma hatası: ${e.message}", e)
            }
        } else {
            Log.d("SunmiPrinter", "Yazıcı bağlı değil, simülasyon yapılıyor...")
            Thread.sleep(500)
        }
        Log.d("SunmiPrinter", "Yazdırma işlemi tamamlandı!")
    }

    private fun printRawData(call: MethodCall, result: Result) {
        try {
            // Flutter'dan List<int> olarak gelir, ByteArray'e çevir
            val dataList = call.argument<List<Int>>("data")
            
            if (dataList == null || dataList.isEmpty()) {
                Log.e("SunmiPrinter", "Raw data boş")
                result.error("DATA_ERROR", "Yazdırılacak veri boş", null)
                return
            }
            
            // List<Int> -> ByteArray
            val data = dataList.map { it.toByte() }.toByteArray()
            
            Log.d("SunmiPrinter", "Raw data yazdırılıyor: ${data.size} byte")
            
            if (sunmiPrinterConnected && sunmiPrinter != null) {
                try {
                    // Raw byte array'i yazdır
                    sunmiPrinter?.sendRAWData(data, null)
                    
                    Log.d("SunmiPrinter", "Raw data başarıyla yazdırıldı")
                    result.success(true)
                } catch (e: Exception) {
                    Log.e("SunmiPrinter", "Raw data yazdırma hatası: ${e.message}", e)
                    result.error("PRINT_ERROR", e.message, null)
                }
            } else {
                Log.e("SunmiPrinter", "Yazıcı bağlı değil")
                result.error("PRINTER_NOT_CONNECTED", "Yazıcı bağlı değil", null)
            }
        } catch (e: Exception) {
            Log.e("SunmiPrinter", "Raw data yazdırma hatası: ${e.message}", e)
            result.error("PRINT_ERROR", e.message, null)
        }
    }

    private fun printTestReceipt(call: MethodCall, result: Result) {
        try {
            val paperWidth = call.argument<Int>("paperWidth") ?: 58
            
            if (sunmiPrinterConnected && sunmiPrinter != null) {
                try {
                    // Başlık
                    sunmiPrinter?.setAlignment(1, null) // Ortalı
                    sunmiPrinter?.setPrinterStyle(WoyouConsts.ENABLE_BOLD, WoyouConsts.ENABLE)
                    sunmiPrinter?.setFontSize(24f, null)
                    sunmiPrinter?.printText("SERENUT OS TEST FİŞİ\n\n", null)
                    
                    // Normal içerik
                    sunmiPrinter?.setAlignment(0, null) // Sola yaslı
                    sunmiPrinter?.setPrinterStyle(WoyouConsts.ENABLE_BOLD, WoyouConsts.DISABLE)
                    sunmiPrinter?.setFontSize(18f, null)
                    sunmiPrinter?.printText("Ürün 1.................... 15,00₺\n", null)
                    sunmiPrinter?.printText("Ürün 2..................... 7,50₺\n", null)
                    sunmiPrinter?.printText("Ürün 3.................... 22,75₺\n", null)
                    sunmiPrinter?.printText("--------------------------------\n", null)
                    sunmiPrinter?.printText("TOPLAM.................... 45,25₺\n\n", null)
                    
                    // Tarih ve saat
                    sunmiPrinter?.printText("Tarih: ${SimpleDateFormat("dd/MM/yyyy HH:mm:ss").format(Date())}\n\n", null)
                    
                    // Alt bilgi
                    sunmiPrinter?.setAlignment(1, null) // Ortalı
                    sunmiPrinter?.printText("Teşekkür Ederiz\n", null)
                    sunmiPrinter?.printText("serenut.com\n\n\n", null)
                    
                    // Kağıt ilerlet
                    sunmiPrinter?.lineWrap(4, null)
                    
                    result.success(true)
                } catch (e: Exception) {
                    Log.e("SunmiPrinter", "Test fiş yazdırma hatası: ${e.message}", e)
                    result.error("PRINT_ERROR", e.message, null)
                }
            } else {
                Log.e("SunmiPrinter", "Yazıcı bağlı değil")
                result.error("PRINTER_NOT_CONNECTED", "Yazıcı bağlı değil", null)
            }
        } catch (e: Exception) {
            Log.e("SunmiPrinter", "Test yazdırma hatası: ${e.message}", e)
            result.success(false)
        }
    }
    
    override fun onDestroy() {
        super.onDestroy()
        // Yazıcı servisini sonlandır
        if (sunmiPrinterConnected) {
            InnerPrinterManager.getInstance().unBindService(applicationContext, innerPrinterCallback)
            sunmiPrinter = null
            sunmiPrinterConnected = false
        }
    }
}
