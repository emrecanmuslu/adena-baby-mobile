import 'package:flutter/material.dart';

/// Onaylanmış sıcak/mercan palet — design/AdenaBaby/adena.css ile birebir.
/// Marka/kategori renkleri her iki temada sabit; semantik nötrler (ink/muted/
/// line/peach/cream) tasarımın "Gece Modu"na göre [brightness]'a duyarlıdır.
class AppColors {
  static const coral = Color(0xFFFF8A7A);
  static const coralDark = Color(0xFFF2705E);
  static const coralDd = Color(0xFFE2553F);

  // ── Tema-duyarlı semantik nötrler (design force-dark değişkenleri) ──
  /// Uygulama kökünde (main) etkin temaya göre set edilir.
  static Brightness brightness = Brightness.light;
  static bool get _d => brightness == Brightness.dark;

  static Color get peach => _d ? const Color(0xFF3E2C3C) : const Color(0xFFFFD4C2);
  static Color get peachLight => _d ? const Color(0xFF33283A) : const Color(0xFFFFE9DF);
  static Color get cream => _d ? const Color(0xFF191320) : const Color(0xFFFFF8F4);
  static Color get cream2 => _d ? const Color(0xFF221A2A) : const Color(0xFFFFF1E9);
  static Color get ink => _d ? const Color(0xFFF2E8E3) : const Color(0xFF3D2B26);
  static Color get ink2 => _d ? const Color(0xFFD8C9C2) : const Color(0xFF6E574F);
  static Color get muted => _d ? const Color(0xFF9F92A2) : const Color(0xFFA08C83);
  static Color get muted2 => _d ? const Color(0xFF766C7C) : const Color(0xFFC3B2A9);
  static Color get line => _d ? const Color(0xFF352B40) : const Color(0xFFF4E7DF);
  static Color get line2 => _d ? const Color(0xFF403349) : const Color(0xFFECDACF);

  // Takip türü kategori renkleri (adena.css "category tones")
  static const diaper = Color(0xFFE0A53C);
  static const feed = coral;
  static const sleep = Color(0xFF9B8CE8);
  static const pump = Color(0xFF34B5B6);
  static const growth = Color(0xFF52BA8E);
  static const fever = Color(0xFFF2705E);
  static const med = Color(0xFFCC7A5C); // terrakota/kil — sıcak palete uyumlu (aşı/randevu/ilaç)
  static const bath = Color(0xFF5FB6E8);
  static const doctor = Color(0xFF9A86D6);
  static const symptom = Color(0xFFD98AA6); // gül/erik — belirti/hastalık takibi (fever'dan ayrı)

  // Kategori arka plan tonları (chip zeminleri)
  // Kategori chip zeminleri — tema-duyarlı (tasarım Gece Modu *-bg değerleri).
  static Color get feedBg => _d ? const Color(0xFF3A2A2C) : const Color(0xFFFFE7E1);
  static Color get diaperBg => _d ? const Color(0xFF352D1F) : const Color(0xFFFBF0D5);
  static Color get sleepBg => _d ? const Color(0xFF2C2740) : const Color(0xFFECE9FB);
  static Color get pumpBg => _d ? const Color(0xFF1F3334) : const Color(0xFFDBF3F3);
  static Color get growthBg => _d ? const Color(0xFF1E3329) : const Color(0xFFDBF2E8);
  static Color get feverBg => _d ? const Color(0xFF3A2622) : const Color(0xFFFBE3DE);
  static Color get medBg => _d ? const Color(0xFF352920) : const Color(0xFFF6E3D9); // terrakota
  static Color get bathBg => _d ? const Color(0xFF1E2E3A) : const Color(0xFFE0F0FB);
  static Color get doctorBg => _d ? const Color(0xFF2A2540) : const Color(0xFFEFEAF9);
  static Color get symptomBg => _d ? const Color(0xFF3A2630) : const Color(0xFFFBE3EC); // gül/erik zemin

  // ── Adet Takvimi modülü aksanı (gül/bordo + loşia) — tema-duyarlı.
  // Bebek cinsiyet temasından bağımsız; doğum sonrası anne modülüne özel.
  static Color get rose => _d ? const Color(0xFFD9799A) : const Color(0xFFC2576E);
  static Color get roseD => _d ? const Color(0xFFEBA0BA) : const Color(0xFFA33D58);
  static Color get roseBg => _d ? const Color(0xFF3C2032) : const Color(0xFFF8E4EC);
  static Color get lochia => _d ? const Color(0xFFC8907A) : const Color(0xFFB8755E);
  static Color get lochiaBg => _d ? const Color(0xFF3A2218) : const Color(0xFFF5E1D6);

  /// Yumuşak kart gölgesi (--sh).
  // Premium (altın) — paywall/AI export rozetleri.
  static const premiumGold = Color(0xFFFFC24B);
  static const premiumGoldLight = Color(0xFFFFE3A8);
  static const premiumInk = Color(0xFF8A6410);
  static const premiumBg = Color(0xFFFFF3DC);

  static const softShadow = [
    BoxShadow(color: Color(0x17E2553F), blurRadius: 18, offset: Offset(0, 6)),
    BoxShadow(color: Color(0x0D3D2B26), blurRadius: 4, offset: Offset(0, 1.5)),
  ];

  /// Küçük çip gölgesi (--sh-sm) — stepper butonları, küçük rozetler.
  static const smallShadow = [
    BoxShadow(color: Color(0x0D3D2B26), blurRadius: 2, offset: Offset(0, 1)),
    BoxShadow(color: Color(0x0A3D2B26), blurRadius: 3, offset: Offset(0, 1)),
  ];
}

class AppTheme {
  static const _radius = 22.0; // --r-card
  static const _radiusBtn = 13.0; // --r-sm (inputlar)

  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.coral,
      primary: AppColors.coral,
      brightness: Brightness.light,
      surface: Colors.white,
    );
    return _base(scheme,
        bg: const Color(0xFFFFF8F4),
        fg: const Color(0xFF3D2B26),
        line: const Color(0xFFF4E7DF),
        chipSel: const Color(0xFFFFD4C2));
  }

  static ThemeData get dark {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.coral,
      primary: AppColors.coral,
      brightness: Brightness.dark,
      surface: const Color(0xFF251D2E), // design dark --card
    );
    return _base(scheme,
        bg: const Color(0xFF191320), // design dark --bg
        fg: const Color(0xFFF2E8E3), // design dark --ink
        line: const Color(0xFF352B40), // design dark --line
        chipSel: const Color(0xFF3E2C3C)); // design dark --peach
  }

  // Tema kurulumunda sabit literaller (global getter'lara bağlı DEĞİL — her tema
  // kendi içinde tutarlı olsun diye).
  static ThemeData _base(ColorScheme scheme,
      {required Color bg,
      required Color fg,
      required Color line,
      required Color chipSel}) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      fontFamily: 'Nunito',
      textTheme: Typography.material2021().black.apply(
            bodyColor: fg,
            displayColor: fg,
          ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_radius)),
      ),
      // Seçili ChoiceChip'lerde zemin açık şeftali → check işareti her temada koyu mercan.
      chipTheme: ChipThemeData(
        selectedColor: chipSel,
        checkmarkColor: AppColors.coralDark,
        secondarySelectedColor: chipSel,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.coral,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: bg,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_radiusBtn),
          borderSide: BorderSide(color: line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_radiusBtn),
          borderSide: BorderSide(color: line),
        ),
      ),
    );
  }
}
