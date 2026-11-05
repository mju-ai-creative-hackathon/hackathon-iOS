# 설로그 (Seollog) iOS

서울의 순간을 AI 숏폼으로 만들고 공유하는 앱. SwiftUI · iOS 17+.

## 실행

```bash
brew install xcodegen        # 처음 한 번
xcodegen generate            # Moment.xcodeproj 생성 (git 에는 포함하지 않음)
open Moment.xcodeproj
```

- 실행 대상: iPhone 시뮬레이터. 실기기는 Xcode → Signing & Capabilities 에서 팀 지정 필요
- 번들 ID: `com.mju.hackathon.moment` (Google iOS 클라이언트와 일치해야 함)
- 패키지: GoogleSignIn-iOS (SPM, xcodegen 이 자동 추가)

## 백엔드

- 기본 주소: `https://3-39-47-78.sslip.io` (`Config/Info.plist` 의 `API_BASE_URL`)
- 로컬 서버로 테스트: Xcode 스킴 실행 인자에 `-apiBaseURL http://localhost:8080`
- 앱에는 비밀값이 없음. Google Client ID 는 공개 값이며 Client Secret 은 서버에만 둔다.

## 화면 / 연결 상태

| 탭 | 내용 | 백엔드 |
| --- | --- | --- |
| 홈 | 지도, 서울에서 뭐 하지?(장소·카테고리·북마크) | `/api/places` 연결 |
| 만들기 | 사진 선택 → 스타일·분위기 → 완성 | `/api/shortforms` 연결 (AI 서버 미연결 시 기기 미리보기) |
| 커뮤니티 | 숏폼 피드 | 목업 — API 필요 |
| 탐색하기 | 여행 도장깨기 코스·미션 | 목업 — API 필요 |
| 더보기 | 계정, 내 북마크, 로그아웃, 회원탈퇴 | `/api/auth`, `/api/places/bookmarks` |

로그인: 이메일, Google(ID 토큰 → `/api/auth/google`). access/refresh 토큰은 Keychain 저장, 401 시 자동 재발급.

백엔드에 요청할 API는 [docs/BACKEND_REQUESTS.md](docs/BACKEND_REQUESTS.md) 참고.

## 디버그 실행 인자 (Debug 빌드 전용)

- `-guest YES` 로그인 화면 건너뛰기
- `-tab 0~4` 시작 탭 (0 홈, 1 만들기, 2 커뮤니티, 3 탐색하기, 4 더보기)
- `-createDemo 1|2|3` 만들기 화면에 샘플 사진 5장을 넣고 해당 단계로 이동

## 폴더

```
Moment/
  App/        앱 진입점, 탭
  Auth/       로그인·토큰(Keychain)
  Services/   APIClient(DTO 포함), 목업 생성기
  Home/       홈, 장소 API 상태(PlacesStore)
  Create/     만들기(숏폼 파이프라인)
  Reels/      커뮤니티 피드
  Tour/       도장깨기
  Theme/ Components/ Models/ Resources/
Config/Info.plist   API 주소, Google 설정, ATS
project.yml         XcodeGen 설정
```
