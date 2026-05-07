# Supabase 보안 정책 · 점검 가이드 (청년 희망사다리)

이 문서는 긴급 과제 체크리스트의 **적용 가능 여부**, **역할별 허용 범위**, **점검용 요청**을 정리한다.

---

## 1. 체크리스트별 적용 가능 여부

| # | 항목 | 적용 가능 여부 | 비고 |
|---|------|----------------|------|
| 1 | `applications` RLS 활성화, anon SELECT/UPDATE/DELETE 차단, anon INSERT만 | **즉시 적용 가능** | 저장소의 `supabase/migrations/20260507120000_applications_rls_admin_users.sql`를 Supabase에 실행 |
| 2 | `admin_users` + authenticated 관리자만 SELECT | **즉시 적용 가능** | 마이그레이션에 포함. 적용 후 **반드시** 최소 1명 `INSERT INTO admin_users` |
| 3 | 관리자 페이지 `.select('*')` 제거, 목록/상세 분리 | **적용 완료 (코드)** | `admin.html` — 목록은 최소 컬럼, 상세는 `id` 기준 1건 조회 |
| 4 | `form_data` 저장 범위 재검토·별도 테이블 | **중기 과제** | 신청 스키마/`collectData`/관리자 UI 동시 변경 필요. RLS와 별개로 계획 수립 권장 |
| 5 | 정책 점검 SQL 문서화 | **본 문서 + 마이그레이션 SQL** | curl 예시는 §5 참고 |
| 6 | 로그인 후 `admin_users` 검증, 무권한 시 메시지·로그아웃 | **적용 완료 (코드)** | `admin.html` 의 `ensureAdminOrBail` |
| 7 | `generate_receipt_number` RPC anon 허용 유지 | **마이그레이션 외 확인 필요** | Supabase Dashboard → Database → Functions 에서 정의·`SECURITY` 확인 |
| 8 | 기존 데이터 노출: anon으로 GET/PATCH/DELETE 차단, POST 신청만 성공 | **RLS 적용 후 검증** | §5 curl 로 재확인 |

---

## 2. 테이블별 허용 역할

### `public.applications`

| 작업 | `anon` | `authenticated` (일반 로그인) | `authenticated` + `admin_users` 행 존재 |
|------|--------|-------------------------------|----------------------------------------|
| SELECT | 불가 | 불가 | 가능 |
| INSERT | 가능 | (신청 페이지는 anon 키 사용 시 해당) | - |
| UPDATE | 불가 | 불가 | 가능 (정책 적용 시) |
| DELETE | 불가 | 불가 | 불가 (정책 미부여 가정) |

### `public.admin_users`

| 작업 | `anon` | `authenticated` |
|------|--------|-------------------|
| SELECT | 불가 | 본인 `user_id = auth.uid()` 행만 |
| INSERT/UPDATE/DELETE | 불가 | 클라이언트 정책 없음 → Dashboard / service_role 로만 등록 권장 |

---

## 3. 관리자 판별 기준

- Supabase Auth로 로그인한 사용자의 `auth.uid()`가 `admin_users.user_id`에 존재하면 관리자.
- 존재하지 않으면 관리자 UI는 **데이터 로드 전** 로그아웃하고 안내 메시지를 표시한다 (`admin.html`).

**최초 등록 예시 (SQL Editor):**

```sql
INSERT INTO public.admin_users (user_id)
VALUES ('<auth.users 의 uuid>');
```

---

## 4. 배포 순서 (접수 유지 관점)

1. SQL 마이그레이션 실행 (RLS + 정책 + `admin_users` 테이블).
2. **관리자 1명 이상** `admin_users`에 수동 삽입 (미삽입 시 관리자 화면은 모두 차단됨).
3. 신청 페이지에서 **제출 스모크 테스트** (RPC + INSERT).
4. 관리자 계정으로 로그인해 **목록·상세** 확인.
5. §5 curl로 anon 차단 확인.

---

## 5. 점검용 curl (anon 키는 클라이언트와 동일)

