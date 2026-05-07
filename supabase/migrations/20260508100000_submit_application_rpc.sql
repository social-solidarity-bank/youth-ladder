-- 공개 신청: REST INSERT 대신 RPC 로 삽입 (anon SELECT 없을 때 PostgREST RETURNING/RLS 이슈 회피)
-- 적용 후: Dashboard → Database → Functions 에서 submit_application 노출, anon EXECUTE 확인

CREATE OR REPLACE FUNCTION public.submit_application(p_row jsonb)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_row IS NULL OR trim(COALESCE(p_row->>'receipt_number', '')) = '' THEN
    RAISE EXCEPTION 'invalid payload: receipt_number required';
  END IF;

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
    trim(p_row->>'receipt_number'),
    COALESCE(trim(p_row->>'name'), ''),
    COALESCE(trim(p_row->>'phone'), ''),
    -- 생년월일: 폼은 숫자 8자리(YYYYMMDD 등). 컬럼이 DATE 타입이면 아래를 to_date(...,'YYYYMMDD') 로 교체.
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
    COALESCE(p_row->'form_data', '{}'::jsonb)
  );
END;
$$;

COMMENT ON FUNCTION public.submit_application(jsonb) IS '신청 폼 전용 삽입. SECURITY DEFINER 로 RLS RETURNING 충돌 없이 INSERT.';

GRANT EXECUTE ON FUNCTION public.submit_application(jsonb) TO anon;
GRANT EXECUTE ON FUNCTION public.submit_application(jsonb) TO authenticated;
