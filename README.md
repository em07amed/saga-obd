# Saga OBD — Flutter (Android)

داشبورد مباشر + كل قراءات OBD2 المدعومة + البنزين والاستهلاك + أكواد الأعطال + تسجيل الرحلات.
معمول لـ Proton Saga 1.3 VVT مع جهاز ELM327 Bluetooth (Classic SPP)، وبيشتغل مع أي عربية OBD2.

## التشغيل

الملفات دي هي `lib/` وملفات Android اللي اتغيرت، فاعمل المشروع الأساسي بـ `flutter create` الأول:

```bash
flutter create --org com.ezzat --platforms android obd_saga
# انسخ محتويات الـ zip فوق المشروع (overwrite):
#   pubspec.yaml, lib/, test/, android/app/src/main/AndroidManifest.xml,
#   android/app/src/main/kotlin/com/ezzat/obd_saga/MainActivity.kt
cd obd_saga
flutter pub get
flutter test        # اختبارات الـ decoders والاستهلاك
flutter run         # على موبايل Android حقيقي (الـ emulator مفيهوش Bluetooth)
```

> مهم: لو استخدمت `--org` أو اسم مشروع غير اللي فوق، غيّر الـ `package` في `MainActivity.kt` ومساره.

## أول استخدام
1. اعمل **Pair** لجهاز الـ OBD من إعدادات Bluetooth في الموبايل (PIN غالباً `1234` أو `0000`).
2. افتح التطبيق ← الإعدادات ← اختار الجهاز. نوع البنزين الافتراضي **95 بسعر 24 ج.م/لتر** (تقدر تغيّره).
3. دوّر العربية، واضغط **اتصال**.

## الهيكل
```
lib/
  main.dart                 تهيئة + التابات + صلاحيات + إبقاء الشاشة شغالة
  settings.dart             الإعدادات (تانك 40 لتر، موتور 1.332، VE، نوع وسعر البنزين)
  obd/
    bt_channel.dart         Dart ↔ Kotlin (RFCOMM)
    elm327.dart             طابور أوامر واحد + parsing الردود
    pids.dart               تعريف ~38 PID بالمعادلات
    fuel.dart               الاستهلاك: 015E ← MAF ← MAP (speed-density) + fuel trims
    obd_service.dart        الاتصال، اكتشاف الـ PIDs المدعومة، الـ polling، الأعطال
  trips/
    trip_db.dart            sqflite: trips + samples
    trip_recorder.dart      بدء/إنهاء تلقائي، مسافة OBD + GPS، بنزين، تكلفة
  ui/                       الداشبورد، القراءات، الأعطال، الرحلات، الإعدادات
android/app/src/main/kotlin/.../MainActivity.kt   Bluetooth SPP bridge
```

## إزاي بيشتغل
- **الـ polling:** كل دورة بتقرا RPM والسرعة ومدخلات الاستهلاك، وبعدين قراءة من القراءات البطيئة بالدور، وقراءة من (حرارة المياه / البنزين / حرارة الهوا / البوابة). طلب واحد في المرة عشان الأجهزة الـ clone.
- **الاستهلاك:** لو العربية مفيهاش MAF بيتحسب من MAP وIAT وRPM والـ VE. عاير الـ VE من الإعدادات بعد تفويلتين فُل.
- **الرحلات:** بتبدأ لما الـ RPM يعدي 300، وبتخلص بعد 90 ثانية من وقوف الموتور أو فصل الجهاز. الرحلات اللي أقل من 100 متر بتتحذف. العينات بتتسجل كل ثانية وبتتحفظ كل 5 ثواني.

## حدود النسخة دي
- التسجيل شغال **والتطبيق مفتوح** (الشاشة بتفضل شغالة طول ما هو متصل)، ومناسب لو الموبايل متركب على حامل. التسجيل في الخلفية محتاج Foreground Service، وده الخطوة الجاية.
- أكواد ABS والإيرباج والفتيس محتاجة بروتوكولات خاصة ببروتون، ومش موجودة هنا.
- Android بس، لأن iPhone ما بيدعمش Bluetooth Classic.
