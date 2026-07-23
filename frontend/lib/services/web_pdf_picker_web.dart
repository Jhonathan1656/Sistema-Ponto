import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';

class SelectedPdfFile {
  const SelectedPdfFile({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;
}

Future<SelectedPdfFile?> pickPdfFromBrowser() {
  final input = html.FileUploadInputElement()
    ..accept = '.pdf,application/pdf'
    ..multiple = false
    ..style.display = 'none';
  html.document.body?.append(input);

  final completer = Completer<SelectedPdfFile?>();
  input.onChange.first.then((_) {
    final file = input.files?.isNotEmpty == true ? input.files!.first : null;
    if (file == null) {
      input.remove();
      completer.complete(null);
      return;
    }

    final reader = html.FileReader();
    reader.onError.first.then((_) {
      input.remove();
      completer.completeError(StateError('Nao foi possivel ler o PDF.'));
    });
    reader.onLoadEnd.first.then((_) {
      input.remove();
      final result = reader.result;
      if (result is ByteBuffer) {
        completer.complete(SelectedPdfFile(
          name: file.name,
          bytes: Uint8List.view(result),
        ));
      } else {
        completer.completeError(StateError('Nao foi possivel ler o PDF.'));
      }
    });
    reader.readAsArrayBuffer(file);
  });

  input.click();
  return completer.future;
}

class WebPdfInput extends StatefulWidget {
  const WebPdfInput({super.key, required this.onSelected, required this.onError});

  final ValueChanged<SelectedPdfFile> onSelected;
  final ValueChanged<Object> onError;

  @override
  State<WebPdfInput> createState() => _WebPdfInputState();
}

class _WebPdfInputState extends State<WebPdfInput> {
  late final String _viewType;

  @override
  void initState() {
    super.initState();
    _viewType = 'ponto-pdf-input-${identityHashCode(this)}';
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (_) {
      final input = html.FileUploadInputElement()
        ..accept = '.pdf,application/pdf'
        ..multiple = false
        ..style.width = '100%'
        ..style.height = '42px'
        ..style.padding = '8px 12px'
        ..style.boxSizing = 'border-box'
        ..style.border = '1px solid #a80000'
        ..style.borderRadius = '22px'
        ..style.color = '#a80000'
        ..style.backgroundColor = 'transparent';

      input.onChange.listen((_) {
        final file = input.files?.isNotEmpty == true ? input.files!.first : null;
        if (file == null) return;

        final reader = html.FileReader();
        reader.onError.first.then((_) {
          widget.onError(StateError('Nao foi possivel ler o PDF.'));
        });
        reader.onLoadEnd.first.then((_) {
          final result = reader.result;
          Uint8List? bytes;
          if (result is ByteBuffer) {
            bytes = Uint8List.view(result);
          } else if (result is Uint8List) {
            bytes = result;
          } else if (result is ByteData) {
            bytes = Uint8List.view(result.buffer, result.offsetInBytes,
                result.lengthInBytes);
          } else if (result is List<int>) {
            bytes = Uint8List.fromList(result);
          }

          if (bytes != null) {
            widget.onSelected(SelectedPdfFile(
              name: file.name,
              bytes: bytes,
            ));
          } else {
            widget.onError(StateError('Nao foi possivel ler o PDF.'));
          }
        });
        reader.readAsArrayBuffer(file);
      });
      return input;
    });
  }

  @override
  Widget build(BuildContext context) => HtmlElementView(viewType: _viewType);
}
