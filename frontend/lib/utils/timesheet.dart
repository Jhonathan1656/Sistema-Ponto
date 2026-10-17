// Folha de ponto de um dia: dos pontos (time_records) de um dia de trabalho,
// ja agrupados por groupRecordsByWorkDay, para a linha da planilha, com as
// horas separadas em normais, extras, 50% e 100%.
//
// Logica portada dos scripts Python de fechamento (Pontocampo.py), ajustada
// ao que foi combinado.

import 'shift_records.dart';

/// Pares de colunas entrada/saida do modelo da folha (C-D / E-F / G-H). A
/// planilha recalcula o total do dia somando esses pares.
const int timesheetColumnPairs = 3;

/// Arredonda a batida para a meia hora: ate :15 volta para a hora cheia, ate
/// :45 fica em :30, depois disso vai para a hora seguinte.
DateTime roundPunchTime(DateTime dt) {
  final minutes = dt.minute;
  if (minutes <= 15) return DateTime(dt.year, dt.month, dt.day, dt.hour, 0);
  if (minutes <= 45) return DateTime(dt.year, dt.month, dt.day, dt.hour, 30);
  return DateTime(dt.year, dt.month, dt.day, dt.hour + 1, 0);
}

const List<String> _fixedHolidays = [
  '01/01',
  '21/04',
  '01/05',
  '07/09',
  '12/10',
  '02/11',
  '15/11',
  '25/12'
];

String _two(int value) => value.toString().padLeft(2, '0');

String _hhmm(DateTime dt) => '${_two(dt.hour)}:${_two(dt.minute)}';

/// Feriado nacional: o dia inteiro paga 100%.
bool isHoliday(DateTime date) {
  final ano = date.year;
  final diaMes = '${_two(date.day)}/${_two(date.month)}';
  if (_fixedHolidays.contains(diaMes)) return true;
  // Consciencia Negra: feriado nacional pela Lei 14.759/2023, desde 2024.
  if (ano >= 2024 && diaMes == '20/11') return true;

  // Pascoa e Sexta-feira Santa (Algoritmo de Meeus/Jones/Butcher)
  int a = ano % 19;
  int b = ano ~/ 100;
  int c = ano % 100;
  int d = b ~/ 4;
  int e = b % 4;
  int f = (b + 8) ~/ 25;
  int g = (b - f + 1) ~/ 3;
  int h = (19 * a + b - d - g + 15) % 30;
  int i = c ~/ 4;
  int k = c % 4;
  int l = (32 + 2 * e + 2 * i - h - k) % 7;
  int m = (a + 11 * h + 22 * l) ~/ 451;
  int mesPascoa = (h + l - 7 * m + 114) ~/ 31;
  int diaPascoa = ((h + l - 7 * m + 114) % 31) + 1;
  DateTime pascoa = DateTime(ano, mesPascoa, diaPascoa);
  DateTime sextaSanta = pascoa.subtract(const Duration(days: 2));

  return date.day == sextaSanta.day && date.month == sextaSanta.month;
}

/// Minutos de [start] a [end] por tipo: 'normal', 'extras' (estagiario fora
/// das 13:30-19:30 em dia util), 'extra50' e 'extra100'.
///   - domingo ou feriado: 100%
///   - noturno 22h-05h: 100%
///   - sabado 05h-22h: 50%
///   - dia util: normal (estagiario: normal so das 13:30 as 19:30)
/// Cada minuto vale pelo PROPRIO dia. Pelo dia do inicio da sessao, o turno
/// de sabado 19:30 a domingo 07:00 pagava a manha de domingo a 50%.
Map<String, int> classifyWorkMinutes(
    DateTime start, DateTime end, String? role) {
  final isEstagiario = role == 'intern' || role == 'estagiario';
  var normal = 0, extras = 0, extra50 = 0, extra100 = 0;
  DateTime? day;
  var wholeDay100 = false;
  for (var current = start;
      current.isBefore(end);
      current = current.add(const Duration(minutes: 1))) {
    final today = DateTime(current.year, current.month, current.day);
    if (today != day) {
      day = today;
      wholeDay100 = today.weekday == DateTime.sunday || isHoliday(today);
    }
    final hour = current.hour;
    if (wholeDay100 || hour >= 22 || hour < 5) {
      extra100++;
    } else if (current.weekday == DateTime.saturday) {
      extra50++;
    } else if (!isEstagiario) {
      normal++;
    } else {
      final minuteOfDay = hour * 60 + current.minute;
      if (minuteOfDay >= 13 * 60 + 30 && minuteOfDay < 19 * 60 + 30) {
        normal++;
      } else {
        extras++;
      }
    }
  }
  return {
    'normal': normal,
    'extras': extras,
    'extra50': extra50,
    'extra100': extra100,
  };
}