`SUPABASE_URL`, `ANON_KEY` 를 환경에 맞게 설정한다.

```bash
export SUPABASE_URL='https://<project>.supabase.co'
export ANON_KEY='<anon jwt>'
```

**기대: 실패 (401 또는 RLS로 빈/에러)**

```bash
curl -sS -w "\nHTTP:%{http_code}\n" \
  "$SUPABASE_URL/rest/v1/applications?select=id&limit=1" \
  -H "apikey: $ANON_KEY" -H "Authorization: Bearer $ANON_KEY"
```

```bash
curl -sS -w "\nHTTP:%{http_code}\n" -X PATCH \
  "$SUPABASE_URL/rest/v1/applications?id=eq.00000000-0000-0000-0000-000000000000" \
  -H "apikey: $ANON_KEY" -H "Authorization: Bearer $ANON_KEY" \
  -H "Content-Type: application/json" -d '{"name":"x"}'
```

```bash
curl -sS -w "\nHTTP:%{http_code}\n" -X DELETE \
  "$SUPABASE_URL/rest/v1/applications?id=eq.00000000-0000-0000-0000-000000000000" \
  -H "apikey: $ANON_KEY" -H "Authorization: Bearer $ANON_KEY"
```

**기대: RPC 200 (신청 경로)**

```bash
curl -sS -w "\nHTTP:%{http_code}\n" -X POST \
  "$SUPABASE_URL/rest/v1/rpc/generate_receipt_number" \
  -H "apikey: $ANON_KEY" -H "Authorization: Bearer $ANON_KEY" \
  -H "Content-Type: application/json" -d '{}'
```

**INSERT 스모크 (실제 삽입이 되므로 스테이징 권장)**  
정책이 `WITH CHECK (true)` 이면 anon INSERT 허용. 컬럼·NOT NULL 제약에 맞는 최소 JSON 을 사용한다.  
PostgREST 에서 `Prefer: return=representation`(삽입 행 반환)을 쓰면, 반환 행을 읽기 위해 **SELECT RLS**까지 통과해야 해서 anon 에서는 `new row violates row-level security policy` 가 날 수 있다. **`Prefer: return=minimal`** 로 두면 회피된다. CDN용 `supabase-js` 가 옵션을 무시하는 경우가 있어, 신청 페이지는 REST **`fetch`로 `Prefer: return=minimal` 고정**한다.

---

## 6. `generate_receipt_number` 확인 항목 (대시보드)

- `EXECUTE` 가 `anon` 에게 허용되는지.
- 함수 본문이 접수번호 생성 외 불필요한 테이블 SELECT/과다 권한을 쓰지 않는지.
- `SECURITY DEFINER` 인 경우 `search_path` 고정 및 최소 권한 원칙 준수 여부.

---

## 7. `form_data` 중복 저장 (중기)

- 현재는 컬럼과 JSON 양쪽에 유사 정보가 많아, RLS 실패 시에도 노출 단면이 넓어질 수 있다.
- 권장 방향: 심사에 필요한 필드 정규화, 고민밀 서술·주소 등은 별도 테이블 + 관리자 전용 RPC/view.
- **RLS 긴급 조치와 독립**으로 스펙·마이그레이션 일정을 잡는 것이 안전하다.

---

## 8. 트러블슈팅: 공개 신청 제출 시 RLS 오류

- 증상: `new row violates row-level security policy for table "applications"` (또는 유사 메시지).
- 원인 후보: PostgREST **직접 INSERT** 시 행 반환 경로가 SELECT RLS 와 겹침 (환경·버전에 따라 **`Prefer: return=minimal` 로도 해결 안 되는 경우** 있음).
- **권장 조치·현재 구현**: `submit_application(jsonb)` **`SECURITY DEFINER` RPC** 로 삽입 (`supabase/migrations/20260508100000_submit_application_rpc.sql`). 클라이언트는 `sb.rpc('submit_application', { p_row: payload })`. Supabase SQL Editor 에 해당 함수 생성·**anon GRANT EXECUTE** 까지 적용해야 함.

