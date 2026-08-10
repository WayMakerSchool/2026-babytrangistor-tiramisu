# 아기 언어 번역기 앱 (팀 티라미수) 🍼

XIAO ESP32S3 Sense 기반 아기 울음 감지 기기와 연동되는 **Android & iOS 앱**입니다.
던스턴 베이비 랭귀지(Dunstan Baby Language) 5대 울음 규칙을 기반으로,
기기가 분류한 아기 울음의 원인을 부모가 **원격으로** 확인할 수 있습니다.

## 주요 기능

| 기능 | 설명 |
|---|---|
| 실시간 번역 | 배고픔(Neh)·졸림(Owh)·불편함(Heh)·복부가스(Eair)·트림(Eh) 5대 상태 + 행동 팁 |
| 원격 확인 (MQTT) | ESP32 → MQTT 브로커 → 앱. 외출 중에도 아기 상태 확인 가능 |
| Wi-Fi 직접 연결 | 같은 네트워크에서 기기 WebSocket 서버(포트 81)에 직접 연결 |
| 접근성 알림 | 청각장애 부모를 위한 **진동 + 화면 색상 플래시** 알림 |
| 울음 기록 | 오늘의 카테고리별 통계 + 시간순 이벤트 목록 (로컬 저장, 최대 200건) |
| 데모 모드 | 기기 없이 샌드박스 버튼으로 전체 기능 체험 |
| 분석 민감도 | 신뢰도 임계값 슬라이더 — 이 값 이상일 때만 알림·기록 |

## 실행 방법

```bash
cd baby_cry_translator
flutter pub get
flutter run          # 연결된 기기/시뮬레이터에서 실행
```

- Android 빌드: `flutter build apk`
- iOS 빌드: `flutter build ios` (Xcode 서명 필요)

처음 실행하면 **데모 모드**로 시작합니다. 홈 화면 하단 샌드박스 버튼으로
울음 이벤트를 발생시켜 번역·진동·플래시·기록 기능을 바로 확인할 수 있습니다.

## 프로젝트 구조

```
lib/
├── main.dart                      # 앱 진입점 + 하단 탭 내비게이션
├── theme.dart                     # 따뜻한 톤 디자인 토큰
├── models/
│   └── baby_cry_data.dart         # 하드웨어 JSON 패킷 모델
├── services/
│   ├── cry_translator.dart        # 던스턴 5대 규칙 번역기
│   ├── connection_service.dart    # MQTT / WebSocket / 데모 수신 서비스
│   ├── app_settings.dart          # 설정 (연결 방식, 브로커, 알림)
│   └── app_state.dart             # 전역 상태 + 기록 저장 + 접근성 알림
└── screens/
    ├── home_screen.dart           # 실시간 상태 (펄스 비주얼라이저 + 번역 카드)
    ├── history_screen.dart        # 울음 기록 + 오늘의 통계
    └── settings_screen.dart       # 연결/알림/민감도 설정
```

## ESP32 연동 규격

### 데이터 패킷 (JSON)

ESP32가 울음을 분류할 때마다 아래 JSON을 전송합니다:

```json
{
  "device_id": "BABY_MONITOR_01",
  "timestamp": "2026-07-14T14:15:00Z",
  "detected_sound": "Neh",
  "confidence_score": 0.92,
  "decibel_level": 65
}
```

- `detected_sound`: `Neh` | `Owh` | `Heh` | `Eair` | `Eh` | `Unknown`
- `confidence_score`: 0.0 ~ 1.0
- `decibel_level`: 정수 (dB)

### 방법 1 — MQTT (원격 확인, 권장)

- 기본 브로커: `broker.hivemq.com:1883` (프로토타입용 공개 브로커, 설정에서 변경 가능)
- 발행 토픽: `tiramisu/babycry/{device_id}` (예: `tiramisu/babycry/BABY_MONITOR_01`)
- 앱이 같은 토픽을 구독하여 어디서든 수신

⚠️ 공개 브로커는 누구나 볼 수 있으므로 시연용입니다. 실제 서비스에서는
인증이 있는 자체 브로커(Mosquitto, EMQX 등)를 사용하세요.

### 방법 2 — WebSocket (같은 Wi-Fi)

- ESP32에서 WebSocket 서버 실행 (권장 포트 81)
- 앱 설정에서 `ws://<기기 IP>:81` 입력

### ESP32 예제 펌웨어

[`esp32_firmware_example/`](esp32_firmware_example/) 폴더에 Arduino IDE용
MQTT 발행 예제 스케치가 있습니다.

## 주의

본 제품은 의료기기가 아닌 **육아 보조기기**입니다. 평소와 다른 지속적인 울음,
발열, 호흡곤란 등의 증상이 보이면 반드시 의료기관 진료를 받아 주세요.
