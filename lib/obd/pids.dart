/// Mode 01 PID definitions (SAE J1979). A, B, C, D = data bytes.
class PidDef {
  final int pid;
  final String name;
  final String unit;
  final int bytes;
  final double Function(List<int> d) decode;
  final int decimals;

  /// For enum/bitfield PIDs: a human-readable value instead of a number.
  final String Function(List<int> d)? text;

  const PidDef(this.pid, this.name, this.unit, this.bytes, this.decode,
      {this.decimals = 0, this.text});

  String get hex => '01${pid.toRadixString(16).padLeft(2, '0').toUpperCase()}';

  /// Placeholder for a PID the car supports but this app has no formula for.
  factory PidDef.unknown(int pid) => PidDef(
        pid,
        'PID 01${pid.toRadixString(16).padLeft(2, '0').toUpperCase()} (خام)',
        '',
        1,
        _a,
        text: (d) =>
            d.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' '),
      );
}

double _a(List<int> d) => d[0].toDouble();
double _ab(List<int> d) => (d[0] * 256 + d[1]).toDouble();
double _pct(List<int> d) => d[0] * 100 / 255;
double _temp(List<int> d) => d[0] - 40.0;
double _trim(List<int> d) => (d[0] - 128) * 100 / 128;
double _lambda(List<int> d) => _ab(d) * 2 / 65536;
double _catTemp(List<int> d) => _ab(d) / 10 - 40;
double _o2v(List<int> d) => d[0] / 200;
double _torque(List<int> d) => d[0] - 125.0;

String _fuelSystem(List<int> d) => switch (d[0]) {
      1 => 'Open loop (المحرك بارد)',
      2 => 'Closed loop (طبيعي)',
      4 => 'Open loop (حمل / فرملة بالموتور)',
      8 => 'Open loop (عطل)',
      16 => 'Closed loop (فيه عطل في حساس)',
      _ => 'كود ${d[0]}',
    };

String _obdStandard(List<int> d) => switch (d[0]) {
      1 => 'OBD-II (CARB)',
      2 => 'OBD (EPA)',
      3 => 'OBD + OBD-II',
      4 => 'OBD-I',
      5 => 'غير متوافق مع OBD',
      6 => 'EOBD (أوروبي)',
      7 => 'EOBD + OBD-II',
      8 => 'EOBD + OBD',
      9 => 'EOBD + OBD + OBD-II',
      10 => 'JOBD (ياباني)',
      11 => 'JOBD + OBD-II',
      12 => 'JOBD + EOBD',
      13 => 'JOBD + EOBD + OBD-II',
      _ => 'كود ${d[0]}',
    };

String _fuelType(List<int> d) => switch (d[0]) {
      1 => 'بنزين',
      2 => 'ميثانول',
      3 => 'إيثانول',
      4 => 'ديزل',
      5 => 'غاز LPG',
      6 => 'غاز طبيعي CNG',
      8 => 'كهرباء',
      9 => 'بنزين/غاز (Bifuel)',
      17 => 'هايبرد بنزين',
      19 => 'هايبرد ديزل',
      20 => 'هايبرد كهرباء',
      _ => 'كود ${d[0]}',
    };

String _monitorStatus(List<int> d) {
  final mil = d[0] & 0x80 != 0 ? 'شغالة' : 'مطفية';
  return 'لمبة الأعطال $mil • ${d[0] & 0x7F} كود';
}

String _o2Present(List<int> d) {
  final bits = <String>[];
  for (var i = 0; i < 8; i++) {
    if (d[0] & (1 << i) != 0) bits.add('B${i ~/ 4 + 1}S${i % 4 + 1}');
  }
  return bits.isEmpty ? 'لا يوجد' : bits.join(' ');
}

String _gear(List<int> d) {
  if (d.length < 2 || d[0] & 0x02 == 0) return 'غير متاح';
  final g = d[1] >> 4;
  return g == 0 ? 'N / P' : 'الغيار $g';
}

int _s16(List<int> d) {
  final v = d[0] * 256 + d[1];
  return v >= 32768 ? v - 65536 : v;
}

