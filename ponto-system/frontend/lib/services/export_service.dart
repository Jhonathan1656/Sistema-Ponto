import 'dart:convert';
import 'dart:io';

import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart' show Uint8List, kIsWeb;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class ExportService {
  static String get backendUrl =>
      kIsWeb ? '${Uri.base.origin}/api' : 'http://localhost:8000';

  Future<void> exportToExcel({
    required Map<String, dynamic> data,
    required String month,
    required String year,
    required bool isCampo,
  }) async {
    try {
      final body = json.encode({
        'employee_name': data['employee']['name'],
        'employee_role': data['employee']['role'],
        'month': month,
        'year': year,
        'is_campo': isCampo,
        'daily_records': data['daily_records'],
        'custom_role': data['custom_role'],
        'custom_department': data['custom_department'],
        'custom_work_hours': data['custom_work_hours'],
        'generate_from_scratch': data['generate_from_scratch'],
        'target_hours': data['target_hours'],
        'holidays': data['holidays'] ?? [],
        if (data['estag_rules'] != null) 'estag_rules': data['estag_rules'],
      });

      final response = await http.post(
        Uri.parse('$backendUrl/export-excel'),
        headers: {'Content-Type': 'application/json'},
        body: body,
      );

      if (response.statusCode == 200) {
        final Uint8List bytes = response.bodyBytes;
        final suffix = _isInternExport(data) ? '_estag' : '';
        final downloadName =
            'Folha_Ponto_${data['employee']['name']}_$month$suffix';

        if (kIsWeb) {
          await FileSaver.instance.saveFile(
            name: downloadName,
            bytes: bytes,
            ext: 'xlsx',
            mimeType: MimeType.microsoftExcel,
          );
        } else {
          final directory = await getApplicationDocumentsDirectory();
          final file = File('${directory.path}/$downloadName.xlsx');
          await file.writeAsBytes(bytes);
        }
      } else {
        throw Exception(
            'Erro no servidor Python (${response.statusCode}): ${response.body}');
      }
    } catch (e) {
      throw Exception(
          'Falha ao conectar ao servidor de exportacao: $e\nCertifique-se de que o Python (main.py) esta rodando.');
    }
  }

  bool _isInternExport(Map<String, dynamic> data) {
    final role = data['employee']?['role']?.toString().toLowerCase() ?? '';
    final customRole = data['custom_role']?.toString().toLowerCase() ?? '';
    return role.contains('intern') ||
        role.contains('estag') ||
        customRole.contains('estag');
  }

  Future<void> exportBatchToHtml({
    required List<Map<String, dynamic>> reports,
    required String month,
    required String year,
  }) async {
    try {
      final List<Map<String, dynamic>> batchData = reports.map((r) {
        final role = (r['employee']['role'] ?? '').toString().toLowerCase();
        final isEstagiario =
            role.contains('estagiario') || role.contains('intern');
        return {
          'employee_name': r['employee']['name'],
          'employee_role': r['employee']['role'],
          'month': month,
          'year': year,
          'is_campo': !isEstagiario,
          'daily_records': r['daily_records'],
          'custom_role': r['custom_role'],
          'custom_department': r['custom_department'],
          'custom_work_hours': r['custom_work_hours'],
          'generate_from_scratch': r['generate_from_scratch'],
          'target_hours': r['target_hours'],
          'holidays': r['holidays'] ?? [],
        };
      }).toList();

      final response = await http.post(
        Uri.parse('$backendUrl/export-batch-html'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(batchData),
      );

      if (response.statusCode == 200) {
        final Uint8List bytes = response.bodyBytes;
        final downloadName = 'Folhas_Ponto_VM_$month-$year';

        if (kIsWeb) {
          await FileSaver.instance.saveFile(
            name: downloadName,
            bytes: bytes,
            ext: 'html',
            mimeType: MimeType.custom,
            customMimeType: 'text/html',
          );
        } else {
          final directory = await getApplicationDocumentsDirectory();
          final file = File('${directory.path}/$downloadName.html');
          await file.writeAsBytes(bytes);
        }
      } else {
        throw Exception(
            'Erro no servidor Python HTML (${response.statusCode}): ${response.body}');
      }
    } catch (e) {
      throw Exception('Falha na exportacao HTML em lote: $e');
    }
  }

  Future<void> exportBatchToZip({
    required List<Map<String, dynamic>> reports,
    required String month,
    required String year,
  }) async {
    try {
      final List<Map<String, dynamic>> batchData = reports.map((r) {
        final role = (r['employee']['role'] ?? '').toString().toLowerCase();
        final isEstagiario =
            role.contains('estagiario') || role.contains('intern');
        return {
          'employee_name': r['employee']['name'],
          'employee_role': r['employee']['role'],
          'month': month,
          'year': year,
          'is_campo': !isEstagiario,
          'daily_records': r['daily_records'],
          'custom_role': r['custom_role'],
          'custom_department': r['custom_department'],
          'custom_work_hours': r['custom_work_hours'],
          'generate_from_scratch': r['generate_from_scratch'],
          'target_hours': r['target_hours'],
          'holidays': r['holidays'] ?? [],
        };
      }).toList();

      final response = await http.post(
        Uri.parse('$backendUrl/export-batch'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(batchData),
      );

      if (response.statusCode == 200) {
        final Uint8List bytes = response.bodyBytes;
        final downloadName = 'Folhas_Ponto_Lote_$month-$year';

        if (kIsWeb) {
          await FileSaver.instance.saveFile(
            name: downloadName,
            bytes: bytes,
            ext: 'zip',
            mimeType: MimeType.zip,
          );
        } else {
          final directory = await getApplicationDocumentsDirectory();
          final file = File('${directory.path}/$downloadName.zip');
          await file.writeAsBytes(bytes);
        }
      } else {
        throw Exception(
            'Erro no servidor Python Batch (${response.statusCode}): ${response.body}');
      }
    } catch (e) {
      throw Exception('Falha na exportacao em lote: $e');
    }
  }
}
