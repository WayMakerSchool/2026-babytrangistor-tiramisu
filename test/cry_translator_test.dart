import 'package:baby_cry_translator/models/baby_cry_data.dart';
import 'package:baby_cry_translator/services/cry_translator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CryTranslator', () {
    test('던스턴 5대 소리를 모두 매핑한다', () {
      expect(CryTranslator.translate('Neh').categoryKo, '배고픔');
      expect(CryTranslator.translate('Owh').categoryKo, '졸림');
      expect(CryTranslator.translate('Heh').categoryKo, '불편함 (기저귀/온도)');
      expect(CryTranslator.translate('Eair').categoryKo, '하복부 가스');
      expect(CryTranslator.translate('Eh').categoryKo, '트림 필요');
    });

    test('대소문자와 공백을 정규화한다', () {
      expect(CryTranslator.translate('  NEH ').sound, 'Neh');
      expect(CryTranslator.translate('owh').sound, 'Owh');
    });

    test('알 수 없는 소리는 Unknown으로 처리하고 알림 대상이 아니다', () {
      final result = CryTranslator.translate('babble');
      expect(result.sound, 'Unknown');
      expect(result.isCry, false);
      expect(CryTranslator.translate('Neh').isCry, true);
    });
  });

  group('BabyCryData', () {
    test('ESP32 JSON 패킷을 파싱한다', () {
      final data = BabyCryData.fromJson({
        'device_id': 'BABY_MONITOR_01',
        'timestamp': '2026-07-14T05:15:00Z',
        'detected_sound': 'Neh',
        'confidence_score': 0.92,
        'decibel_level': 65,
      });
      expect(data.deviceId, 'BABY_MONITOR_01');
      expect(data.detectedSound, 'Neh');
      expect(data.confidenceScore, 0.92);
      expect(data.decibelLevel, 65);
    });

    test('필드 누락/타입 혼입에도 안전하게 파싱한다', () {
      final data = BabyCryData.fromJson({
        'confidence_score': 1, // int로 들어와도 double 처리
        'decibel_level': 65.7, // double로 들어와도 int 처리
      });
      expect(data.deviceId, 'UNKNOWN_MONITOR');
      expect(data.detectedSound, 'Unknown');
      expect(data.confidenceScore, 1.0);
      expect(data.decibelLevel, 65);
    });

    test('toJson 라운드트립이 성립한다', () {
      final original = BabyCryData(
        deviceId: 'D1',
        timestamp: DateTime(2026, 7, 14, 14, 15),
        detectedSound: 'Owh',
        confidenceScore: 0.88,
        decibelLevel: 62,
      );
      final restored = BabyCryData.fromJson(original.toJson());
      expect(restored.deviceId, original.deviceId);
      expect(restored.detectedSound, original.detectedSound);
      expect(restored.confidenceScore, original.confidenceScore);
      expect(restored.decibelLevel, original.decibelLevel);
    });
  });
}
