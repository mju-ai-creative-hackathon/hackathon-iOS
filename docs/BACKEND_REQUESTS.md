# 백엔드 API 요청 (iOS → 백엔드)

iOS 앱에서 아직 목업으로 돌고 있는 기능과, 붙이기 위해 필요한 API입니다.
필드 이름·경로는 제안이며 백엔드에서 정해주면 앱을 맞춥니다.

## 1. 커뮤니티 — 탐색/등록/삭제는 연결 완료 (#4)

영상 전용(`post` JSON + `video` + `cover`) 등록도 연결 완료.

남은 요청:

- 좋아요 `PUT/DELETE /api/community/posts/{id}/like`, 댓글 `GET/POST /api/community/posts/{id}/comments`
- 내 게시물 목록 `GET /api/community/posts/mine` — explore 는 로그인 시 본인 글을 제외해서, 올린 뒤 내 글을 볼 곳이 없음
- 숏폼 렌더 결과를 바로 게시하는 방법(`renderId` 로 게시) — 지금은 앱이 결과 영상을 내려받아 다시 업로드해야 함

## 2. 탐색하기 코스·미션 — 연결 완료

연결된 API: `GET /api/courses/regions`, `GET /api/courses`, `GET /api/courses/{id}`(정차지·구간·길찾기 URL·미션), `POST /api/courses/recommendations`(AI 맞춤), `PUT/DELETE /api/courses/{id}/save`, `GET /api/courses/saved`.
숏폼 제작 시 `courseId` + `missionIds` 를 보내 AI `shootingHints` 에 연결함.

남은 요청: 미션 촬영물(PHOTO/VIDEO)이 지금은 앱 메모리에만 있어 재시작 시 사라지고 도장 기록도 없음.

| 메서드 | 경로 | 용도 |
| --- | --- | --- |
| POST | `/api/courses/{id}/missions/{missionId}/stamp` | 미션 촬영물 업로드(multipart) + 도장 처리. 위치 검증이 필요하면 `latitude, longitude` 함께 전송. 또는 숏폼 업로드 시 코스 미션 ID 를 연결하는 방식도 가능 |
| GET | `/api/me/stamps` | 내 도장 현황(홈 '나의 도장 현황' 카드용) |

- ID 통일 필요: 숏폼 `sources[].missionId` 는 UUID, 코스 미션 ID 는 숫자라 서로 연결이 안 됨 → 한쪽으로 맞춰주세요.

## 3. 작은 개선

- `GET /api/places` 목록 항목에 `latitude`, `longitude` 추가 → 지금은 지도 핀 때문에 상세를 12번 호출함
- 장소 `imageUrl` 이 picsum 랜덤 이미지라 장소와 무관한 사진이 나옴 → 실제 사진 URL로 교체
- 숏폼 `musicId` 목록(AI 담당과 합의) → 앱의 배경 음악 선택이 지금은 화면에만 있고 서버로 보내지 않음
- 숏폼 AI 서버 연결(`SHORTFORM_AI_ENABLED`, `SHORTFORM_AI_BASE_URL`) → 운영 `renderingAvailable=false` 라 제작 요청이 503
- 회원탈퇴 시 숏폼 프로젝트·업로드 원본도 함께 삭제되는지 확인