class Pids {
  static const status = 0x01;
  static const load = 0x04;
  static const coolant = 0x05;
  static const stft1 = 0x06;
  static const ltft1 = 0x07;
  static const map = 0x0B;
  static const rpm = 0x0C;
  static const speed = 0x0D;
  static const iat = 0x0F;
  static const maf = 0x10;
  static const throttle = 0x11;
  static const fuelLevel = 0x2F;
  static const voltage = 0x42;
  static const ambient = 0x46;
  static const oilTemp = 0x5C;
  static const fuelRate = 0x5E;
  static const odometer = 0xA6;

  static final List<PidDef> all = [
    // --- status ---
    PidDef(status, 'حالة لمبة الأعطال', '', 4,
        (d) => (d[0] & 0x7F).toDouble(),
        text: _monitorStatus),
    PidDef(0x03, 'حالة نظام البنزين', '', 2, _a, text: _fuelSystem),
    PidDef(0x1C, 'معيار OBD في العربية', '', 1, _a, text: _obdStandard),
    PidDef(0x51, 'نوع الوقود', '', 1, _a, text: _fuelType),
    PidDef(0x13, 'حساسات الأكسجين الموجودة', '', 1, _a, text: _o2Present),

    // --- engine ---
    PidDef(rpm, 'سرعة المحرك', 'RPM', 2, (d) => _ab(d) / 4),
    PidDef(speed, 'السرعة', 'km/h', 1, _a),
    PidDef(load, 'حمل المحرك', '%', 1, _pct),
    PidDef(0x43, 'الحمل المطلق', '%', 2, (d) => _ab(d) * 100 / 255),
    PidDef(0x0E, 'توقيت الإشعال', '°', 1, (d) => d[0] / 2 - 64, decimals: 1),
    PidDef(0x1F, 'مدة تشغيل المحرك', 's', 2, _ab),
    PidDef(0x61, 'العزم المطلوب', '%', 1, _torque),
    PidDef(0x62, 'العزم الفعلي', '%', 1, _torque),
    PidDef(0x63, 'العزم المرجعي', 'Nm', 2, _ab),
    PidDef(0x8E, 'عزم الاحتكاك', '%', 1, _torque),
    PidDef(0xA4, 'الغيار الحالي', '', 2, _a, text: _gear),

    // --- temperatures ---
    PidDef(coolant, 'حرارة المياه', '°C', 1, _temp),
    PidDef(0x67, 'حرارة المياه (حساس 1)', '°C', 3, (d) => d[1] - 40.0),
    PidDef(iat, 'حرارة الهواء الداخل', '°C', 1, _temp),
    PidDef(0x68, 'حرارة الهواء الداخل (حساس 1)', '°C', 3, (d) => d[1] - 40.0),
    PidDef(ambient, 'حرارة الجو', '°C', 1, _temp),
    PidDef(oilTemp, 'حرارة الزيت', '°C', 1, _temp),
    PidDef(0x3C, 'حرارة الكتاليست B1S1', '°C', 2, _catTemp),
    PidDef(0x3D, 'حرارة الكتاليست B2S1', '°C', 2, _catTemp),
    PidDef(0x3E, 'حرارة الكتاليست B1S2', '°C', 2, _catTemp),
    PidDef(0x3F, 'حرارة الكتاليست B2S2', '°C', 2, _catTemp),

    // --- air / throttle ---
    PidDef(map, 'ضغط المنفولد (MAP)', 'kPa', 1, _a),
    PidDef(0x33, 'الضغط الجوي', 'kPa', 1, _a),
    PidDef(maf, 'كمية الهواء (MAF)', 'g/s', 2, (d) => _ab(d) / 100, decimals: 2),
    PidDef(0x50, 'أقصى قيمة MAF', 'g/s', 4, (d) => d[0] * 10.0),
    PidDef(throttle, 'فتحة البوابة (Throttle)', '%', 1, _pct),
    PidDef(0x45, 'فتحة البوابة النسبية', '%', 1, _pct),
    PidDef(0x47, 'فتحة البوابة B', '%', 1, _pct),
    PidDef(0x48, 'فتحة البوابة C', '%', 1, _pct),
    PidDef(0x4C, 'البوابة المطلوبة', '%', 1, _pct),
    PidDef(0x49, 'دواسة البنزين D', '%', 1, _pct),
    PidDef(0x4A, 'دواسة البنزين E', '%', 1, _pct),
    PidDef(0x4B, 'دواسة البنزين F', '%', 1, _pct),
    PidDef(0x5A, 'دواسة البنزين النسبية', '%', 1, _pct),

    // --- fuel ---
    PidDef(fuelLevel, 'مستوى البنزين', '%', 1, _pct),
    PidDef(fuelRate, 'معدل استهلاك البنزين', 'L/h', 2, (d) => _ab(d) / 20,
        decimals: 2),
    PidDef(stft1, 'تصحيح البنزين قصير المدى B1', '%', 1, _trim, decimals: 1),
    PidDef(ltft1, 'تصحيح البنزين طويل المدى B1', '%', 1, _trim, decimals: 1),
    PidDef(0x08, 'تصحيح البنزين قصير المدى B2', '%', 1, _trim, decimals: 1),
    PidDef(0x09, 'تصحيح البنزين طويل المدى B2', '%', 1, _trim, decimals: 1),
    PidDef(0x55, 'تصحيح حساس O2 الثانوي قصير B1', '%', 2, _trim, decimals: 1),
    PidDef(0x56, 'تصحيح حساس O2 الثانوي طويل B1', '%', 2, _trim, decimals: 1),
    PidDef(0x0A, 'ضغط البنزين', 'kPa', 1, (d) => d[0] * 3.0),
    PidDef(0x22, 'ضغط الريل (نسبي)', 'kPa', 2, (d) => _ab(d) * 0.079,
        decimals: 1),
    PidDef(0x23, 'ضغط الريل', 'kPa', 2, (d) => _ab(d) * 10),
    PidDef(0x59, 'ضغط الريل المطلق', 'kPa', 2, (d) => _ab(d) * 10),
    PidDef(0x5D, 'توقيت الحقن', '°', 2, (d) => _ab(d) / 128 - 210,
        decimals: 1),
    PidDef(0x44, 'Lambda المطلوبة', 'λ', 2, _lambda, decimals: 3),
    PidDef(0x52, 'نسبة الإيثانول', '%', 1, _pct),

    // --- emissions ---
    PidDef(0x2C, 'EGR المطلوب', '%', 1, _pct),
    PidDef(0x2D, 'خطأ EGR', '%', 1, _trim, decimals: 1),
    PidDef(0x2E, 'تنقية بخار البنزين (EVAP)', '%', 1, _pct),
    PidDef(0x32, 'ضغط بخار EVAP', 'Pa', 2, (d) => _s16(d) / 4, decimals: 1),
    PidDef(0x53, 'ضغط EVAP المطلق', 'kPa', 2, (d) => _ab(d) / 200,
        decimals: 2),

    // --- oxygen sensors (narrow band) ---
    for (var i = 0; i < 8; i++)
      PidDef(0x14 + i, 'حساس الأكسجين ${i + 1} (فولت)', 'V', 2, _o2v,
          decimals: 3),
    // --- oxygen sensors (wide band) ---
    for (var i = 0; i < 8; i++)
      PidDef(0x24 + i, 'حساس الأكسجين ${i + 1} (Lambda)', 'λ', 4, _lambda,
          decimals: 3),
    for (var i = 0; i < 8; i++)
      PidDef(0x34 + i, 'حساس الأكسجين ${i + 1} (تيار)', 'mA', 4,
          (d) => (d[2] * 256 + d[3]) / 256 - 128,
          decimals: 2),

    // --- electrical / distance / time ---
    PidDef(voltage, 'فولت البطارية', 'V', 2, (d) => _ab(d) / 1000, decimals: 2),
    PidDef(0x5B, 'بطارية الهايبرد', '%', 1, _pct),
    PidDef(odometer, 'العداد', 'km', 4,
        (d) => (d[0] * 16777216 + d[1] * 65536 + d[2] * 256 + d[3]) / 10,
        decimals: 1),
    PidDef(0x21, 'مسافة مع لمبة الأعطال', 'km', 2, _ab),
    PidDef(0x31, 'مسافة من مسح الأعطال', 'km', 2, _ab),
    PidDef(0x30, 'مرات التسخين من مسح الأعطال', '', 1, _a),
    PidDef(0x4D, 'وقت التشغيل مع لمبة الأعطال', 'min', 2, _ab),
    PidDef(0x4E, 'وقت من مسح الأعطال', 'min', 2, _ab),
    PidDef(0x7F, 'إجمالي وقت تشغيل المحرك', 's', 13,
        (d) => (d[1] * 16777216 + d[2] * 65536 + d[3] * 256 + d[4]).toDouble()),
  ];

  static final Map<int, PidDef> byId = {for (final p in all) p.pid: p};
}
