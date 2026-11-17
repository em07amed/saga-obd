/// Minimal Arabic/English localisation.
///
/// The UI is written in Arabic; [tr] translates a finished Arabic string to
/// English by replacing known phrases (longest first). That lets one helper
/// handle both plain literals and interpolated ones like '12 كم • 3 لتر'.
class Lang {
  /// 'ar' or 'en'. Set from settings at startup and when the user switches.
  static String code = 'ar';
  static bool get isEn => code == 'en';
}

String tr(String s) {
  if (!Lang.isEn || !_arabic.hasMatch(s)) return s;
  var out = s;
  for (final (re, en) in _compiled) {
    if (!_arabic.hasMatch(out)) break;
    out = out.replaceAll(re, en);
  }
  return out.replaceAll('،', ',').replaceAll('؟', '?');
}

final _arabic = RegExp(r'[؀-ۿ]');

// Phrases are matched only when not glued to other Arabic letters, so a
// short token like 'كم' never eats part of a longer word.
final List<(RegExp, String)> _compiled = (() {
  final keys = _en.keys.toList()..sort((a, b) => b.length.compareTo(a.length));
  return [
    for (final k in keys)
      (
        RegExp('(?<![\\u0621-\\u064A])${RegExp.escape(k)}(?![\\u0621-\\u064A])'),
        _en[k]!,
      ),
  ];
})();

