-- 접수번호 + 저장 원자화: 클라이언트에서 generate_receipt_number 분리 호출 시 중복·경합 제거
-- 적용: SQL Editor 전체 실행 (기존 submit_application(jsonb) 반환 타입 변경 → DROP 후 재생성)

CREATE TABLE IF NOT EXISTS public.application_receipt_seq (
  day_key date PRIMARY KEY,
  last_seq integer NOT NULL DEFAULT 0 CHECK (last_seq >= 0)
);

COMMENT ON TABLE public.application_receipt_seq IS 'Asia/Seoul 기준 일자별 접수 접미 순번. submit_application 전용.';

-- 오늘 날짜 접수번호 최대 접미로 시드 (기존 행과 숫자 충돌 방지)
INSERT INTO public.application_receipt_seq (day_key, last_seq)
SELECT ((now() AT TIME ZONE 'Asia/Seoul'))::date,
       COALESCE(MAX(NULLIF(trim(split_part(receipt_number, '-', 3)), '')::int), 0)
FROM public.applications
WHERE receipt_number ~ ('^YH-' || to_char(((now() AT TIME ZONE 'Asia/Seoul'))::date, 'YYYYMMDD') || '-\d+$')
ON CONFLICT (day_key) DO NOTHING;

DROP FUNCTION IF EXISTS public.submit_application(jsonb);

CREATE FUNCTION public.submit_application(p_row jsonb)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  d date := ((now() AT TIME ZONE 'Asia/Seoul'))::date;
  n int;
  v_rn text;
  v_fd jsonb;
BEGIN
  IF p_row IS NULL THEN
    RAISE EXCEPTION 'invalid payload';
  END IF;

  INSERT INTO public.application_receipt_seq AS s (day_key, last_seq)
  VALUES (d, 1)
  ON CONFLICT (day_key) DO UPDATE
    SET last_seq = application_receipt_seq.last_seq + 1
  RETURNING last_seq INTO n;

  v_rn := 'YH-' || to_char(d, 'YYYYMMDD') || '-' || lpad(n::text, 4, '0');

  v_fd := COALESCE(p_row->'form_data', '{}'::jsonb) || jsonb_build_object('접수번호', v_rn);

  INSERT INTO public.applications (
    receipt_number,
    name,
    phone,
    birth_date,
    employment_type,
    income_range,
    loan_amount,
    loan_purpose,
    loan_period,
    qual_age,
    qual_income_150,
    qual_multi_debt,
    qual_high_rate,
    qual_no_overdue,
    qual_no_delinquency,
    q1_background,
    q2_repay_plan,
    q3_repay_plan,
    consent_collect,
    consent_collect_id,
    consent_provide,
    consent_provide_id,
    consent_third_party,
    consent_third_party_id,
    consent_agreed,
    form_data
  )
  VALUES (
    v_rn,
    COALESCE(trim(p_row->>'name'), ''),
    COALESCE(trim(p_row->>'phone'), ''),
    CASE
      WHEN length(regexp_replace(COALESCE(p_row->>'birth_date', ''), '\D', '', 'g')) >= 8
      THEN left(regexp_replace(trim(COALESCE(p_row->>'birth_date', '')), '\D', '', 'g'), 8)
      ELSE NULL
    END,
    NULLIF(trim(p_row->>'employment_type'), ''),
    NULLIF(trim(p_row->>'income_range'), ''),
    COALESCE((p_row->>'loan_amount')::integer, 0),
    NULLIF(trim(p_row->>'loan_purpose'), ''),
    NULLIF(trim(p_row->>'loan_period'), ''),
    COALESCE((p_row->>'qual_age')::boolean, false),
    COALESCE((p_row->>'qual_income_150')::boolean, false),
    COALESCE((p_row->>'qual_multi_debt')::boolean, false),
    COALESCE((p_row->>'qual_high_rate')::boolean, false),
    COALESCE((p_row->>'qual_no_overdue')::boolean, false),
    COALESCE((p_row->>'qual_no_delinquency')::boolean, false),
    COALESCE(trim(p_row->>'q1_background'), ''),
    COALESCE(trim(p_row->>'q2_repay_plan'), ''),
    COALESCE(trim(p_row->>'q3_repay_plan'), ''),
    COALESCE((p_row->>'consent_collect')::boolean, false),
    COALESCE((p_row->>'consent_collect_id')::boolean, false),
    COALESCE((p_row->>'consent_provide')::boolean, false),
    COALESCE((p_row->>'consent_provide_id')::boolean, false),
    COALESCE((p_row->>'consent_third_party')::boolean, false),
    COALESCE((p_row->>'consent_third_party_id')::boolean, false),
    COALESCE((p_row->>'consent_agreed')::boolean, false),
    v_fd
  );

  RETURN v_rn;
END;
$$;

COMMENT ON FUNCTION public.submit_application(jsonb) IS '접수번호 발급+applications INSERT 단일 트랜잭션. 반환값이 접수번호 문자열.';

GRANT EXECUTE ON FUNCTION public.submit_application(jsonb) TO anon;
GRANT EXECUTE ON FUNCTION public.submit_application(jsonb) TO authenticated;
