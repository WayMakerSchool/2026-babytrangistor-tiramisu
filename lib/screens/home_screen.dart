import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/app_state.dart';
import '../services/connection_service.dart';
import '../services/cry_translator.dart';
import '../theme.dart';

/// 실시간 아기 상태 화면.
/// 하드웨어에서 새 울음 이벤트가 오면 번역 결과와 함께
/// 화면 색상 플래시(청각장애 부모 접근성)를 표시한다.
class HomeScreen extends StatefulWidget {
  final AppState appState;
  const HomeScreen({super.key, required this.appState});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with TickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final AnimationController _flashController;
  int _lastAlertTick = 0;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _flashController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    _lastAlertTick = widget.appState.alertTick;
    widget.appState.addListener(_onStateChanged);
  }

  void _onStateChanged() {
    // 새 울음 이벤트 → 전체 화면 색상 플래시 (진동과 함께 시각 알림)
    if (widget.appState.alertTick != _lastAlertTick) {
      _lastAlertTick = widget.appState.alertTick;
      if (widget.appState.settings.flashEnabled) {
        _flashController.forward(from: 0);
      }
      _showCryAlert();
    }
  }

  bool _alertVisible = false;
  Timer? _alertAutoClose;

  /// 울음 감지 알림 팝업: 어떤 상태인지 크게 보여주고 8초 후 자동으로 닫힌다.
  void _showCryAlert() {
    if (!mounted) return;
    final result = widget.appState.currentTranslation;
    final data = widget.appState.current;

    // 이전 알림이 떠 있으면 닫고 최신 상태로 갱신
    if (_alertVisible) {
      Navigator.of(context, rootNavigator: true).pop();
    }
    _alertVisible = true;

    _alertAutoClose?.cancel();
    _alertAutoClose = Timer(const Duration(seconds: 8), () {
      if (_alertVisible && mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    });

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Column(
          children: [
            Text(result.emoji, style: const TextStyle(fontSize: 52)),
            const SizedBox(height: 10),
            Text(
              '${result.categoryKo} 감지!',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w800,
                color: result.color,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (data != null)
              Text(
                '${DateFormat('a h:mm', 'ko_KR').format(data.timestamp)} · '
                '신뢰도 ${(data.confidenceScore * 100).toInt()}% · '
                '${data.decibelLevel} dB',
                style: const TextStyle(
                    fontSize: 12.5, color: AppColors.textGrey),
              ),
            const SizedBox(height: 10),
            Text(
              result.actionTip,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                height: 1.55,
                fontWeight: FontWeight.w600,
                color: AppColors.textDark,
              ),
            ),
          ],
        ),
        actions: [
          Center(
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: result.color,
                minimumSize: const Size(160, 44),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('확인',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
        actionsPadding: const EdgeInsets.only(bottom: 16),
      ),
    ).then((_) {
      _alertVisible = false;
      _alertAutoClose?.cancel();
    });
  }

  @override
  void dispose() {
    widget.appState.removeListener(_onStateChanged);
    _alertAutoClose?.cancel();
    _pulseController.dispose();
    _flashController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.appState,
      builder: (context, _) {
        final state = widget.appState;
        final result = state.currentTranslation;

        return Scaffold(
          appBar: AppBar(
            title: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.child_care,
                      color: AppColors.primary, size: 20),
                ),
                const SizedBox(width: 8),
                const Text('아기 언어 번역기'),
              ],
            ),
          ),
          body: Stack(
            children: [
              ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  _DeviceStatusBanner(state: state),
                  const SizedBox(height: 18),
                  _buildVisualizer(result),
                  const SizedBox(height: 20),
                  _TranslationCard(state: state, result: result),
                  const SizedBox(height: 16),
                  _MetricsRow(state: state),
                  if (state.isDemo) ...[
                    const SizedBox(height: 24),
                    _SandboxPanel(state: state),
                  ],
                  const SizedBox(height: 12),
                ],
              ),
              // 청각장애 부모용 화면 플래시 오버레이
              IgnorePointer(
                child: AnimatedBuilder(
                  animation: _flashController,
                  builder: (context, _) {
                    final t = _flashController.value;
                    if (t == 0 || _flashController.isDismissed) {
                      return const SizedBox.shrink();
                    }
                    // 두 번 깜빡이고 사라지는 파형
                    final wave =
                        (1 - t) * (0.5 + 0.5 * (1 - (2 * ((t * 2) % 1) - 1).abs()));
                    return Container(
                      color: result.color.withValues(alpha: 0.45 * wave),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildVisualizer(TranslationResult result) {
    return SizedBox(
      height: 190,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, _) {
              return Container(
                width: 140 + 30 * _pulseController.value,
                height: 140 + 30 * _pulseController.value,
                decoration: BoxDecoration(
                  color: result.color
                      .withValues(alpha: 0.14 * (1 - _pulseController.value)),
                  shape: BoxShape.circle,
                ),
              );
            },
          ),
          Container(
            width: 124,
            height: 124,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(
                color: result.color.withValues(alpha: 0.5),
                width: 2.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: result.color.withValues(alpha: 0.2),
                  blurRadius: 18,
                  spreadRadius: 2,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Center(
              child: Text(result.emoji, style: const TextStyle(fontSize: 56)),
            ),
          ),
          Positioned(
            bottom: 0,
            child: Text(
              result.audioSim,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textGrey,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DeviceStatusBanner extends StatelessWidget {
  final AppState state;
  const _DeviceStatusBanner({required this.state});

  @override
  Widget build(BuildContext context) {
    final status = state.connectionStatus;
    final (label, color, icon) = switch (status) {
      ConnectionStatus.connected => (
          'LIVE',
          AppColors.live,
          Icons.wifi_tethering
        ),
      ConnectionStatus.connecting => (
          '연결 중',
          Colors.amber.shade700,
          Icons.wifi_find
        ),
      ConnectionStatus.error => ('연결 오류', Colors.red, Icons.wifi_off),
      ConnectionStatus.disconnected => (
          '연결 끊김',
          AppColors.textGrey,
          Icons.wifi_off
        ),
    };

    final modeLabel = switch (state.settings.mode) {
      _ when state.isDemo => '데모 모드 (기기 시뮬레이션)',
      _ => '${state.settings.deviceId} ∙ 실시간 동기화',
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: cardDecoration(),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: status == ConnectionStatus.connected
                  ? AppColors.primarySoft
                  : Colors.grey.shade100,
              shape: BoxShape.circle,
            ),
            child: Icon(icon,
                size: 20,
                color: status == ConnectionStatus.connected
                    ? AppColors.primary
                    : AppColors.textGrey),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '기기 연결 상태',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textGrey,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  modeLabel,
                  style: const TextStyle(
                    fontSize: 13.5,
                    color: AppColors.textDark,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          if (status == ConnectionStatus.error ||
              status == ConnectionStatus.disconnected)
            TextButton.icon(
              onPressed: state.reconnect,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('재연결', style: TextStyle(fontSize: 12)),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration:
                        BoxDecoration(color: color, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: TextStyle(
                      color: color,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _TranslationCard extends StatelessWidget {
  final AppState state;
  final TranslationResult result;
  const _TranslationCard({required this.state, required this.result});

  @override
  Widget build(BuildContext context) {
    final data = state.current;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: cardDecoration(
        borderColor: result.color.withValues(alpha: 0.35),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: result.color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Text(
                  '던스턴 소리 태그: ${result.sound}',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: result.color,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (data != null)
                Row(
                  children: [
                    const Icon(Icons.access_time,
                        size: 13, color: AppColors.textGrey),
                    const SizedBox(width: 4),
                    Text(
                      DateFormat('a h:mm:ss', 'ko_KR').format(data.timestamp),
                      style: const TextStyle(
                          fontSize: 11.5, color: AppColors.textGrey),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            result.isCry
                ? '우리 아기가 지금 ${result.categoryKo} 상태예요!'
                : '아기 소리를 기다리고 있어요',
            style: const TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w800,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            result.description,
            style: const TextStyle(
              fontSize: 13.5,
              height: 1.6,
              color: AppColors.textGrey,
            ),
          ),
          const Divider(height: 28),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: const BoxDecoration(
                  color: AppColors.primarySoft,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.tips_and_updates,
                    color: AppColors.primary, size: 16),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '부모님 권장 행동 팁',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      result.actionTip,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.55,
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetricsRow extends StatelessWidget {
  final AppState state;
  const _MetricsRow({required this.state});

  @override
  Widget build(BuildContext context) {
    final confidence = state.current?.confidenceScore ?? 0;
    final decibel = state.current?.decibelLevel ?? 0;

    return Row(
      children: [
        Expanded(
          child: _MetricCard(
            icon: Icons.check_circle_outline,
            iconColor: Colors.indigo,
            label: 'AI 판단 정확도',
            value: '${(confidence * 100).toInt()}%',
            progress: confidence,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: _MetricCard(
            icon: Icons.volume_up,
            iconColor: Colors.amber.shade700,
            label: '소리 데시벨',
            value: '$decibel dB',
            progress: decibel / 110,
          ),
        ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final double progress;

  const _MetricCard({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor, size: 16),
              const SizedBox(width: 5),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: AppColors.textGrey,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: iconColor,
            ),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              backgroundColor: Colors.grey.shade100,
              color: iconColor,
              minHeight: 4,
            ),
          ),
        ],
      ),
    );
  }
}

/// 데모 모드 전용: 하드웨어 수집 모의 제어 패널.
class _SandboxPanel extends StatelessWidget {
  final AppState state;
  const _SandboxPanel({required this.state});

  static const _candidates = [
    ('Neh', '네(Neh) · 배고픔', 0.95, 72),
    ('Owh', '아우(Owh) · 졸림', 0.89, 64),
    ('Heh', '헤(Heh) · 기저귀 불편', 0.91, 68),
    ('Eair', '에어(Eair) · 복부 가스', 0.86, 75),
    ('Eh', '에(Eh) · 트림 필요', 0.94, 70),
    ('Unknown', '조용함 / 일반 잡음', 0.32, 42),
  ];

  @override
  Widget build(BuildContext context) {
    final selected = state.current?.detectedSound;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.developer_mode, color: AppColors.primary, size: 18),
            SizedBox(width: 6),
            Text(
              '하드웨어 수집 모의 제어 (샌드박스)',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: AppColors.textDark,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _candidates.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 3.2,
          ),
          itemBuilder: (context, index) {
            final (sound, label, conf, db) = _candidates[index];
            final isSelected = selected == sound;
            return ElevatedButton(
              style: ElevatedButton.styleFrom(
                elevation: isSelected ? 2 : 0,
                backgroundColor:
                    isSelected ? AppColors.primary : Colors.white,
                foregroundColor:
                    isSelected ? Colors.white : AppColors.textDark,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: isSelected ? AppColors.primary : AppColors.border,
                  ),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              onPressed: () => state.demoService?.trigger(sound, conf, db),
              child: Text(
                label,
                style: const TextStyle(
                    fontSize: 11.5, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            );
          },
        ),
      ],
    );
  }
}
