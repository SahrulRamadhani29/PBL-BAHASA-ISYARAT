import 'package:flutter/material.dart';

import '../models/sign_guide_item.dart';

class SignGuideScreen extends StatelessWidget {
  const SignGuideScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      key: const PageStorageKey('sign-guide'),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Rumus Sign Language',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'Pilih huruf untuk melihat cara membentuk ejaan jari ASL.',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 14),
                const _MotionNotice(),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          sliver: SliverGrid.builder(
            itemCount: signGuideItems.length,
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 112,
              mainAxisExtent: 112,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemBuilder: (context, index) {
              final item = signGuideItems[index];
              return _LetterCard(item: item);
            },
          ),
        ),
      ],
    );
  }
}

class _MotionNotice extends StatelessWidget {
  const _MotionNotice();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFFFE8B3),
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Padding(
        padding: EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(Icons.gesture_rounded, color: Color(0xFF7A4B00)),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'J dan Z memakai gerakan, sehingga belum dinilai oleh model gambar statis.',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LetterCard extends StatelessWidget {
  const _LetterCard({required this.item});

  final SignGuideItem item;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: item.requiresMotion
          ? const Color(0xFFFFF0CC)
          : const Color(0xFFF2F7F3),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _showDetail(context),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(
                child: item.imageAsset == null
                    ? Center(
                        child: Text(
                          item.letter,
                          style: Theme.of(context).textTheme.displaySmall
                              ?.copyWith(
                                color: const Color(0xFF9A6200),
                                fontWeight: FontWeight.w900,
                              ),
                        ),
                      )
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Image.asset(
                          item.imageAsset!,
                          width: double.infinity,
                          fit: BoxFit.cover,
                        ),
                      ),
              ),
              const SizedBox(height: 5),
              Text(
                item.requiresMotion ? '${item.letter} · Gerakan' : item.letter,
                style: Theme.of(context).textTheme.labelLarge
                    ?.copyWith(fontWeight: FontWeight.w900),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showDetail(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (item.imageAsset != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Image.asset(
                  item.imageAsset!,
                  width: 220,
                  height: 220,
                  fit: BoxFit.cover,
                ),
              )
            else
              Container(
                width: 180,
                height: 120,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF0CC),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Text(
                  '${item.letter} · membutuhkan gerakan',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: const Color(0xFF7A4B00),
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            const SizedBox(height: 18),
            Text(
              'Bentuk tangan huruf ${item.letter}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 10),
            Text(
              item.instruction,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            if (item.requiresMotion) ...[
              const SizedBox(height: 12),
              const Text(
                'Model saat ini tidak mengenali huruf ini.',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
