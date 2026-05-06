-- 청년 희망사다리: applications RLS + admin_users
-- 적용: Supabase SQL Editor 또는 supabase db push (CLI)
--
-- 운영 순서 권장:
--   1) 아래 SQL 실행
--   2) INSERT 로 admin_users 에 최소 1명 등록 (미등록 시 관리자 페이지 전원 차단)
--   3) 신청 폼으로 RPC + INSERT 스모크 테스트
--   4) 관리자 로그인으로 목록·상세 확인
--   5) 배포된 admin.html (목록/상세 분리·권한 검사 버전) 반영
--
-- 선행: 예전 정책명(youth-ladder 프로젝트)은 아래 DROP 블록에서 제거함.
--       RLS는 같은 명령에 대한 정책을 OR로 합치므로, anon_can_select 를 남기면 anon 조회가 계속 허용됨.

-- ── 관리자 화이트리스트 ─────────────────────────────────
CREATE TABLE IF NOT EXISTS public.admin_users (
  user_id uuid PRIMARY KEY REFERENCES auth.users (id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.admin_users IS '관리자 뷰어 접근 허용 계정(auth.users.id)';

ALTER TABLE public.admin_users ENABLE ROW LEVEL SECURITY;

-- 본인 행만 조회 가능 (로그인 후 권한 확인용)
DROP POLICY IF EXISTS "admin_users_self_select" ON public.admin_users;
CREATE POLICY "admin_users_self_select"
  ON public.admin_users
  FOR SELECT
  TO authenticated
  USING (user_id = auth.uid());

-- anon은 admin_users 접근 불가 (정책 없음 = 거부)

-- ── applications ─────────────────────────────────────
ALTER TABLE public.applications ENABLE ROW LEVEL SECURITY;

-- 기존 정책 제거 (이름이 하나라도 남으면 보안 목적 실패 가능 — 특히 anon SELECT/UPDATE)
-- 대시보드에 표시된 youth-ladder 쪽 레거시
DROP POLICY IF EXISTS "anon_can_insert" ON public.applications;
DROP POLICY IF EXISTS "anon_can_select" ON public.applications;
DROP POLICY IF EXISTS "anon_can_update" ON public.applications;
DROP POLICY IF EXISTS "anon_insert" ON public.applications;
DROP POLICY IF EXISTS "auth_select" ON public.applications;
-- 이 마이그레이션을 이전에 부분 실행했을 때 생긴 이름
DROP POLICY IF EXISTS "applications_anon_insert" ON public.applications;
DROP POLICY IF EXISTS "applications_admin_select" ON public.applications;
DROP POLICY IF EXISTS "applications_admin_update" ON public.applications;

-- 신청 폼: 익명 INSERT 만
CREATE POLICY "applications_anon_insert"
  ON public.applications
  FOR INSERT
  TO anon
  WITH CHECK (true);

-- 관리자: 목록·상세 SELECT (admin_users 등록자만)
CREATE POLICY "applications_admin_select"
  ON public.applications
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.admin_users au
      WHERE au.user_id = auth.uid()
    )
  );

-- 심사·상태 수정 시 사용 예정 (현재 클라이언트는 미사용이어도 정책만 두면 이후 PATCH 허용)
CREATE POLICY "applications_admin_update"
  ON public.applications
  FOR UPDATE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.admin_users au
      WHERE au.user_id = auth.uid()
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.admin_users au
      WHERE au.user_id = auth.uid()
    )
  );

-- anon UPDATE/DELETE/SELECT 정책 없음 → REST 에서 차단
-- DELETE 미부여 → authenticated 도 삭제 불가 (대시보드 service_role 제외)

-- ── 최초 관리자 1명 등록 (예시, UUID만 교체 후 실행) ────────────────
-- INSERT INTO public.admin_users (user_id)
-- VALUES ('<Supabase Auth Users 에서 복사한 uuid>');

