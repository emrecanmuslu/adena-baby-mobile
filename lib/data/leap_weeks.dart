/// Gelişim atağı ("atak haftası") verisi — bebek gelişimi biliminin genel
/// kabul gören 10 zihinsel/motor sıçrama dönemine dayanır; özgün içerik.
/// Gömülü tablo offline fallback'tir (TR); `LeapRepository` bunu API'den
/// çekilen/cache'lenen (locale'e göre) veriyle değiştirir.
class LeapInfo {
  final int index; // 1..10
  final int weekStart; // (düzeltilmiş) doğumdan itibaren yaklaşık hafta
  final String title;
  final String summary;
  final String body; // markdown
  final double fussyWeeksBefore;

  const LeapInfo({
    required this.index,
    required this.weekStart,
    required this.title,
    required this.summary,
    required this.body,
    required this.fussyWeeksBefore,
  });

  factory LeapInfo.fromApi(Map<String, dynamic> j) => LeapInfo(
        index: (j['index'] as num).toInt(),
        weekStart: (j['week_start'] as num).toInt(),
        title: j['title'] as String? ?? '',
        summary: j['summary'] as String? ?? '',
        body: j['body'] as String? ?? '',
        // DRF DecimalField JSON'da string olarak serialize edilir (ör. "1.0").
        fussyWeeksBefore: switch (j['fussy_weeks_before']) {
          num n => n.toDouble(),
          String s => double.tryParse(s) ?? 1,
          _ => 1,
        },
      );
}

