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
| 홈 | (구 탐색하기) 지역별 코스·미션, AI 맞춤 코스 추천·수정 요청, 저장, 출발지(`origin`) 표시 경로 지도, 길찾기(네이버지도 → 없으면 구글맵), 진행 중 일정 배너, 코스 상세 '코스 시작하기' | `/api/courses` 연결 (AI 추천·수정 `POST /api/courses/{id}/refinements`·저장 포함), 일정 시작은 `/api/diaries` |
| 만들기 | 사진 선택 → 스타일·분위기 → 완성 | `/api/shortforms` 연결 (AI 서버 미연결 시 기기 미리보기) |
| 커뮤니티 | 2열 SHORTS 카드, 화면 가운데 영상 1개 자동 재생(길게 누르면 고정), 검색·인기 태그, 상세, 내 글 삭제, 만들기에서 게시 | `/api/community/posts` 연결, 영상 전용(video+cover 필수. AI 렌더 불가 시 사진을 기기에서 1080x1920 mp4 로 만들어 게시). 좋아요·댓글은 서버 미지원 |
| 마이 | 나만의 기록: 발자취 지도·걸음수·메모, 내가 만든 V-log | `/api/diaries` 연결. 내가 만든 V-log 는 업로드한 글 ID 를 기기에 저장 |
| 더보기 | 계정, 내 북마크, 로그아웃, 회원탈퇴 | `/api/auth`, `/api/places/bookmarks` |

기존 홈(지도·서울에서 뭐 하지? `/api/places`)은 더 이상 탭이 아님. 코드는 `Moment/Home` 에 남아 있음.

### 나만의 기록 (일정 다이어리)

- 코스 상세 '코스 시작하기' → `POST /api/diaries` 로 여행 시작. 진행 중 일정은 `GET /api/diaries/active`, 홈 배너로 표시.
- 앱이 위치(CoreLocation, 포그라운드만)와 걸음수(CoreMotion `CMPedometer`, `NSMotionUsageDescription` 필요)를 수집하고, 종료 시 `POST /api/diaries/{id}/complete` 로 걸음수·좌표 포인트를 업로드. 시뮬레이터는 만보기가 없어 걸음수 0.
- 수집한 포인트는 업로드 성공 전까지 UserDefaults 에 보관(앱 종료·실패 대비).
- 칼로리는 추정값(걸음수 × 0.04 kcal).
- 목록 `GET /api/diaries`, 상세 `GET /api/diaries/{id}`, 제목·메모 수정 `PATCH`, 삭제 `DELETE`.

로그인: 이메일, Google(ID 토큰 → `/api/auth/google`). access/refresh 토큰은 Keychain 저장, 401 시 자동 재발급.

백엔드에 요청할 API는 [docs/BACKEND_REQUESTS.md](docs/BACKEND_REQUESTS.md) 참고.
에이전트 작업 규칙은 [CLAUDE.md](CLAUDE.md) 참고.

## 디버그 실행 인자 (Debug 빌드 전용)

- `-guest YES` 로그인 화면 건너뛰기
- `-tab 0~4` 시작 탭 (0 홈, 1 만들기, 2 커뮤니티, 3 마이, 4 더보기)
- `-openCourse <id>` 홈 탭에서 해당 코스 상세를 바로 열기
- `-createDemo 1|2|3` 만들기 화면에 샘플 사진 5장을 넣고 해당 단계로 이동

## 폴더

```
Moment/
  App/        앱 진입점, 탭
  Auth/       로그인·토큰(Keychain)
  Services/   APIClient(DTO 포함), 목업 생성기
  Home/       (탭에서 빠짐) 지도·장소 화면, PlacesStore
  Create/     만들기(숏폼 파이프라인)
  Community/  커뮤니티 탐색·상세
  Reels/      영상 플레이어(공용)
  Tour/       홈 탭(코스 API 화면, TourStore)
  My/         마이 탭(DiaryStore, MyView)
  Theme/ Components/ Models/ Resources/
Config/Info.plist   API 주소, Google 설정, ATS
project.yml         XcodeGen 설정
```
