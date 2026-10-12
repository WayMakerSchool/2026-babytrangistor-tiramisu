import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/baby_cry_data.dart';
import '../services/app_state.dart';
import '../services/cry_translator.dart';
import '../theme.dart';

/// 울음 기록 화면: 오늘 통계 요약 + 시간순 이벤트 목록.
/// 아기별 울음 패턴을 파악하는 데 활용한다.
class HistoryScreen extends StatelessWidget {
  final AppState appState;
  const HistoryScreen({super.key, required this.appState});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final history = appState.history;
        return Scaffold(
          appBar: AppBar(
            title: const Text('울음 기록'),
            actions: [
              if (history.isNotEmpty)
                IconButton(
                  tooltip: '기록 전체 삭제',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _confirmClear(context),
                ),
            ],
          ),
          body: history.isEmpty
              ? const _EmptyView()
              : ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    _TodaySummary(history: history),
                    const SizedBox(height: 20),
                    const Text(
                      '최근 이벤트',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 10),
                    ...history.map((e) => _HistoryTile(data: e)),
                  ],
                ),
        );
      },
    );
  }

  Future<void> _confirmClear(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('기록 삭제'),
        content: const Text('저장된 울음 기록을 모두 삭제할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('삭제', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true) await appState.clearHistory();
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('🍼', style: TextStyle(fontSize: 56)),
          SizedBox(height: 14),
          Text(
            '아직 기록된 울음이 없어요',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.textDark,
            ),
          ),
          SizedBox(height: 6),
          Text(
            '기기가 울음을 감지하면 자동으로 기록됩니다.',
            style: TextStyle(fontSize: 13, color: AppColors.textGrey),
          ),
        ],
      ),
    );
  }
}

/// 오늘 감지된 울음의 카테고리별 횟수 요약.
class _TodaySummary extends StatelessWidget {
  final List<BabyCryData> history;
  const _TodaySummary({required this.history});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = history.where((e) =>
        e.timestamp.year == now.year &&
        e.timestamp.month == now.month &&
        e.timestamp.day == now.day);

    final counts = <String, int>{};
    for (final e in today) {
      final key = CryTranslator.translate(e.detectedSound).sound;
      counts[key] = (counts[key] ?? 0) + 1;
    }
    final total = today.length;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.insights, color: AppColors.primary, size: 18),
              const SizedBox(width: 6),
              const Text(
                '오늘의 울음 요약',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textDark,
                ),
              ),
              const Spacer(),
              Text(
                '총 $total회',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (total == 0)
            const Text(
              '오늘은 아직 감지된 울음이 없어요.',
              style: TextStyle(fontSize: 13, color: AppColors.textGrey),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: CryTranslator.all
                  .where((r) => r.isCry && (counts[r.sound] ?? 0) > 0)
                  .map((r) => Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: r.color.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${r.emoji} ${r.categoryKo} ${counts[r.sound]}회',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.bold,
                            color: r.color,
                          ),
                        ),
                      ))
                  .toList(),
            ),
        ],
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  final BabyCryData data;
  const _HistoryTile({required this.data});

  @override
  Widget build(BuildContext context) {
    final result = CryTranslator.translate(data.detectedSound);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: cardDecoration(),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: result.color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(result.emoji, style: const TextStyle(fontSize: 22)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  result.categoryKo,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  DateFormat('M월 d일 (E) a h:mm', 'ko_KR')
                      .format(data.timestamp),
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textGrey),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${(data.confidenceScore * 100).toInt()}%',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: result.color,
                ),
              ),
              Text(
                '${data.decibelLevel} dB',
                style: const TextStyle(
                    fontSize: 11, color: AppColors.textGrey),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