/// Sessoes de trabalho (pares entrada/saida) de UM turno: o turno [inicio] a
/// [fim] (ja arredondados) menos as [pauses] (refeicoes batidas ou
/// automaticas), que ficam descontadas por serem os intervalos ENTRE as
/// sessoes. O trecho da pausa fora do turno e ignorado.
List<List<DateTime>> buildShiftSessions({
  required DateTime inicio,
  required DateTime fim,
  required List<List<DateTime>> pauses,
}) {
  if (!fim.isAfter(inicio)) return [];
  final ordered = [...pauses]..sort((a, b) => a[0].compareTo(b[0]));

  final sessions = <List<DateTime>>[];
  var cursor = inicio;
  for (final p in ordered) {
    final start = p[0].isBefore(inicio) ? inicio : p[0];
    final end = p[1].isAfter(fim) ? fim : p[1];
    if (end.isBefore(start)) continue;
    // Pausa de duracao zero (12:05-12:14 arredonda para 12:00-12:00) ainda
    // divide o turno em dois pares, como sempre saiu na folha.
    if (start.isAfter(cursor)) sessions.add([cursor, start]);
    if (end.isAfter(cursor)) cursor = end;
  }
  if (fim.isAfter(cursor)) sessions.add([cursor, fim]);
  return sessions;
}

/// Turno do dia, arredondado, com as pausas batidas e as janelas de refeicao
/// automatica (almoco 12-13 e jantar 20-21 do dia da entrada) que ele cobre
/// inteiras e que ainda nao tem refeicao.
class _ShiftPlan {
  _ShiftPlan(this.inicio, this.fim, this.pauses)
      : windows = [
          for (final hour in const [12, 20])
            if (!inicio.isAfter(_atHour(inicio, hour)) &&
                !fim.isBefore(_atHour(inicio, hour + 1)))
              [_atHour(inicio, hour), _atHour(inicio, hour + 1)],
        ];

  final DateTime inicio;
  final DateTime fim;
  final List<List<DateTime>> pauses;
  final List<List<DateTime>> windows;

  static DateTime _atHour(DateTime day, int hour) =>
      DateTime(day.year, day.month, day.day, hour);
}

/// Distancia entre dois intervalos; zero quando se encostam ou sobrepoem.
Duration _gapBetween(List<DateTime> a, List<DateTime> b) {
  final after = b[0].difference(a[1]);
  final before = a[0].difference(b[1]);
  final gap = after > before ? after : before;
  return gap.isNegative ? Duration.zero : gap;
}

/// A [meal] (pausa batida ou intervalo entre turnos) e a refeicao da janela
/// de referencia mais proxima dela: almoco 12-13 ou jantar 20-21 do dia dela,
/// da vespera ou do dia seguinte. Se algum turno de [plans] ia descontar essa
/// janela, deixa de descontar. Se nenhum a cobre, nada muda: o intervalo
/// 12-13 entre os turnos 07-12 e 13-22 e o proprio almoco. Procurar so entre
/// as janelas que os turnos cobrem levava a refeicao para a outra janela,
/// horas longe: o almoco batido como saida e entrada cancelava o jantar.
void _takeNearestWindow(List<_ShiftPlan> plans, List<DateTime> meal) {
  final day = meal[0];
  List<DateTime>? nearest;
  for (final offset in const [-1, 0, 1]) {
    for (final hour in const [12, 20]) {
      final window = [
        DateTime(day.year, day.month, day.day + offset, hour),
        DateTime(day.year, day.month, day.day + offset, hour + 1),
      ];
      if (nearest == null ||
          _gapBetween(meal, window) < _gapBetween(meal, nearest)) {
        nearest = window;
      }
    }
  }
  for (final plan in plans) {
    plan.windows.removeWhere((window) => window[0] == nearest![0]);
  }
}

/// Retorno de pausa gravado pelo sistema, nao batido pela pessoa: o
/// fechamento da pausa esquecida (job do servidor ou o app) grava o doc
/// "autoclose_<id do inicio da pausa>" com auto_closed.
bool isAutomaticBreakEnd(Map<String, dynamic> record) =>
    record['auto_closed'] == true ||
    (record['id']?.toString() ?? '').startsWith('autoclose_');

