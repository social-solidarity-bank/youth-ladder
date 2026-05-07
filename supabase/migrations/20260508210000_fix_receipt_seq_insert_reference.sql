-- 이미 atomic 마이그레이션을 적용한 뒤 오류(
--   invalid reference to FROM-clause entry for table "application_receipt_seq"
-- )가 나는 경우: UPSERT 의 AS 별칭 문제 → 함수만 교체

CREATE OR REPLACE FUNCTION public.submit_application(p_row jsonb)
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

  INSERT INTO public.application_receipt_seq (day_key, last_seq)
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
