import 'package:flutter/foundation.dart';
import 'database_service.dart';

class PrinterService {
  static final PrinterService instance = PrinterService._init();
  final DatabaseService _dbService = DatabaseService.instance;

  PrinterService._init();
  
  /// Fiş yazıcısını atar
  Future<bool> assignReceiptPrinter(String deviceId) async {
    try {
      await _dbService.assignReceiptPrinter(deviceId);
      return true;
    } catch (e) {
      debugPrint('Fiş yazıcısı atanırken hata: $e');
      return false;
    }
  }
  
  /// Etiket yazıcısını atar
  Future<bool> assignLabelPrinter(String deviceId) async {
    try {
      await _dbService.assignLabelPrinter(deviceId);
      return true;
    } catch (e) {
      debugPrint('Etiket yazıcısı atanırken hata: $e');
      return false;
    }
  }
  
  /// Fiş yazıcısını getirir
  Future<Map<String, dynamic>?> getReceiptPrinter() async {
    try {
      return await _dbService.getReceiptPrinter();
    } catch (e) {
      debugPrint('Fiş yazıcısı alınırken hata: $e');
      return null;
    }
  }
  
  /// Etiket yazıcısını getirir
  Future<Map<String, dynamic>?> getLabelPrinter() async {
    try {
      return await _dbService.getLabelPrinter();
    } catch (e) {
      debugPrint('Etiket yazıcısı alınırken hata: $e');
      return null;
    }
  }
  
  /// Tüm yazıcı atamalarını getirir
  Future<Map<String, Map<String, dynamic>?>> getAllPrinterAssignments() async {
    try {
      final receiptPrinter = await _dbService.getReceiptPrinter();
      final labelPrinter = await _dbService.getLabelPrinter();
      
      return {
        'receipt': receiptPrinter,
        'label': labelPrinter,
      };
    } catch (e) {
      debugPrint('Yazıcı atamaları alınırken hata: $e');
      return {
        'receipt': null,
        'label': null,
      };
    }
  }
  
  /// Fiş yazıcısı atamasını kaldırır
  Future<bool> removeReceiptPrinter() async {
    try {
      await _dbService.removeReceiptPrinter();
      return true;
    } catch (e) {
      debugPrint('Fiş yazıcısı kaldırılırken hata: $e');
      return false;
    }
  }
  
  /// Etiket yazıcısı atamasını kaldırır
  Future<bool> removeLabelPrinter() async {
    try {
      await _dbService.removeLabelPrinter();
      return true;
    } catch (e) {
      debugPrint('Etiket yazıcısı kaldırılırken hata: $e');
      return false;
    }
  }
} 