const Map<String, String> _en = {
  // ---- navigation / common ----
  'الداشبورد': 'Dashboard',
  'القراءات': 'Readings',
  'الرحلات': 'Trips',
  'الصيانة': 'Maintenance',
  'الإعدادات': 'Settings',
  'وضع القيادة': 'Drive mode',
  'حفظ': 'Save',
  'إلغاء': 'Cancel',
  'حذف': 'Delete',
  'تعديل': 'Edit',
  'تحديث': 'Update',
  'إدخال': 'Enter',
  'خروج': 'Exit',
  'احسب': 'Calculate',
  'امسح': 'Clear',
  'اتنسخت': 'Copied',
  'نسخ النتيجة': 'Copy result',
  'مش مدعوم': 'Not supported',
  'غير متاح': 'N/A',
  'لا يوجد': 'None',
  '(فاضي)': '(empty)',

  // ---- connection ----
  'متصل': 'Connected',
  'غير متصل': 'Disconnected',
  'اتصال': 'Connect',
  'فصل': 'Disconnect',
  'انقطع الاتصال': 'Connection lost',
  'تهيئة الجهاز…': 'Initialising adapter…',
  'جاري الاتصال بـ': 'Connecting to',
  'فشل الاتصال:': 'Connection failed:',
  'صلاحية ناقصة:': 'Missing permission:',
  'الـ Bluetooth مقفول': 'Bluetooth is off',
  'الجهاز مش بيرد. اتأكد إنه متركب والكونتاكت شغال':
      'Adapter not responding. Check it is plugged in and ignition is on',
  'العربية ما ردتش. اتأكد إن الكونتاكت شغال.':
      'The car did not answer. Make sure the ignition is on.',
  'اختار جهاز الـ OBD من الإعدادات': 'Choose the OBD adapter in Settings',
  'لازم توافق على صلاحية Bluetooth (الأجهزة القريبة)':
      'Please allow the Bluetooth (Nearby devices) permission',

  // ---- dashboard ----
  'السرعة': 'Speed',
  'حرارة المياه': 'Coolant temp',
  'البنزين': 'Fuel',
  'مستوى البنزين مش مدعوم': 'Fuel level not supported',
  'يكفي': 'range',
  'الاستهلاك اللحظي': 'Instant consumption',
  'الاستهلاك': 'Consumption',
  'من حساس الاستهلاك': 'From fuel-rate sensor',
  'محسوب من MAF': 'Calculated from MAF',
  'محسوب من': 'Calculated from',
  'العربية مش بتدعم قراءات الاستهلاك': 'Car does not report consumption data',
  'الرحلة الحالية': 'Current trip',
  'مفيش رحلة شغالة': 'No active trip',
  'هتبدأ لوحدها لما الموتور يدور': 'Starts automatically with the engine',
  'الرحلة': 'Trip',
  'البطارية': 'Battery',
  'البوابة / الحمل': 'Throttle / load',
  'حمل المحرك': 'Engine load',
  'حرارة الهواء الداخل': 'Intake air temp',
  'الجو': 'Outside',
  'العداد': 'Odometer',
  'اكتب رقم التابلوه من تاب الصيانة': 'Enter the dashboard reading in Maintenance',
  'من كمبيوتر العربية (بعد المعايرة) • لحظي': 'From the car ECU (calibrated) • live',
  'من كمبيوتر العربية • لحظي': 'From the car ECU • live',
  'من كمبيوتر العربية': 'From the car ECU',
  'تقريبي من كمبيوتر العربية • اضبطه من الصيانة':
      'Approx. from the car ECU • calibrate in Maintenance',
  'تقريبي من كمبيوتر العربية • دوس تحديث واكتب رقم التابلوه للدقة':
      'Approx. from the car ECU • tap Update and enter the dashboard reading',
  'تقديري • بيزيد مع الرحلات': 'Estimated • grows with trips',
  'تقديري: آخر قراءة + الرحلات المسجلة': 'Estimated: last reading + logged trips',
  'متوسط': 'avg',
  'لفة/د': 'rpm',

  // ---- units ----
  'كم/س': 'km/h',
  'ل/100كم': 'L/100km',
  'ل/100': 'L/100',
  'ل/ساعة': 'L/h',
  'كم': 'km',
  'لتر': 'L',
  'ج.م': 'EGP',
  'يوم': 'days',
  'د': 'min',
  'س': 'h',

  // ---- readings ----
  'قراءة مدعومة': 'supported readings',
  'بروتوكول': 'Protocol',
  'الأعطال': 'Trouble codes',
  'فحص العداد': 'Odometer check',
  'اتصل بالعربية عشان تظهر القراءات': 'Connect to the car to see readings',
  'رقم الشاسيه (VIN)': 'VIN',
  'خام': 'raw',

  // ---- trouble codes ----
  'أكواد الأعطال': 'Trouble codes',
  'مفيش أعطال مخزنة': 'No stored trouble codes',
  'مسح الأعطال؟': 'Clear trouble codes?',
  'مسح الأعطال': 'Clear codes',
  'هيتم مسح الأكواد ولمبة Check Engine، وكمان قراءات الـ readiness':
      'This clears the codes and the Check Engine light, and resets readiness monitors.',
  'هتتصفر. لو العطل لسه موجود هيرجع تاني. اعمل كده والموتور واقف':
      'If the fault is still present it will come back. Do this with the engine off',
  'والكونتاكت شغال.': 'and the ignition on.',
  'تم المسح': 'Cleared',
  'الكمبيوتر ما أكدش المسح': 'The ECU did not confirm',
  'محرك / فتيس': 'Engine / transmission',
  'شاسيه': 'Chassis',
  'بودي': 'Body',
  'شبكة': 'Network',
  'كود عام (SAE)': 'Generic code (SAE)',
  'كود خاص بالشركة': 'Manufacturer code',
  'ابحث عن الكود لمعرفة التفاصيل': 'look up the code for details',
  'كود': 'code',

  // ---- odometer probe ----
  'العربية ما ردتش بقراءة العداد بالطرق القياسية':
      'The car did not return the odometer via standard requests',
  'قارن الرقم بعداد التابلوه. لو مفيش نتيجة، انسخ الردود وابعتها.':
      'Compare with the dashboard. If nothing works, copy the replies and send them.',
  'PID 01A6 (العداد القياسي)': 'PID 01A6 (standard odometer)',
  'مسافة من مسح الأعطال (مش العداد)': 'Distance since codes cleared (not odometer)',

  // ---- trips ----
  'لسه مفيش رحلات مسجلة': 'No trips recorded yet',
  'الشهر ده': 'This month',
  'رحلة': 'trips',
  'متوسط الاستهلاك:': 'Avg consumption:',
  'حذف الرحلة؟': 'Delete trip?',
  'المسافة': 'Distance',
  'عداد OBD': 'OBD speed',
  'من عداد السرعة': 'From speed sensor',
  'المدة': 'Duration',
  'وقوف': 'Idle',
  'متوسط الاستهلاك': 'Avg consumption',
  'التكلفة': 'Cost',
  'سعر اللتر': 'Price/L',
  'حدد سعر اللتر من الإعدادات': 'Set the fuel price in Settings',
  'أقصى سرعة / حرارة': 'Top speed / temp',
  'أعلى حرارة مياه': 'Max coolant',
  'خط السير (ملون بالسرعة)': 'Route (coloured by speed)',
  'السرعة خلال الرحلة': 'Speed during trip',

  // ---- maintenance ----
  'صيانة جديدة': 'New service',
  'تعديل الصيانة': 'Edit service',
  'حذف الصيانة دي؟': 'Delete this service?',
  'المواعيد الجاية': 'Upcoming',
  'السجل': 'History',
  'إجمالي': 'Total',
  'لسه مفيش صيانات متسجلة': 'No services recorded yet',
  'اكتب رقم عداد التابلوه مرة واحدة': 'Enter the dashboard odometer once',
  'رقم العداد من التابلوه': 'Dashboard odometer',
  'فاضل': 'in',
  'متأخر': 'overdue by',
  'النوع': 'Type',
  'اكتب النوع': 'Type name',
  'التاريخ': 'Date',
  'العداد وقت الصيانة': 'Odometer at service',
  'ملاحظات': 'Notes',
  'نوع الزيت، المركز، القطعة…': 'Oil type, workshop, part…',
  'الميعاد الجاي (اختياري)': 'Next service (optional)',
  'بعد كام كيلو': 'After how many km',
  'حسب كتيب الصيانة أو كلام الميكانيكي': 'Per the service manual or your mechanic',
  'أو في تاريخ': 'Or on a date',
  'إلغاء التاريخ': 'Clear date',
  'تغيير زيت الموتور': 'Engine oil change',
  'فلتر زيت': 'Oil filter',
  'فلتر هواء': 'Air filter',
  'فلتر تكييف': 'Cabin filter',
  'فلتر بنزين': 'Fuel filter',
  'بوجيهات': 'Spark plugs',
  'تيل فرامل أمامي': 'Front brake pads',
  'تيل فرامل خلفي': 'Rear brake pads',
  'زيت فتيس': 'Transmission oil',
  'مياه الردياتير': 'Coolant',
  'سير الكاتينة': 'Timing belt',
  'بطارية': 'Battery',
  'كاوتش': 'Tyres',
  'ترصيص وضبط زوايا': 'Balancing & alignment',
  'أخرى': 'Other',

  // ---- settings ----
  'المظهر': 'Appearance',
  'تلقائي': 'System',
  'فاتح': 'Light',
  'داكن': 'Dark',
  'رياضي': 'Sport',
  'اللغة': 'Language',
  'جهاز الـ OBD': 'OBD adapter',
  'لم يتم الاختيار': 'Not selected',
  'اعمل Pair للجهاز من إعدادات Bluetooth في الموبايل الأول':
      'Pair the adapter in your phone Bluetooth settings first',
  'اتصال تلقائي عند فتح التطبيق': 'Auto-connect on app start',
  'الأجهزة المقترنة': 'Paired devices',
  'جهاز ELM327 غالباً اسمه OBDII أو V-LINK':
      'An ELM327 is usually named OBDII or V-LINK',
  'مفيش أجهزة. اعمل Pair الأول.': 'No devices. Pair one first.',
  'مش قادر أقرا الأجهزة:': "Can't read devices:",
  'العربيات': 'Vehicles',
  'إضافة عربية': 'Add vehicle',
  'بيانات': 'Specs —',
  'سعة التانك': 'Tank capacity',
  'سعة الموتور': 'Engine size',
  'الكفاءة الحجمية (VE)': 'Volumetric efficiency (VE)',
  'بتستخدم بس لو العربية مفيهاش حساس MAF. عايرها من تفويلة حقيقية.':
      'Used only when the car has no MAF sensor. Calibrate from a real fill-up.',
  'معايرة الاستهلاك من تفويلة': 'Calibrate consumption from a fill-up',
  'قارن اللترات اللي فوّلتها باللي التطبيق حسبه':
      'Compare litres pumped with what the app computed',
  'متوسط استهلاك افتراضي (لحساب المسافة المتبقية)':
      'Default consumption (for range)',
  'سعر لتر البنزين': 'Fuel price per litre',
  'السعر الرسمي بيتحط تلقائي لما تختار النوع. لو اتغير عدّله من هنا؛ كل رحلة بتتسجل بالسعر وقت بدايتها.':
      'The official price is set when you pick a grade. Edit it if it changes; each trip keeps the price at its start.',
  'نوع البنزين': 'Fuel grade',
  'بنزين': 'Gasoline',
  'معايرة الـ VE': 'VE calibration',
  'فوّل التانك فُل، امشي مشوار طويل، وفوّل فُل تاني.':
      'Fill the tank, drive a long distance, then fill up again.',
  'اكتب اللترات الحقيقية من البنزينة، وإجمالي لترات الرحلات':
      'Enter the litres pumped and the total trip litres',
  'اللي بين التفويلتين من التطبيق.': 'between the two fill-ups from the app.',
  'لترات البنزينة': 'Litres pumped',
  'لترات التطبيق': 'App litres',
  'الـ VE الجديدة:': 'New VE:',

  // ---- vehicle editor ----
  'عربية جديدة': 'New vehicle',
  'تعديل العربية': 'Edit vehicle',
  'الماركة': 'Make',
  'الموديل': 'Model',
  'سنة الصنع': 'Year',
  'اسم تعرفها بيه (اختياري)': 'Nickname (optional)',
  'مثلاً: Hyundai، Toyota': 'e.g. Hyundai, Toyota',
  'مثلاً: Elantra، Corolla': 'e.g. Elantra, Corolla',
  'مثلاً: عربية البيت': 'e.g. Family car',
  'مثلاً 1.6 لموتور 1600 سي سي': 'e.g. 1.6 for a 1600 cc engine',
  'اكتب سعة التانك وسعة الموتور (من كتيب العربية)':
      "Enter tank and engine size (from the owner's manual)",
  'هيتمسح معاها كل الرحلات وسجل الصيانة بتاعها.':
      'All its trips and service history will be deleted too.',
  'عربيتي': 'My car',

  // ---- PIDs ----
  'حالة لمبة الأعطال': 'Check-engine status',
  'لمبة الأعطال': 'Check-engine light',
  'شغالة': 'ON',
  'مطفية': 'OFF',
  'حالة نظام البنزين': 'Fuel system status',
  'طبيعي': 'normal',
  'فيه عطل في حساس': 'sensor fault',
  'المحرك بارد': 'engine cold',
  'حمل / فرملة بالموتور': 'load / engine braking',
  'عطل': 'fault',
  'معيار OBD في العربية': 'OBD standard',
  'أوروبي': 'European',
  'ياباني': 'Japanese',
  'غير متوافق مع OBD': 'Not OBD compliant',
  'نوع الوقود': 'Fuel type',
  'ميثانول': 'Methanol',
  'إيثانول': 'Ethanol',
  'ديزل': 'Diesel',
  'غاز LPG': 'LPG',
  'غاز طبيعي CNG': 'CNG',
  'كهرباء': 'Electric',
  'بنزين/غاز (Bifuel)': 'Bifuel',
  'هايبرد بنزين': 'Hybrid gasoline',
  'هايبرد ديزل': 'Hybrid diesel',
  'هايبرد كهرباء': 'Hybrid electric',
  'حساسات الأكسجين الموجودة': 'O2 sensors present',
  'سرعة المحرك': 'Engine speed',
  'الحمل المطلق': 'Absolute load',
  'توقيت الإشعال': 'Ignition timing',
  'مدة تشغيل المحرك': 'Run time since start',
  'العزم المطلوب': 'Demanded torque',
  'العزم الفعلي': 'Actual torque',
  'العزم المرجعي': 'Reference torque',
  'عزم الاحتكاك': 'Friction torque',
  'الغيار الحالي': 'Current gear',
  'الغيار': 'Gear',
  'حساس': 'sensor',
  'حرارة الجو': 'Ambient temp',
  'حرارة الزيت': 'Oil temp',
  'حرارة الكتاليست': 'Catalyst temp',
  'ضغط المنفولد (MAP)': 'Manifold pressure (MAP)',
  'الضغط الجوي': 'Barometric pressure',
  'كمية الهواء (MAF)': 'Air flow (MAF)',
  'أقصى قيمة MAF': 'Max MAF',
  'فتحة البوابة (Throttle)': 'Throttle position',
  'فتحة البوابة النسبية': 'Relative throttle',
  'فتحة البوابة': 'Throttle',
  'البوابة المطلوبة': 'Commanded throttle',
  'دواسة البنزين النسبية': 'Relative pedal',
  'دواسة البنزين': 'Accelerator pedal',
  'مستوى البنزين': 'Fuel level',
  'معدل استهلاك البنزين': 'Fuel rate',
  'تصحيح البنزين قصير المدى': 'Short-term fuel trim',
  'تصحيح البنزين طويل المدى': 'Long-term fuel trim',
  'تصحيح حساس O2 الثانوي قصير': 'Secondary O2 short trim',
  'تصحيح حساس O2 الثانوي طويل': 'Secondary O2 long trim',
  'ضغط البنزين': 'Fuel pressure',
  'ضغط الريل (نسبي)': 'Fuel rail pressure (rel.)',
  'ضغط الريل المطلق': 'Fuel rail pressure (abs.)',
  'ضغط الريل': 'Fuel rail pressure',
  'توقيت الحقن': 'Injection timing',
  'Lambda المطلوبة': 'Commanded lambda',
  'نسبة الإيثانول': 'Ethanol %',
  'EGR المطلوب': 'Commanded EGR',
  'خطأ EGR': 'EGR error',
  'تنقية بخار البنزين (EVAP)': 'EVAP purge',
  'ضغط بخار EVAP': 'EVAP vapour pressure',
  'ضغط EVAP المطلق': 'EVAP absolute pressure',
  'حساس الأكسجين': 'O2 sensor',
  'تيار': 'current',
  'فولت': 'voltage',
  'فولت البطارية': 'Battery voltage',
  'بطارية الهايبرد': 'Hybrid battery',
  'مسافة مع لمبة الأعطال': 'Distance with MIL on',
  'مسافة من مسح الأعطال': 'Distance since codes cleared',
  'مرات التسخين من مسح الأعطال': 'Warm-ups since codes cleared',
  'وقت التشغيل مع لمبة الأعطال': 'Run time with MIL on',
  'وقت من مسح الأعطال': 'Time since codes cleared',
  'إجمالي وقت تشغيل المحرك': 'Total engine run time',
  'بروتون ساجا': 'Proton Saga',

  // ---- fuel log / background ----
  'سجل البنزين': 'Fuel log',
  'فوّلت التانك فُل': 'Filled the tank to full',
  'فوّلت': 'Fill-up',
  'في التانك': 'In tank',
  'سجّل تفويلة فُل عشان يبدأ الحساب': 'Log a full fill-up to start tracking',
  'من حساس العربية': 'From the car sensor',
  'تقديري من آخر تفويلة': 'Estimated from last fill-up',
  'دوس هنا وسجّل تفويلة': 'Tap to log a fill-up',
  'تقديري': 'Estimated',
  'على': 'at',
  'الاستهلاك الحقيقي': 'Real consumption',
  'من آخر تفويلات فُل': 'From recent full fill-ups',
  'معايرة الاستهلاك': 'Consumption calibration',
  'التطبيق حاسب أقل من البنزينة.': 'The app computed less than the pump.',
  'التطبيق حاسب أكتر من البنزينة.': 'The app computed more than the pump.',
  'الـ VE المقترحة': 'Suggested VE',
  'طبّق': 'Apply',
  'التفويلات': 'Fill-ups',
  'لسه مفيش تفويلات. فوّل التانك فُل ودوس «فوّلت».':
      'No fill-ups yet. Fill the tank and tap “Fill-up”.',
  'فُل': 'full',
  'جزئي': 'partial',
  'اللترات': 'Litres',
  'المبلغ': 'Amount',
  'بيسجّل الرحلة والقراءات': 'Recording trip and readings',

  // ---- alerts ----
  'حرارة الموتور عالية': 'Engine temperature high',
  'اركن وطفي التكييف.': 'Pull over and turn off the A/C.',
  'مشكلة في الشحن': 'Charging problem',
  'والموتور شغال. افحص الدينامو.': 'with the engine running. Check the alternator.',
  'فولت عالي': 'High voltage',
  'افحص منظم الدينامو.': 'Check the alternator regulator.',
  'عطل جديد': 'New trouble code',
  'الكمبيوتر سجّل': 'The ECU stored',
  'افتح القراءات ← الأعطال.': 'Open Readings → Trouble codes.',
  'ميعاد صيانة': 'Service due',
  'قرّب': 'due soon',
  'فات ميعاده': 'past due',
  'تنبيهات وإنت سايق': 'Driving alerts',
  'الحرارة، الشحن، الأعطال، مواعيد الصيانة': 'Temperature, charging, trouble codes, services',
  'تنبيه الحرارة عند': 'Coolant alert at',
  'الطبيعي 105. خليه أقل عشان تجرّب التنبيه.': 'Normal is 105. Set lower to test the alert.',
};
