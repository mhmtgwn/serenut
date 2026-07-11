import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:excel/excel.dart' as ex;

void main() async {
  final file = File('market_data_catalog_with_images.zip');
  final bytes = await file.readAsBytes();
  final archive = ZipDecoder().decodeBytes(bytes);

  ArchiveFile? excelFile;
  for (final f in archive) {
    if (f.name == 'market_data_catalog.xlsx') {
      excelFile = f;
      break;
    }
  }

  if (excelFile == null) {
    print('Excel not found');
    return;
  }

  final excelBytes = excelFile.content as List<int>;
  
  // Fix excel relations in-memory
  final innerArchive = ZipDecoder().decodeBytes(excelBytes);
  final newInnerArchive = Archive();

  for (final file in innerArchive) {
    if (file.name == 'xl/_rels/workbook.xml.rels') {
      var content = String.fromCharCodes(file.content as List<int>);
      final fixedContent = content.replaceAll('Target="/xl/', 'Target="');
      final fixedBytes = Uint8List.fromList(fixedContent.codeUnits);
      newInnerArchive.addFile(ArchiveFile(file.name, fixedBytes.length, fixedBytes));
    } else {
      newInnerArchive.addFile(file);
    }
  }

  final zipEncoder = ZipEncoder();
  final encoded = zipEncoder.encode(newInnerArchive);

  final excel = ex.Excel.decodeBytes(Uint8List.fromList(encoded!));
  final sheetName = excel.tables.keys.first;
  final sheet = excel.tables[sheetName]!;

  print('Header columns in sheet:');
  final headerRow = sheet.rows[0];
  for (int j = 0; j < headerRow.length; j++) {
    final cell = headerRow[j];
    print('  Column $j: ${cell?.value}');
  }
}