class _PauseMark {
  _PauseMark(this.type, this.at, this.automatic);

  final String type;
  final DateTime at;
  final bool automatic;
}

class _Shift {
  _Shift(this.entry);

  final DateTime entry;
  DateTime? exit;

  /// Turno da noite do lote antigo do gestor (isLegacyBatchRecord): saida e
  /// pausas da madrugada gravadas antes da entrada, na mesma data.
  bool manualNight = false;
  final List<_PauseMark> pauses = [];
}

const Set<String> _pauseTypes = {
  'break_start',
  'break_end',
  'entry_3',
  'exit_3'
};

DateTime? _timeOf(Map<String, dynamic> record) =>
    DateTime.tryParse(record['timestamp']?.toString() ?? '')?.toLocal();

_PauseMark _pauseMark(Map<String, dynamic> record, DateTime at) => _PauseMark(
    record['record_type'].toString(), at, isAutomaticBreakEnd(record));

/// Monta os turnos do dia em ordem: cada entrada abre um turno, as pausas
/// entram no turno aberto e a saida o fecha.
List<_Shift> _pairShifts(List<Map<String, dynamic>> ordered) {
  final times = [for (final record in ordered) _timeOf(record)];
  // Turno da noite do lote antigo: a saida e as pausas da madrugada vem
  // antes da entrada e ficam reservadas para ela (manualNightMorning; a saida
  // e a ultima). Pelas pausas soltas desde o ultimo ponto, a pausa da
  // madrugada se perdia quando o mesmo lote tinha um turno de dia no meio. O
  // lote novo grava a data real e segue a ordem comum, como o app.
  final nights = <int, List<int>>{};
  for (var i = 0; i < ordered.length; i++) {
    final morning = manualNightMorning(ordered, i);
    if (morning.isNotEmpty &&
        times[i] != null &&
        morning.every((j) => times[j] != null)) {
      nights[i] = morning;
    }
  }
  final reserved = {for (final morning in nights.values) ...morning};

  final shifts = <_Shift>[];
  // Pausas sem turno aberto, desde o ultimo ponto de entrada ou saida.
  final loose = <int>[];
  _Shift? current;
  for (var i = 0; i < ordered.length; i++) {
    final record = ordered[i];
    final at = times[i];
    if (at == null || reserved.contains(i)) continue;
    final type = record['record_type']?.toString();
    if (type == 'check_in') {
      final shift = _Shift(at);
      final morning = nights[i];
      if (morning != null) {
        DateTime nextDay(DateTime mark) =>
            mark.isBefore(at) ? mark.add(const Duration(days: 1)) : mark;
        shift.manualNight = true;
        shift.exit = nextDay(times[morning.last]!);
        for (final j in morning.take(morning.length - 1)) {
          shift.pauses.add(_pauseMark(ordered[j], nextDay(times[j]!)));
        }
      }
      loose.clear();
      shifts.add(shift);
      current = shift;
    } else if (type == 'check_out') {
      // Saida antes da primeira entrada do dia e solta (turno de outro dia
      // fechado tarde): contada, virava a noite inteira ate a manha seguinte.
      if (current == null || current.manualNight) {
        continue;
      }
      // Saida repetida sem nova entrada corrige a anterior (vale a ultima),
      // como o gestor lancando a saida real de um turno fechado no "Esqueci".
      if (current.exit != null) {
        for (final j in loose) {
          current.pauses.add(_pauseMark(ordered[j], times[j]!));
        }
      }
      current.exit = at;
      loose.clear();
    } else if (_pauseTypes.contains(type)) {
      if (current != null && (current.exit == null || current.manualNight)) {
        current.pauses.add(_pauseMark(record, at));
      } else {
        loose.add(i);
      }
    }
  }
  return shifts;
}

