/// Mode 01 PID definitions (SAE J1979). A, B, C, D = data bytes.
class PidDef {
  final int pid;
  final String name;
  final String unit;
  final int bytes;
  final double Function(List<int> d) decode;
  final int decimals;

  const PidDef(this.pid, this.name, this.unit, this.bytes, this.decode,
      {this.decimals = 0});

  String get hex => '01${pid.toRadixString(16).padLeft(2, '0').toUpperCase()}';
}

double _a(List<int> d) => d[0].toDouble();
double _ab(List<int> d) => (d[0] * 256 + d[1]).toDouble();
double _pct(List<int> d) => d[0] * 100 / 255;
double _temp(List<int> d) => d[0] - 40.0;
double _trim(List<int> d) => (d[0] - 128) * 100 / 128;

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
    PidDef(status, 'عدد الأعطال المخزنة', '', 4, (d) => (d[0] & 0x7F).toDouble()),
    PidDef(load, 'حمل المحرك', '%', 1, _pct),
    PidDef(coolant, 'حرارة المياه', '°C', 1, _temp),
    PidDef(stft1, 'تصحيح البنزين قصير المدى', '%', 1, _trim, decimals: 1),
    PidDef(ltft1, 'تصحيح البنزين طويل المدى', '%', 1, _trim, decimals: 1),
    PidDef(0x0A, 'ضغط البنزين', 'kPa', 1, (d) => d[0] * 3.0),
    PidDef(map, 'ضغط المنفولد (MAP)', 'kPa', 1, _a),
    PidDef(rpm, 'سرعة المحرك', 'RPM', 2, (d) => _ab(d) / 4),
    PidDef(speed, 'السرعة', 'km/h', 1, _a),
    PidDef(0x0E, 'توقيت الإشعال', '°', 1, (d) => d[0] / 2 - 64, decimals: 1),
    PidDef(iat, 'حرارة الهواء الداخل', '°C', 1, _temp),
    PidDef(maf, 'كمية الهواء (MAF)', 'g/s', 2, (d) => _ab(d) / 100, decimals: 2),
    PidDef(throttle, 'فتحة البوابة (Throttle)', '%', 1, _pct),
    PidDef(0x14, 'حساس الأكسجين 1', 'V', 2, (d) => d[0] / 200, decimals: 3),
    PidDef(0x15, 'حساس الأكسجين 2', 'V', 2, (d) => d[0] / 200, decimals: 3),
    PidDef(0x1F, 'مدة تشغيل المحرك', 's', 2, _ab),
    PidDef(0x21, 'مسافة مع لمبة الأعطال', 'km', 2, _ab),
    PidDef(0x2C, 'EGR المطلوب', '%', 1, _pct),
    PidDef(0x2E, 'تنقية بخار البنزين (EVAP)', '%', 1, _pct),
    PidDef(fuelLevel, 'مستوى البنزين', '%', 1, _pct),
    PidDef(0x30, 'مرات التسخين من مسح الأعطال', '', 1, _a),
    PidDef(0x31, 'مسافة من مسح الأعطال', 'km', 2, _ab),
    PidDef(0x33, 'الضغط الجوي', 'kPa', 1, _a),
    PidDef(0x3C, 'حرارة الشكمان (كتاليست)', '°C', 2, (d) => _ab(d) / 10 - 40),
    PidDef(voltage, 'فولت البطارية', 'V', 2, (d) => _ab(d) / 1000, decimals: 2),
    PidDef(0x43, 'الحمل المطلق', '%', 2, (d) => _ab(d) * 100 / 255),
    PidDef(0x44, 'Lambda المطلوبة', 'λ', 2, (d) => _ab(d) * 2 / 65536, decimals: 3),
    PidDef(0x45, 'فتحة البوابة النسبية', '%', 1, _pct),
    PidDef(ambient, 'حرارة الجو', '°C', 1, _temp),
    PidDef(0x47, 'فتحة البوابة B', '%', 1, _pct),
    PidDef(0x49, 'دواسة البنزين D', '%', 1, _pct),
    PidDef(0x4A, 'دواسة البنزين E', '%', 1, _pct),
    PidDef(0x4C, 'البوابة المطلوبة', '%', 1, _pct),
    PidDef(0x4D, 'وقت التشغيل مع لمبة الأعطال', 'min', 2, _ab),
    PidDef(0x4E, 'وقت من مسح الأعطال', 'min', 2, _ab),
    PidDef(oilTemp, 'حرارة الزيت', '°C', 1, _temp),
    PidDef(fuelRate, 'معدل استهلاك البنزين', 'L/h', 2, (d) => _ab(d) / 20, decimals: 2),
    PidDef(odometer, 'العداد', 'km', 4,
        (d) => (d[0] * 16777216 + d[1] * 65536 + d[2] * 256 + d[3]) / 10),
  ];

  static final Map<int, PidDef> byId = {for (final p in all) p.pid: p};
}
