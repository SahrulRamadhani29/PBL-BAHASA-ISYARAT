import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:pbl_bahasa_isyarat/services/image_preprocessor.dart';
import 'package:pbl_bahasa_isyarat/services/sign_classifier.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('model mengenali seluruh foto referensi alfabet', (tester) async {
    final labelsData = await rootBundle.loadString('assets/models/labels.json');
    final labelsJson = jsonDecode(labelsData) as Map<String, dynamic>;
    final labels = List<String>.from(labelsJson['labels'] as List<dynamic>);
    final results = <String, Map<String, Object?>>{};
    final classifier = SignClassifier.instance;
    await classifier.initialize();

    for (final expected in labels) {
      final imageData = await rootBundle.load(
        'assets/signs/${expected.toLowerCase()}.png',
      );
      final image = ImagePreprocessor.decodeFileBytes(
        imageData.buffer.asUint8List(),
      );
      final normal = await classifier.classifyImage(image);
      final mirrored = await classifier.classifyImage(
        img.flipHorizontal(img.Image.from(image)),
      );
      results[expected] = <String, Object?>{
        'normal_label': normal.label,
        'normal_confidence': normal.confidence,
        'mirrored_label': mirrored.label,
        'mirrored_confidence': mirrored.confidence,
      };
    }

    // Keep this machine-readable so the same test can produce a regression
    // report on any Android device used by the team.
    // ignore: avoid_print
    print('ALL_LETTERS_RESULT=${jsonEncode(results)}');
    expect(results, hasLength(24));
    for (final expected in labels) {
      expect(
        results[expected]!['normal_label'],
        expected,
        reason: 'Orientasi model harus mengenali huruf $expected.',
      );
    }
    expect(
      results.values.every(
        (result) =>
            (result['normal_confidence']! as double).isFinite &&
            (result['mirrored_confidence']! as double).isFinite,
      ),
      isTrue,
    );
  });
}
