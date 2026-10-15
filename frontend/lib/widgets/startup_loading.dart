import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

/// Carregamento da abertura do app (Firebase, sessao, tela de ponto).
///
/// Sem internet a abertura demora mais (o app sobe da copia salva no
/// aparelho e as consultas ao servidor precisam desistir antes). Para a
/// pessoa nao achar que travou, mostra um aviso explicando que vai abrir.
class StartupLoading extends StatefulWidget {
  const StartupLoading({super.key});

  @override
  State<StartupLoading> createState() => _StartupLoadingState();
}

class _StartupLoadingState extends State<StartupLoading> {
  static const Color _wine = Color(0xFF8B0000);

  bool _offline = false;
  StreamSubscription<List<ConnectivityResult>>? _subscription;

  @override
  void initState() {
    super.initState();
    Connectivity()
        .checkConnectivity()
        .then(_update)
        .catchError((Object _) => null);
    _subscription = Connectivity().onConnectivityChanged.listen(_update);
  }

  void _update(List<ConnectivityResult> results) {
    final offline =
        results.isEmpty || results.contains(ConnectivityResult.none);
    if (mounted && offline != _offline) setState(() => _offline = offline);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: _wine),
            if (_offline) ...[
              const SizedBox(height: 24),
              const Icon(Icons.wifi_off_rounded, color: _wine, size: 28),
              const SizedBox(height: 12),
              const Text(
                'Você está sem internet',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: _wine,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'O app vai abrir com os dados salvos no aparelho. '
                'Sem sinal isso pode levar alguns segundos.\n'
                'Os pontos batidos agora sobem quando a internet voltar.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.4,
                  color: Colors.grey[700],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