/// Inicio e fim (arredondados) de cada pausa do tipo [startType] /
/// [endType] do turno, em ordem; fim null na pausa deixada aberta. Cada
/// inicio abre uma pausa e o retorno seguinte a fecha. Inicio repetido com a
/// pausa aberta nao abre outra (vale o primeiro). Retorno batido depois do
/// automatico, antes de outro inicio, vale no lugar dele: o retorno batido
/// offline chega depois de o servidor ja ter fechado a pausa "esquecida" com
/// 1h, e o batido e o que aconteceu. Retorno sem pausa aberta e ignorado.
///
/// Todas as pausas do tipo contam, nao so a primeira: o lote do gestor
/// oferece a Pausa 1 primeiro, e a pausa lancada como Pausa 1 na noite que
/// ja tinha a Pausa 1 do app (Saida batida no lugar da Pausa 2) sumia e era
/// paga como trabalhada.
///
/// No mesmo horario, com a pausa aberta o retorno fecha ela antes do novo
/// inicio (Pausa 1 23:00-00:00 e 00:00-00:30); sem pausa aberta o inicio vem
/// antes (pausa de 0 min, inicio e fim iguais).
List<(DateTime, DateTime?)> _pickPauses(
    _Shift shift, String startType, String endType) {
  final marks = [
    for (final mark in shift.pauses)
      if (mark.type == startType || mark.type == endType) mark,
  ]..sort((a, b) => a.at.compareTo(b.at));
  final pauses = <(_PauseMark, _PauseMark?)>[];
  _PauseMark? open;
  void take(_PauseMark mark) {
    if (mark.type == startType) {
      open ??= mark;
    } else if (open != null) {
      pauses.add((open!, mark));
      open = null;
    } else if (pauses.isNotEmpty &&
        pauses.last.$2!.automatic &&
        !mark.automatic) {
      pauses.last = (pauses.last.$1, mark);
    }
  }

  for (var i = 0; i < marks.length;) {
    var j = i;
    while (j < marks.length && marks[j].at == marks[i].at) {
      j++;
    }
    final same = marks.sublist(i, j);
    final starts = same.where((mark) => mark.type == startType);
    final ends = same.where((mark) => mark.type != startType);
    for (final mark in open != null
        ? [...ends, ...starts]
        : [...starts, ...ends]) {
      take(mark);
    }
    i = j;
  }
  if (open != null) pauses.add((open!, null));
  return [
    for (final (start, end) in pauses)
      (
        roundPunchTime(start.at),
        end == null ? null : roundPunchTime(end.at),
      ),
  ];
}

/// Cabe as sessoes nos [timesheetColumnPairs] pares de colunas. Passando
/// disso (dois turnos com refeicao no mesmo dia), junta as duas sessoes
/// vizinhas de menor intervalo, que passa a contar como trabalhado: cortar a
/// sessao que sobra perdia horas trabalhadas de verdade (a noite inteira de
/// quem dobra 08-17 e 19:30-07:00).
List<List<DateTime>> _fitColumns(List<List<DateTime>> sessions) {
  final fitted = <List<DateTime>>[];
  for (final s in [...sessions]..sort((a, b) => a[0].compareTo(b[0]))) {
    if (fitted.isNotEmpty && s[0].isBefore(fitted.last[1])) {
      // Turnos sobrepostos (ponto lancado em dobro): o trecho conta uma vez.
      if (s[1].isAfter(fitted.last[1])) fitted.last[1] = s[1];
    } else {
      fitted.add([s[0], s[1]]);
    }
  }
  while (fitted.length > timesheetColumnPairs) {
    Duration gap(int i) => fitted[i + 1][0].difference(fitted[i][1]);
    var shortest = 0;
    for (var i = 1; i + 1 < fitted.length; i++) {
      if (gap(i) < gap(shortest)) shortest = i;
    }
    fitted[shortest] = [fitted[shortest][0], fitted[shortest + 1][1]];
    fitted.removeAt(shortest + 1);
  }
  return fitted;
}