/// Uygulamaya gömülü varsayılan (her zaman çalışır, internet gerektirmez) —
/// backend'deki `seed_leaps.py` ile aynı içerik (TR).
const List<LeapInfo> kEmbeddedLeaps = [
  LeapInfo(
    index: 1,
    weekStart: 5,
    title: 'Duyular Uyanıyor',
    summary: 'Bebeğinin duyuları netleşiyor, çevresini daha yoğun fark ediyor.',
    fussyWeeksBefore: 1,
    body:
        'Bu dönemde bebeğinin duyuları (görme, işitme, koku, dokunma) hızla gelişiyor ve dünyayı önceki haftalara göre çok daha yoğun algılıyor. Bu yoğunluk bazen bunaltıcı gelebilir — bu yüzden huzursuzluk, daha sık ağlama, uyku ve beslenme düzeninde dalgalanma görülebilir.\n\n'
        '## Bu dönemde neler olur?\n\n'
        '- Işığa, sese ve dokunuşa tepkisi artar.\n'
        '- Daha sık kucağa alınmak isteyebilir.\n'
        '- Uyku/beslenme düzeni geçici olarak dalgalanabilir.\n\n'
        '## Nasıl destek olabilirsin?\n\n'
        '- Sakin, tanıdık bir ortam sun; uyaranı azalt.\n'
        '- Ten tene temas ve alçak sesle konuşmak rahatlatır.\n'
        '- Bu geçici bir dönem — birkaç gün içinde sakinleşme beklenir.\n\n'
        '> Her bebek bu dönemleri farklı yaşar; süre ve yoğunluk değişebilir. Endişelenmen gereken bir durum değil, gelişiminin doğal bir parçası.',
  ),
  LeapInfo(
    index: 2,
    weekStart: 8,
    title: 'Örüntüleri Fark Ediyor',
    summary: 'Bebeğin, tekrar eden basit örüntüleri fark etmeye başladığı dönem.',
    fussyWeeksBefore: 1,
    body:
        'Bebeğin artık basit örüntüleri — bir hareketin, sesin ya da görüntünün tekrar ettiğini — fark etmeye başlıyor. Kendi elini izlemek, aynı sesi tekrar duymaktan hoşlanmak gibi davranışlar bu dönemde belirginleşebilir.\n\n'
        '## Bu dönemde neler olur?\n\n'
        '- Kendi el/ayaklarını daha bilinçli izler.\n'
        '- Basit, tekrar eden hareketlerden (sallanma, ritim) keyif alır.\n'
        '- Huzursuzluk ve ağlama nöbetleri artabilir.\n\n'
        '## Nasıl destek olabilirsin?\n\n'
        '- Basit, tekrar eden oyunlar (cee-ee gibi) ilgisini çeker.\n'
        '- Fazla uyarandan kaçın; kundaklama/ninni gibi sakinleştirme rutinlerine sarıl.\n\n'
        '> Zorlandığın anlarda yalnız olmadığını unutma — bu dönemler geçicidir.',
  ),
  LeapInfo(
    index: 3,
    weekStart: 12,
    title: 'Hareketler Akıcılaşıyor',
    summary: 'Bebeğin vücudunu daha yumuşak ve kontrollü hareket ettirmeye başladığı dönem.',
    fussyWeeksBefore: 1.5,
    body:
        'Bebeğinin hareketleri bu dönemde daha akıcı ve amaçlı hale gelir. Önceden rastgele görünen kol/bacak hareketleri artık daha kontrollü; dönmeye çalışma, bir nesneye doğru uzanma gibi girişimler başlayabilir.\n\n'
        '## Bu dönemde neler olur?\n\n'
        '- Hareketleri daha yumuşak, daha az "sıçramalı".\n'
        '- Nesnelere uzanma/yakalama girişimleri artar.\n'
        '- Geçici huzursuzluk ve yapışkanlık görülebilir.\n\n'
        '## Nasıl destek olabilirsin?\n\n'
        '- Yüzüstü oyun zamanı ve serbest hareket alanı ver.\n'
        '- Renkli, farklı dokularda oyuncaklarla uzanma/yakalamayı teşvik et.\n\n'
        '> Bu dönemde bebeğinin daha huysuz olması, yeni beceriler için "iç güç" harcadığının bir işareti olabilir.',
  ),
  LeapInfo(
    index: 4,
    weekStart: 19,
    title: 'Olayları Bağlıyor',
    summary: 'Bebeğin bir hareketin bir sonucu olduğunu fark etmeye başladığı dönem.',
    fussyWeeksBefore: 2,
    body:
        'Bebeğin artık bir olayın adım adım ilerlediğini ve bir sonucu olduğunu fark etmeye başlıyor. Bir oyuncağı düşürdüğünde ne olacağını "bekler", basit bir hareket dizisini takip edebilir.\n\n'
        '## Bu dönemde neler olur?\n\n'
        '- Nesneyi düşürüp tepkini izlemekten hoşlanabilir (yorucu ama gelişimsel!).\n'
        '- Tanıdık rutinleri (banyo → pijama → uyku) fark etmeye başlar.\n'
        '- Ayrılık kaygısı belirginleşebilir.\n\n'
        '## Nasıl destek olabilirsin?\n\n'
        '- Basit nedensellik oyuncakları (düşünce ses çıkaran, bastırınca açılan) sun.\n'
        '- Günlük rutinleri tutarlı tut — tahmin edilebilirlik güven verir.\n\n'
        '> Ayrılık kaygısı bu dönemde normaldir; sakin ve kısa vedalar güven inşa eder.',
  ),
  LeapInfo(
    index: 5,
    weekStart: 26,
    title: 'Yakınlığı ve Uzaklığı Anlıyor',
    summary: 'Nesnelerin/insanların mesafesini kavramaya başladığı, yabancı kaygısının belirginleştiği dönem.',
    fussyWeeksBefore: 2,
    body:
        'Bebeğin artık mesafe ve yakınlık kavramını anlamaya başlıyor — kendisiyle bir nesne/kişi arasındaki ilişkiyi fark ediyor. Bu, tanıdık/yabancı ayrımını netleştirir; yabancı kaygısı bu dönemde sık görülür.\n\n'
        '## Bu dönemde neler olur?\n\n'
        '- Tanımadığı kişilere karşı çekingenlik/ağlama artabilir.\n'
        '- Sürünme veya emeklemeye yönelik girişimler görülebilir.\n'
        '- Sana/bakım verene daha sıkı sarılma isteği.\n\n'
        '## Nasıl destek olabilirsin?\n\n'
        '- Yeni kişilerle tanışmayı zorlamadan, kademeli yap.\n'
        '- Güven verici yakınlığı esirgeme; bu bağlanmayı güçlendirir, "şımartmaz".\n\n'
        '> Yabancı kaygısı sağlıklı bağlanmanın bir işaretidir, genelde birkaç ay içinde yumuşar.',
  ),
  LeapInfo(
    index: 6,
    weekStart: 37,
    title: 'Gruplandırmaya Başlıyor',
    summary: 'Bebeğin nesneleri/sesleri benzerliklerine göre ayırt etmeye başladığı dönem.',
    fussyWeeksBefore: 2.5,
    body:
        'Bebeğin artık nesneleri ve kavramları kategorilere ayırmaya başlıyor — sert/yumuşak, büyük/küçük, hayvan/insan gibi basit gruplamaları sezgisel olarak fark edebiliyor.\n\n'
        '## Bu dönemde neler olur?\n\n'
        '- Farklı nesneleri karşılaştırıp incelemekten hoşlanır.\n'
        '- Basit taklit oyunlarına (alkışlama, el sallama) ilgisi artar.\n'
        '- Huysuzluk, uyku direnci görülebilir.\n\n'
        '## Nasıl destek olabilirsin?\n\n'
        '- Farklı doku/boyuttaki güvenli nesneleri keşfetmesine izin ver.\n'
        '- Basit resimli kitaplarla "bu ne?" sorularına yer aç.\n\n'
        '> Bu dönemde artan bağımsızlık isteği ile huzursuzluk bir arada görülebilir — ikisi de normaldir.',
  ),
  LeapInfo(
    index: 7,
    weekStart: 46,
    title: 'Adım Adım Yapmayı Öğreniyor',
    summary: 'Bebeğin basit, sıralı hareketleri taklit edip tekrarlayabildiği dönem.',
    fussyWeeksBefore: 3,
    body:
        'Bebeğin artık birden fazla adımı sırayla yapmayı deneyebiliyor — bir kutuyu açıp içindekini çıkarmak, bir bloğu diğerinin üstüne koymak gibi. Taklit becerisi belirgin şekilde güçlenir.\n\n'
        '## Bu dönemde neler olur?\n\n'
        '- Senin hareketlerini taklit etme isteği artar.\n'
        '- Basit "önce-sonra" oyunlarına katılabilir.\n'
        '- Hayal kırıklığına karşı sabırsızlık/ağlama artabilir.\n\n'
        '## Nasıl destek olabilirsin?\n\n'
        '- Basit, 2 adımlı görevleri birlikte yap (küpü kutuya koy, kapağı kapat).\n'
        '- Denemesine izin ver; hemen yardım etmek yerine bekle, cesaretlendir.\n\n'
        '> Bu dönemde hüsran toleransı düşüktür — bu bir "huy" değil, gelişimin doğal bir parçasıdır.',
  ),
  LeapInfo(
    index: 8,
    weekStart: 55,
    title: 'Küçük Planlar Kuruyor',
    summary: 'Bebeğin bir amaca ulaşmak için birkaç adımı art arda deneyebildiği dönem.',
    fussyWeeksBefore: 3,
    body:
        'Bebeğin artık basit bir "plan" kurabiliyor — istediği bir şeye ulaşmak için sırayla birkaç şey deniyor (sandalyeye tırmanıp masadaki oyuncağa uzanmak gibi). Bu, ileri düzey problem çözmenin başlangıcıdır.\n\n'
        '## Bu dönemde neler olur?\n\n'
        '- İstediğine ulaşmak için yaratıcı yollar dener.\n'
        '- "Hayır" ı anlar ama her zaman kabul etmeyebilir.\n'
        '- Huysuzluk, uyku direnci yine artabilir.\n\n'
        '## Nasıl destek olabilirsin?\n\n'
        '- Güvenli keşif alanı tanı; her "hayır" yerine yönlendirme kullan.\n'
        '- Basit engelli oyuncaklar (kapaklı kutular, geçiş oyuncakları) ilgisini çeker.\n\n'
        '> Bu dönemde artan inatlaşma, bağımsızlaşmanın erken bir işaretidir.',
  ),
  LeapInfo(
    index: 9,
    weekStart: 65,
    title: 'Kuralları Deniyor',
    summary: 'Çocuğun sınırları ve kuralları test etmeye, esnekliği anlamaya başladığı dönem.',
    fussyWeeksBefore: 3,
    body:
        'Çocuğun artık kuralların ve beklentilerin "esnek" olabileceğini keşfediyor — bazen bir kural her durumda geçerli olmayabiliyor. Bu, sınır test etme davranışının artmasına yol açabilir.\n\n'
        '## Bu dönemde neler olur?\n\n'
        '- "Hayır" a karşı direnç ve sınır zorlama artabilir.\n'
        '- Farklı ortamlarda farklı kuralları fark eder (evde/dışarıda).\n'
        '- Duygusal patlamalar (öfke nöbetleri) sık görülebilir.\n\n'
        '## Nasıl destek olabilirsin?\n\n'
        '- Tutarlı ama sıcak sınırlar koy; sınırın nedenini kısaca açıkla.\n'
        '- Duygularını adlandırmasına yardımcı ol ("kızgınsın, anlıyorum").\n\n'
        '> Sınır test etmek, çocuğun dünyayı anlama çabasıdır — kişisel bir meydan okuma değil.',
  ),
  LeapInfo(
    index: 10,
    weekStart: 75,
    title: 'Büyük Resmi Görüyor',
    summary: 'Çocuğun kendini bir bütünün parçası gibi görmeye, karmaşık ilişkileri kavramaya başladığı dönem.',
    fussyWeeksBefore: 3,
    body:
        'Çocuğun artık parçaları bir araya getirip "büyük resmi" görebiliyor — kendi rolünü bir aile, bir oyun ya da bir günlük düzenin parçası olarak anlamlandırabiliyor. Bu, soyut düşüncenin ilk adımlarından biridir.\n\n'
        '## Bu dönemde neler olur?\n\n'
        '- Rol yapma/hayali oyunlara ilgi artar.\n'
        '- Birden fazla adımlı, karmaşık talimatları takip edebilir.\n'
        '- Duygusal iniş çıkışlar ve huysuzluk yine görülebilir.\n\n'
        '## Nasıl destek olabilirsin?\n\n'
        '- Basit rol yapma oyunlarını (bebeğini besleme, "market" oyunu) destekle.\n'
        '- Günlük rutinde ona küçük, anlamlı görevler ver (kaşığını masaya koyma gibi).\n\n'
        '> Bu, ilk 20 ayın son büyük atağıdır — bundan sonrası daha bireysel bir tempoda ilerler.',
  ),
];
