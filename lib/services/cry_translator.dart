import 'package:flutter/material.dart';

/// 던스턴 베이비 랭귀지(Dunstan Baby Language) 번역 결과.
class TranslationResult {
  final String sound; // 하드웨어 소리 태그 (예: Neh)
  final String categoryKo; // 한국어 카테고리 (예: 배고픔)
  final String categoryEn; // 영어 카테고리 (예: Hunger)
  final String description; // 소리가 발생하는 생리학적 근거
  final String actionTip; // 부모를 위한 즉각 행동 가이드
  final String emoji; // 상태 이모지
  final Color color; // 상태 매핑 컬러
  final String audioSim; // 소리 의성어 표기

  const TranslationResult({
    required this.sound,
    required this.categoryKo,
    required this.categoryEn,
    required this.description,
    required this.actionTip,
    required this.emoji,
    required this.color,
    required this.audioSim,
  });

  /// 실제 울음(대응 필요)인지 여부. Unknown은 알림을 울리지 않는다.
  bool get isCry => sound != 'Unknown';
}

/// 던스턴 5대 울음 규칙 기반 번역기.
class CryTranslator {
  static const _unknown = TranslationResult(
    sound: 'Unknown',
    categoryKo: '울음 분석 대기',
    categoryEn: 'Analyzing',
    description: '규칙 외의 자연스러운 옹알이거나 주변 소음이 감지되었습니다. '
        '감정적 울음(놀람, 안아달라는 보챔)일 수도 있어요.',
    actionTip: '기기를 아기 입에서 1~1.5m 거리에 안정적으로 두고, '
        '주변 TV·음악 소리를 낮춘 뒤 다시 분석해 주세요.',
    emoji: '🩺',
    color: Color(0xFF64748B),
    audioSim: '분석 대기 중...',
  );

  static const Map<String, TranslationResult> _rules = {
    'neh': TranslationResult(
      sound: 'Neh',
      categoryKo: '배고픔',
      categoryEn: 'Hunger',
      description: '젖을 빠는 포유 반사(Sucking Reflex)로 혀가 입천장에 닿으면서 '
          '공기가 밀려나 "네~", "네에" 하는 N 자음 소리가 섞입니다. '
          '아기의 대표적인 맘마 필요 신호예요.',
      actionTip: '지체하지 말고 수유를 준비해 주세요. '
          '타이밍을 놓치면 아기가 격하게 울기 시작할 수 있어요.',
      emoji: '🍼',
      color: Color(0xFFF59E0B),
      audioSim: 'N-e-h... N-e-h...',
    ),
    'owh': TranslationResult(
      sound: 'Owh',
      categoryKo: '졸림',
      categoryEn: 'Sleepiness',
      description: '하품을 하듯 입을 동그랗게 크게 벌리며 내는 발성으로, '
          '"아우~", "오우-" 하는 낮고 느릿한 소리가 반복됩니다.',
      actionTip: '조명을 어둡게 하고 소음을 줄여 주세요. '
          '가볍게 토닥이며 백색소음과 함께 수면을 유도해 주세요.',
      emoji: '😴',
      color: Color(0xFF8B5CF6),
      audioSim: 'O-w-h... O-w-h...',
    ),
    'heh': TranslationResult(
      sound: 'Heh',
      categoryKo: '불편함 (기저귀/온도)',
      categoryEn: 'Discomfort',
      description: '축축한 기저귀, 덥거나 추운 공기 등 피부의 불쾌함을 호소하는 울음입니다. '
          '가쁜 호흡 속에 "헤-", "헤에-" 하는 높은 소리가 납니다.',
      actionTip: '먼저 기저귀가 젖었는지 확인하고, 방 온도·습도를 체크해 주세요. '
          '등에 땀이 차거나 옷이 피부를 찌르지 않는지도 살펴 주세요.',
      emoji: '👶',
      color: Color(0xFFEF4444),
      audioSim: 'H-e-h... H-e-h...',
    ),
    'eair': TranslationResult(
      sound: 'Eair',
      categoryKo: '하복부 가스',
      categoryEn: 'Lower Gas',
      description: '장에 가스가 차서 아래쪽 배에 압력이 심해진 상태입니다. '
          '다리를 배 위로 당기며 힘을 주기 때문에 "에어~" 하는 길고 억센 소리가 납니다.',
      actionTip: '아기 다리를 잡고 자전거 페달을 밟듯 가볍게 굽혔다 펴 주세요. '
          '배를 시계방향으로 부드럽게 원형 마사지해 주는 것도 좋아요.',
      emoji: '💨',
      color: Color(0xFF10B981),
      audioSim: 'E-a-i-r... E-a-i-r...',
    ),
    'eh': TranslationResult(
      sound: 'Eh',
      categoryKo: '트림 필요',
      categoryEn: 'Needs to burp',
      description: '수유 때 삼킨 공기가 가슴이나 식도 상부에 갇혀 있는 상태입니다. '
          '짧고 딱딱하게 끊기는 "에-", "에-" 소리를 반복해서 냅니다.',
      actionTip: '아기를 수직으로 세워 안고 등을 아래에서 위로 쓸어 올리거나, '
          '손을 오목하게 모아 가볍게 톡톡 두드려 트림을 유도해 주세요.',
      emoji: '😮‍💨',
      color: Color(0xFF14B8A6),
      audioSim: 'E-h... E-h...',
    ),
  };

  /// 하드웨어가 감지한 소리 태그를 던스턴 규칙에 매핑한다.
  static TranslationResult translate(String detectedSound) {
    return _rules[detectedSound.trim().toLowerCase()] ?? _unknown;
  }

  /// 데모/통계 화면에서 사용하는 전체 규칙 목록 (Unknown 포함).
  static List<TranslationResult> get all => [..._rules.values, _unknown];
}
