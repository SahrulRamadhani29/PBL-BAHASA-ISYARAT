import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/sign_prediction.dart';
import '../services/sign_classifier.dart';

class UploadScreen extends StatefulWidget {
  const UploadScreen({super.key});

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  final _picker = ImagePicker();
  final _results = <ImagePredictionResult>[];
  bool _isProcessing = false;

  Future<void> _pickSingle() async {
    final file = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 95,
      requestFullMetadata: false,
    );
    if (file != null) await _classifyFiles([file]);
  }

  Future<void> _pickMultiple() async {
    final files = await _picker.pickMultiImage(
      imageQuality: 95,
      requestFullMetadata: false,
    );
    if (files.isNotEmpty) await _classifyFiles(files);
  }

  Future<void> _classifyFiles(List<XFile> files) async {
    setState(() {
      _isProcessing = true;
      _results.clear();
    });

    for (final file in files) {
      ImagePredictionResult result;
      try {
        final prediction = await SignClassifier.instance.classifyFile(
          file.path,
        );
        result = ImagePredictionResult(path: file.path, prediction: prediction);
      } catch (error) {
        result = ImagePredictionResult(path: file.path, error: '$error');
      }
      if (!mounted) return;
      setState(() => _results.add(result));
    }

    if (mounted) setState(() => _isProcessing = false);
  }

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      key: const PageStorageKey('upload'),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Uji Gambar',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'Pilih satu atau banyak gambar. Setiap gambar menghasilkan satu huruf.',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _isProcessing ? null : _pickSingle,
                        icon: const Icon(Icons.image_outlined),
                        label: const Text('Satu gambar'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _isProcessing ? null : _pickMultiple,
                        icon: const Icon(Icons.photo_library_outlined),
                        label: const Text('Banyak gambar'),
                      ),
                    ),
                  ],
                ),
                if (_isProcessing) ...[
                  const SizedBox(height: 18),
                  const LinearProgressIndicator(),
                  const SizedBox(height: 8),
                  Text('Memproses gambar ${_results.length + 1}...'),
                ],
              ],
            ),
          ),
        ),
        if (_results.isEmpty && !_isProcessing)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: _EmptyUploadState(),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            sliver: SliverList.list(
              children: [
                _UploadSummary(results: _results),
                const SizedBox(height: 14),
                for (var index = 0; index < _results.length; index++) ...[
                  _ResultCard(result: _results[index], index: index),
                  if (index < _results.length - 1) const SizedBox(height: 12),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _UploadSummary extends StatelessWidget {
  const _UploadSummary({required this.results});

  final List<ImagePredictionResult> results;

  @override
  Widget build(BuildContext context) {
    final letters = results
        .map((result) => result.prediction?.label)
        .whereType<String>()
        .join();
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFE0EFE9),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.text_fields_rounded, color: Color(0xFF0D5C46)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Urutan hasil tanpa spasi',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    letters.isEmpty ? 'Belum ada hasil valid' : letters,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                      letterSpacing: 3,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyUploadState extends StatelessWidget {
  const _EmptyUploadState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.add_photo_alternate_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 14),
            const Text(
              'Belum ada gambar',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            const Text(
              'Untuk hasil uji awal, gunakan foto satu tangan dengan posisi tengah dan latar sederhana.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.result, required this.index});

  final ImagePredictionResult result;
  final int index;

  @override
  Widget build(BuildContext context) {
    final prediction = result.prediction;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: 104,
        child: Row(
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: Image.file(
                File(result.path),
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const ColoredBox(
                  color: Color(0xFFE9ECE8),
                  child: Icon(Icons.broken_image_outlined),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: prediction == null
                    ? Text(
                        'Gambar ${index + 1}\nGagal: ${result.error}',
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      )
                    : Row(
                        children: [
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Gambar ${index + 1}',
                                  style: Theme.of(context).textTheme.labelLarge,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Keyakinan ${prediction.confidenceText}',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          Text(
                            prediction.label,
                            style: Theme.of(context).textTheme.displaySmall
                                ?.copyWith(
                                  color: const Color(0xFF0D5C46),
                                  fontWeight: FontWeight.w900,
                                ),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
