import 'dart:async';
import 'dart:math' as math;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

/// Carregamento da abertura do app (Firebase, sessao, tela de ponto).
///
/// Sem internet a abertura demora mais (o app sobe da copia salva no
/// aparelho e as consultas ao servidor precisam desistir antes). Para a
/// pessoa nao achar que travou, mostra um aviso e uma barra de porcentagem.
///
/// A porcentagem e por etapa: a tela inicial em HTML (index.html) vai ate
/// 80% e cada tela do app que usa este widget cobre uma faixa
/// [from]-[to]. Dentro da faixa a barra anda devagar, sem chegar ao fim
/// antes de a etapa terminar, e nunca volta para tras entre uma tela e a
/// seguinte. Com internet continua so o circulo girando.
class StartupLoading extends StatefulWidget {
  const StartupLoading({super.key, this.from = 80, this.to = 99});

  final double from;
  final double to;

  @override
  State<StartupLoading> createState() => _StartupLoadingState();
}

class _StartupLoadingState extends State<StartupLoading> {
  static const Color _wine = Color(0xFF8B0000);

  // Ultima porcentagem mostrada, compartilhada entre as telas da abertura.
  static double _lastShown = 0;

  bool _offline = false;
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  Timer? _ticker;
  late final double _from;
  final DateTime _startedAt = DateTime.now();
  double _percent = 0;

  @override
  void initState() {
    super.initState();
    _from = _lastShown > widget.from ? _lastShown : widget.from;
    _percent = _from;
    Connectivity()
        .checkConnectivity()
        .then(_update)
        .catchError((Object _) => null);
    _subscription = Connectivity().onConnectivityChanged.listen(_update);
  }

  void _update(List<ConnectivityResult> results) {
    if (!mounted) return;
    final offline =
        results.isEmpty || results.contains(ConnectivityResult.none);
    if (offline != _offline) setState(() => _offline = offline);
    if (offline) {
      _ticker ??= Timer.periodic(const Duration(milliseconds: 150), (_) {
        _tick();
      });
    } else {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  void _tick() {
    if (!mounted) return;
    final seconds =
        DateTime.now().difference(_startedAt).inMilliseconds / 1000.0;
    final to = widget.to > _from ? widget.to : _from;
    final value = _from + (to - _from) * (1 - math.exp(-seconds / 4));
    _lastShown = value;
    setState(() => _percent = value);
  }

  @override
  void dispose() {
    _ticker?.cancel();
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
            if (!_offline) const CircularProgressIndicator(color: _wine),
            if (_offline) ...[
              SizedBox(
                width: 220,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: _percent / 100,
                    minHeight: 6,
                    color: _wine,
                    backgroundColor: Colors.grey[300],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Abrindo... ${_percent.floor()}%',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: _wine,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
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
