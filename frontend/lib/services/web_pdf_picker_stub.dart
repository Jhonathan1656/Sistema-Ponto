import 'dart:typed_data';

import 'package:flutter/widgets.dart';

class SelectedPdfFile {
  const SelectedPdfFile({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;
}

Future<SelectedPdfFile?> pickPdfFromBrowser() {
  throw UnsupportedError('Seletor web indisponivel nesta plataforma.');
}

class WebPdfInput extends StatelessWidget {
  const WebPdfInput({super.key, required this.onSelected, required this.onError});

  final ValueChanged<SelectedPdfFile> onSelected;
  final ValueChanged<Object> onError;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
