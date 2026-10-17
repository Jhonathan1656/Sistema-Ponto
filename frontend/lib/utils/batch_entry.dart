// Lancamento em lote do gestor (aba Lote Gestor): os horarios do formulario
// viram pontos com a data real de cada um.
//
// O lote antigo gravava tudo na data escolhida, e a noite 19:30-07:00 ficava
// com a saida ANTES da entrada. Esses pontos continuam com as regras proprias
// (isLegacyBatchRecord em shift_records.dart); os do lote novo levam
// batchRealDatesField e valem como a batida do app.

import 'shift_records.dart';

/// Hora e minuto de um campo do formulario.
typedef BatchTime = ({int hour, int minute});

/// Um ponto do lote, ja na data em que acontece.
class BatchPunch {
  const BatchPunch(this.recordType, this.at, {this.nextDay = false});

  final String recordType;
  final DateTime at;

  /// Foi para o dia seguinte a data escolhida (horario antes da entrada ou,
  /// sem ela, do primeiro horario do formulario).
  final bool nextDay;
}

/// Campos do formulario do lote, na ordem da tela.
const List<String> batchFormOrder = [
  'check_in',
  'break_start',
  'break_end',
  'entry_3',
  'exit_3',
  'check_out',
];

/// Pontos do lote na ordem de [times] (record_type -> horario, so os
/// preenchidos), na data [date]. A referencia e a entrada ou, sem ela, o
/// primeiro horario preenchido na ordem do formulario ([batchFormOrder]).
/// Todo horario ANTES da referencia e do dia seguinte: a noite com entrada
/// 19:30 e saida 07:00 em 15/10 grava 15/10 19:30 e 16/10 07:00, como o app,
/// e o lote so com a Pausa 1 23:00-01:00 em 15/10 grava o fim em 16/10 01:00
/// (em 15/10 o fim ficava antes da entrada e a noite pagava 1h a mais). O
/// horario igual ao da referencia fica no mesmo dia, menos a saida igual a
/// entrada, que vai para o dia seguinte (24h, o erro de [maxShiftSpan]): era
/// um turno de 0h, lido como "Esqueci". Sem entrada, a saida igual a pausa
/// fica na data (Pausa 1 fim 07:00 e Saida 07:00 da pausa deixada aberta no
/// app). So a saida (a que corrige um "Esqueci", por exemplo) e a propria
/// referencia e fica em [date].
///
/// Horarios iguais saem com o mesmo timestamp; a ordem entre eles vem do
/// tipo (sortRecords em shift_records.dart): o fim da pausa antes da
/// saida, a entrada antes do inicio da pausa. A mesma ordem vale contra a
/// batida do app no mesmo minuto (com segundos).
List<BatchPunch> planBatchPunches(
    DateTime date, Map<String, BatchTime> times) {
  int minuteOfDay(BatchTime time) => time.hour * 60 + time.minute;
  final anchorType =
      batchFormOrder.firstWhere(times.containsKey, orElse: () => '');
  final anchor = times[anchorType];
  bool isNextDay(String type, BatchTime time) {
    if (anchor == null || type == anchorType) return false;
    final minute = minuteOfDay(time);
    final anchorMinute = minuteOfDay(anchor);
    return minute < anchorMinute ||
        (type == 'check_out' &&
            anchorType == 'check_in' &&
            minute == anchorMinute);
  }

  return [
    for (final item in times.entries)
      if (isNextDay(item.key, item.value))
        BatchPunch(
          item.key,
          DateTime(date.year, date.month, date.day + 1, item.value.hour,
              item.value.minute),
          nextDay: true,
        )
      else
        BatchPunch(
          item.key,
          DateTime(date.year, date.month, date.day, item.value.hour,
              item.value.minute),
        ),
  ];
}

/// Do primeiro ao ultimo ponto do lote, ou null sem pontos. Depois de
/// planBatchPunches o primeiro e a referencia (a entrada ou, sem ela, o
/// primeiro horario do formulario). Acima de [maxShiftSpan] o lote nao e um
/// turno (entrada 08:00 e saida 07:00 virariam 23h; Pausa 1 02:00 e saida
/// 01:00 tambem): o gestor confere os horarios.
Duration? batchShiftSpan(List<BatchPunch> punches) {
  if (punches.isEmpty) return null;
  var first = punches.first.at;
  var last = first;
  for (final punch in punches) {
    if (punch.at.isBefore(first)) first = punch.at;
    if (punch.at.isAfter(last)) last = punch.at;
  }
  return last.difference(first);
}

/// O lote passa de [maxShiftSpan] da entrada ao ultimo ponto?
bool batchTooLong(List<BatchPunch> punches) {
  final span = batchShiftSpan(punches);
  return span != null && span > maxShiftSpan;
}

/// Campos extras de todo ponto gravado pelo lote novo.
const Map<String, dynamic> batchRecordFields = {batchRealDatesField: true};
