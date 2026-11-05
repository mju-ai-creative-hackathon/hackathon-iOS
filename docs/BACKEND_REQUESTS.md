# 백엔드 API 요청 (iOS → 백엔드)

iOS 앱에서 아직 목업으로 돌고 있는 기능과, 붙이기 위해 필요한 API입니다.
필드 이름·경로는 제안이며 백엔드에서 정해주면 앱을 맞춥니다.

## 1. 커뮤니티 — 탐색/등록/삭제는 연결 완료 (#4)

영상 전용(`post` JSON + `video` + `cover`) 등록도 연결 완료.

남은 요청:

- 좋아요 `PUT/DELETE /api/community/posts/{id}/like`, 댓글 `GET/POST /api/community/posts/{id}/comments`
- 내 게시물 목록 `GET /api/community/posts/mine` — 여전히 필요. explore 는 로그인 시 본인 글을 제외하고, 앱은 '내가 만든 V-log' 용으로 업로드한 글 ID 를 기기에만 저장 중이라 재설치하면 사라짐
- 숏폼 렌더 결과를 바로 게시하는 방법(`renderId` 로 게시) — 지금은 앱이 결과 영상을 내려받아 다시 업로드해야 함

## 2. 탐색하기 코스·미션 — 연결 완료

연결된 API: `GET /api/courses/regions`, `GET /api/courses`, `GET /api/courses/{id}`(정차지·구간·길찾기 URL·미션), `POST /api/courses/recommendations`(AI 맞춤), `PUT/DELETE /api/courses/{id}/save`, `GET /api/courses/saved`.
숏폼 제작 시 `courseId` + `missionIds` 를 보내 AI `shootingHints` 에 연결함.

연결 추가: 코스 수정 요청 `POST /api/courses/{id}/refinements`(새 안으로 추가). 코스 `origin`(출발지)은 경로 지도에 표시.

> 앱에서 촬영 미션은 소개만 보여주고 촬영·도장은 제거함. 아래 도장 API 는 일정 다이어리 API(`/api/diaries`)로 대체되어 당장은 필요 없음(도장을 다시 살릴 때만 유효).

(보류) 미션 촬영물(PHOTO/VIDEO)이 앱 메모리에만 있어 재시작 시 사라지고 도장 기록도 없던 문제.

| 메서드 | 경로 | 용도 |
| --- | --- | --- |
| POST | `/api/courses/{id}/missions/{missionId}/stamp` (보류) | 미션 촬영물 업로드(multipart) + 도장 처리. 위치 검증이 필요하면 `latitude, longitude` 함께 전송. 또는 숏폼 업로드 시 코스 미션 ID 를 연결하는 방식도 가능 |
| GET | `/api/me/stamps` (보류) | 내 도장 현황 |

- ID 통일 필요: 숏폼 `sources[].missionId` 는 UUID, 코스 미션 ID 는 숫자라 서로 연결이 안 됨 → 한쪽으로 맞춰주세요.

## 3. 일정 다이어리 — 연결 완료

`POST /api/diaries`(시작), `GET /active`, `POST /{id}/complete`(걸음수·포인트), `GET` 목록·상세, `PATCH`(제목·메모), `DELETE` 연결. 위치는 포그라운드 수집만(백그라운드 미지원, 데모엔 충분). 칼로리는 앱이 걸음수 × 0.04 로 추정.

남은 요청:

- 다이어리 ↔ 숏폼 연결: 숏폼/커뮤니티 글에 `diaryId` 를 달 수 있게 해서, V-log 가 어떤 여행에서 나왔는지 보여주기
- 커뮤니티 영상·커버 응답이 `Cache-Control: no-store` 라 스크롤마다 다시 받음 → `public, max-age=86400, immutable` 로 변경. 가능하면 저해상도 `previewUrl` 도 추가(2열 카드 자동 재생용)
- 일부 시드 커버 이미지가 거의 흰색이라 카드가 비어 보임 → 교체

## 4. 작은 개선

- `GET /api/places` 목록 항목에 `latitude`, `longitude` 추가 → 지금은 지도 핀 때문에 상세를 12번 호출함
- 장소 `imageUrl` 이 picsum 랜덤 이미지라 장소와 무관한 사진이 나옴 → 실제 사진 URL로 교체
- 숏폼 `musicId` 목록(AI 담당과 합의) → 앱의 배경 음악 선택이 지금은 화면에만 있고 서버로 보내지 않음
- 숏폼 AI 서버 연결(`SHORTFORM_AI_ENABLED`, `SHORTFORM_AI_BASE_URL`) → 운영 `renderingAvailable=false` 라 제작 요청이 503
- 회원탈퇴 시 숏폼 프로젝트·업로드 원본도 함께 삭제되는지 확인
