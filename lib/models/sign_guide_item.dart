class SignGuideItem {
  const SignGuideItem({
    required this.letter,
    required this.instruction,
    this.requiresMotion = false,
  });

  final String letter;
  final String instruction;
  final bool requiresMotion;

  String? get imageAsset =>
      requiresMotion ? null : 'assets/signs/${letter.toLowerCase()}.png';
}

const signGuideItems = <SignGuideItem>[
  SignGuideItem(
    letter: 'A',
    instruction: 'Kepalkan tangan, ibu jari di sisi luar.',
  ),
  SignGuideItem(
    letter: 'B',
    instruction: 'Empat jari lurus rapat, ibu jari menutup telapak.',
  ),
  SignGuideItem(
    letter: 'C',
    instruction: 'Lengkungkan semua jari seperti bentuk huruf C.',
  ),
  SignGuideItem(
    letter: 'D',
    instruction: 'Telunjuk ke atas, ujung jari lain bertemu ibu jari.',
  ),
  SignGuideItem(
    letter: 'E',
    instruction: 'Tekuk semua jari ke telapak, ibu jari di depannya.',
  ),
  SignGuideItem(
    letter: 'F',
    instruction:
        'Telunjuk dan ibu jari membentuk lingkaran; tiga jari ke atas.',
  ),
  SignGuideItem(
    letter: 'G',
    instruction:
        'Telunjuk dan ibu jari mengarah ke samping, jari lain ditekuk.',
  ),
  SignGuideItem(
    letter: 'H',
    instruction: 'Telunjuk dan jari tengah rapat mengarah ke samping.',
  ),
  SignGuideItem(
    letter: 'I',
    instruction: 'Kelingking ke atas, jari lainnya mengepal.',
  ),
  SignGuideItem(
    letter: 'J',
    instruction: 'Mulai dari bentuk I lalu gerakkan kelingking membentuk J.',
    requiresMotion: true,
  ),
  SignGuideItem(
    letter: 'K',
    instruction: 'Telunjuk dan jari tengah terbuka; ibu jari di antaranya.',
  ),
  SignGuideItem(
    letter: 'L',
    instruction: 'Telunjuk ke atas dan ibu jari ke samping membentuk L.',
  ),
  SignGuideItem(
    letter: 'M',
    instruction: 'Ibu jari terselip di bawah tiga jari yang ditekuk.',
  ),
  SignGuideItem(
    letter: 'N',
    instruction: 'Ibu jari terselip di bawah dua jari yang ditekuk.',
  ),
  SignGuideItem(
    letter: 'O',
    instruction: 'Semua ujung jari bertemu ibu jari membentuk O.',
  ),
  SignGuideItem(
    letter: 'P',
    instruction: 'Bentuk K diputar hingga mengarah ke bawah.',
  ),
  SignGuideItem(
    letter: 'Q',
    instruction: 'Bentuk G diputar hingga mengarah ke bawah.',
  ),
  SignGuideItem(
    letter: 'R',
    instruction: 'Telunjuk dan jari tengah ke atas lalu disilangkan.',
  ),
  SignGuideItem(
    letter: 'S',
    instruction: 'Kepalkan tangan, ibu jari melintang di depan jari.',
  ),
  SignGuideItem(
    letter: 'T',
    instruction:
        'Kepalkan tangan, ibu jari keluar di antara telunjuk dan jari tengah.',
  ),
  SignGuideItem(
    letter: 'U',
    instruction: 'Telunjuk dan jari tengah lurus serta rapat.',
  ),
  SignGuideItem(
    letter: 'V',
    instruction: 'Telunjuk dan jari tengah lurus serta terbuka.',
  ),
  SignGuideItem(
    letter: 'W',
    instruction: 'Telunjuk, tengah, dan manis lurus serta terbuka.',
  ),
  SignGuideItem(
    letter: 'X',
    instruction: 'Telunjuk ditekuk seperti kait, jari lain mengepal.',
  ),
  SignGuideItem(
    letter: 'Y',
    instruction: 'Ibu jari dan kelingking terbuka, tiga jari lain ditekuk.',
  ),
  SignGuideItem(
    letter: 'Z',
    instruction: 'Gunakan telunjuk untuk menggambar bentuk Z di udara.',
    requiresMotion: true,
  ),
];
