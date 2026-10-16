# StudyHelper (메뉴 막대 학습 보조)

화면의 한국어 문제를 5초마다 OCR(Apple Vision)로 읽고, 문제가 바뀌었을 때만 `claude -p`로 분석해 메뉴 막대에 답을 표시합니다.

- 객관식: `①`~`⑤`
- 단답형: 짧은 텍스트
- 판단 불가: `?`
- Claude 실행 오류(미설치, 로그인 만료 등): `⚠︎` (30초 뒤 자동 재시도, 메뉴의 상태 줄에 원인 표시)
- 분석 중: `…`, 중지 상태: `학습`

## 요구 사항

- macOS 14 이상, Xcode 15 이상(또는 Command Line Tools의 Swift 5.9+)
- Claude Code CLI 설치 및 로그인 완료 (`claude` 실행 후 `/login`). API 키는 쓰지 않으며, 앱이 하위 프로세스 환경에서 `ANTHROPIC_API_KEY`를 제거합니다.

## 빌드와 실행

```bash
./build.sh
open build/StudyHelper.app
```

1. 메뉴 막대의 `학습` → **시작**
2. 처음 실행하면 화면 기록 권한 요청이 뜹니다. **시스템 설정 → 개인정보 보호 및 보안 → 화면 및 시스템 오디오 녹음**에서 StudyHelper를 허용한 뒤 앱을 재시작하세요.
3. **캡처 영역 선택…** → 문제와 선택지가 있는 부분만 드래그하세요(ESC는 취소). 영역을 좁힐수록 OCR 정확도와 변경 감지가 좋아집니다. **전체 화면으로 초기화**를 누르면 주 화면 전체를 캡처합니다.

## 동작 방식

| 파일 | 역할 |
|---|---|
| `ScreenCapturer.swift` | ScreenCaptureKit(`SCScreenshotManager`)으로 Retina 해상도 캡처 후 선택 영역을 자름 |
| `TextRecognizer.swift` | Vision `VNRecognizeTextRequest`(ko-KR, en-US, accurate) |
| `AppModel.swift` | 5초 루프. 전체 화면 모드에서는 메뉴 막대를 빼고 캡처. 분석 중 문제가 바뀌면 즉시 재분석 |
| `Analysis.swift` | 줄 단위로 비교해 새 줄이 생기면 새 문제로 판단(숫자만 바뀐 줄 1개, 예: 타이머는 무시). 응답 파싱(`③`, `3번` → `③`, 거절·설명 문장 → `?`) |
| `ClaudeRunner.swift` | 로그인 셸에서 `claude` 경로와 PATH를 찾아 `claude -p --system-prompt <답 전용> --tools ""` 실행(120초 타임아웃) |
| `RegionSelector.swift` | 드래그로 캡처 영역을 고르는 오버레이 |

## 문제 해결

- 다시 빌드하면 ad-hoc 서명이 바뀌어 화면 기록 권한이 풀릴 수 있습니다. 이때는 `tccutil reset ScreenCapture com.saikyo.studyhelper` 후 다시 허용하세요. 개발자 인증서가 있다면 `CODESIGN_IDENTITY="Apple Development: ..." ./build.sh`로 빌드하면 권한이 유지됩니다.
- 메뉴에 `claude CLI를 찾을 수 없음`이 보이면 터미널에서 `command -v claude`로 경로를 확인하세요. 앱은 `~/.local/bin`, `~/.claude/local`, `/opt/homebrew/bin`, `/usr/local/bin` 등을 찾아봅니다.
- OCR 확인: `build/StudyHelper.app/Contents/MacOS/StudyHelper --ocr-test 이미지.png`
