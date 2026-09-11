import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pbl_bahasa_isyarat/main.dart';
import 'package:pbl_bahasa_isyarat/models/sign_guide_item.dart';

void main() {
  testWidgets('menampilkan tiga menu utama', (tester) async {
    await tester.pumpWidget(const LatihIsyaratApp(cameraEnabled: false));

    expect(find.text('Kamera Latihan'), findsOneWidget);
    expect(find.text('Kamera'), findsOneWidget);
    expect(find.text('Upload'), findsOneWidget);
    expect(find.text('Rumus ASL'), findsOneWidget);
    expect(find.text('Tangan boleh di mana saja dalam frame'), findsOneWidget);
  });

  testWidgets('mode bebas dan mode target memiliki alur berbeda', (
    tester,
  ) async {
    await tester.pumpWidget(const LatihIsyaratApp(cameraEnabled: false));

    expect(find.text('MODE: LATIHAN BEBAS'), findsOneWidget);
    expect(find.text('Mulai latihan bebas'), findsOneWidget);

    await tester.tap(find.text('MODE: LATIHAN BEBAS'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('MODE UJI: HURUF A').last);
    await tester.pumpAndSettle();

    expect(find.text('MODE UJI: HURUF A'), findsOneWidget);
    expect(find.text('Mulai uji huruf A'), findsNothing);
    expect(find.text('Reset hasil uji A'), findsOneWidget);
    expect(find.text('Deteksi otomatis menunggu kamera'), findsOneWidget);
    expect(find.textContaining('video tidak direkam'), findsOneWidget);

    await tester.tap(find.text('MODE UJI: HURUF A'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('MODE: LATIHAN BEBAS').last);
    await tester.pumpAndSettle();

    expect(find.text('Mulai latihan bebas'), findsOneWidget);
    expect(find.textContaining('Reset hasil uji'), findsNothing);
  });

  testWidgets('menu rumus menampilkan alfabet ASL', (tester) async {
    await tester.pumpWidget(const LatihIsyaratApp(cameraEnabled: false));

    await tester.tap(find.text('Rumus ASL'));
    await tester.pumpAndSettle();

    expect(find.text('Rumus Sign Language'), findsOneWidget);
    expect(find.text('A'), findsOneWidget);
    expect(find.byType(Image), findsWidgets);
    expect(find.textContaining('Gerakan'), findsWidgets);
    expect(signGuideItems.where((item) => item.requiresMotion), hasLength(2));
    expect(
      signGuideItems.where((item) => item.imageAsset != null),
      hasLength(24),
    );
  });

  testWidgets('menu upload menyediakan pilihan tunggal dan banyak', (
    tester,
  ) async {
    await tester.pumpWidget(const LatihIsyaratApp(cameraEnabled: false));

    await tester.tap(find.text('Upload'));
    await tester.pumpAndSettle();

    expect(find.text('Satu gambar'), findsOneWidget);
    expect(find.text('Banyak gambar'), findsOneWidget);
  });
}