/// Linha da folha do dia de trabalho [dateKey] (yyyy-MM-dd) a partir dos
/// pontos desse dia (groupRecordsByWorkDay): date, os 3 pares de colunas
/// ("HH:mm" ou null) check_in/check_out, break_start/break_end,
/// entry_3/exit_3, start_date (yyyy-MM-dd em que o primeiro par comeca de
/// verdade) e as horas total_hours, regular_hours, overtime_hours, extra_50 e
/// extra_100.
///
/// start_date e para o backend, que so ve "HH:mm": a entrada 23:50 arredonda
/// para 00:00 do dia seguinte e, pela data da linha, o resumo do estagiario
/// pagava aquelas horas no dia errado (sabado a 50% em vez de domingo a 100%).
///
/// O dia e a soma dos seus turnos (cada entrada ate a saida seguinte), nao
/// "primeira entrada ate ultima saida", que pagava o intervalo entre dois
/// turnos (08-11 e 14-18 davam 9h). As horas saem das mesmas sessoes que vao
/// para as colunas, porque a planilha recalcula o total por elas.
///
/// Refeicoes: a pausa batida e o intervalo de ate 2h entre dois turnos do dia
/// contam como a refeicao da janela mais proxima (almoco 12-13 ou jantar
/// 20-21). Cada janela do dia da entrada que o turno cobre inteira e ficou sem
/// refeicao e descontada como pausa automatica de 1h.
///
/// Turno aberto (sem saida) ou fechado no "Esqueci" (saida 1s depois da
/// entrada) nao soma horas; sem nenhuma outra sessao no dia, a linha mostra
/// so a entrada.
Map<String, dynamic> computeWorkDay(
    String dateKey, Iterable<dynamic> dayRecords, String? role) {
  final ordered = sortRecords(dayRecords
      .map((item) => Map<String, dynamic>.from(item as Map))
      .toList());

  final plans = <_ShiftPlan>[];
  DateTime? openEntry;
  for (final shift in _pairShifts(ordered)) {
    final exit = shift.exit;
    // Saida a menos de 1 min da entrada e o "Esqueci" (entrada + 1s). Vale o
    // tempo, nao o id forgot_, que fica no doc quando o gestor corrige o
    // horario nele. Sem arredondar: 08:15:59 e 08:16:00 viravam 08:00-08:30.
    if (exit == null ||
        exit.difference(shift.entry) < const Duration(minutes: 1)) {
      openEntry ??= shift.entry;
      continue;
    }
    final pauses = [
      for (final pause in [
        ..._pickPauses(shift, 'break_start', 'break_end'),
        ..._pickPauses(shift, 'entry_3', 'exit_3'),
      ])
        // Pausa deixada aberta (bateu o inicio, esqueceu o fim) fecha com 1h.
        [pause.$1, pause.$2 ?? pause.$1.add(const Duration(hours: 1))],
    ];
    final plan =
        _ShiftPlan(roundPunchTime(shift.entry), roundPunchTime(exit), pauses);
    // Cada pausa batida e a refeicao da janela mais proxima dela, nao a do
    // tipo do botao: o app oferece sempre a Pausa 1 primeiro, e a pausa da
    // madrugada batida como Pausa 1 ainda descontava o jantar automatico.
    for (final pause in pauses) {
      _takeNearestWindow([plan], pause);
    }
    plans.add(plan);
  }
  plans.sort((a, b) => a.inicio.compareTo(b.inicio));
  for (var i = 0; i + 1 < plans.length; i++) {
    final gap = [plans[i].fim, plans[i + 1].inicio];
    final length = gap[1].difference(gap[0]);
    // Intervalo de ate maxMealGap (shift_records.dart) entre dois turnos do
    // dia de trabalho, inclusive a volta da refeicao depois da meia-noite.
    if (length.isNegative || length > maxMealGap) continue;
    _takeNearestWindow([plans[i], plans[i + 1]], gap);
  }

  final sessions = [
    for (final plan in plans)
      ...buildShiftSessions(
        inicio: plan.inicio,
        fim: plan.fim,
        pauses: [...plan.pauses, ...plan.windows],
      ),
  ];
  final columns = _fitColumns(sessions);
  var normal = 0, extras = 0, extra50 = 0, extra100 = 0;
  for (final s in columns) {
    final minutes = classifyWorkMinutes(s[0], s[1], role);
    normal += minutes['normal']!;
    extras += minutes['extras']!;
    extra50 += minutes['extra50']!;
    extra100 += minutes['extra100']!;
  }

  String? column(int pair, int edge) =>
      columns.length > pair ? _hhmm(columns[pair][edge]) : null;
  return {
    'date': dateKey,
    'check_in': columns.isEmpty && openEntry != null
        ? _hhmm(roundPunchTime(openEntry))
        : column(0, 0),
    'check_out': column(0, 1),
    'break_start': column(1, 0),
    'break_end': column(1, 1),
    'entry_3': column(2, 0),
    'exit_3': column(2, 1),
    'start_date': columns.isEmpty
        ? null
        : '${columns[0][0].year}-${_two(columns[0][0].month)}-'
            '${_two(columns[0][0].day)}',
    'total_hours': (normal + extras + extra50 + extra100) / 60,
    'regular_hours': normal / 60,
    'overtime_hours': (extras + extra50 + extra100) / 60,
    'extra_50': extra50 / 60,
    'extra_100': extra100 / 60,
  };
}
