-- =====================================================================
-- Query de referencia do ROI (mesma logica do painel "Quadrante de Decisao")
-- Serve para validar numeros FORA do Grafana e para auditoria da formula.
-- Exemplo:
--   psql -h <host> -U grafana_ro -d awx \
--     -v dias=30 -v employee_cost_per_minute=2.50 -v aap_cost_per_minute=0.10 \
--     -v manual_time_per_host_minutes=15 \
--     -v custo_por_time="'linux=2.50,security=3.00,cloud=3.00'" \
--     -f 03-roi-core-query.sql
--
-- Formula por job (apenas jobs cujo template tem os 4 eixos de label):
--   hosts            = COUNT(main_jobhostsummary) do job (workflow sem hosts => 1)
--   custo_manual     = hosts * manual_time_per_host_minutes * custo_min(time)
--   custo_automatizado = elapsed_segundos/60 * aap_cost_per_minute
--   economia         = custo_manual - custo_automatizado
--   retorno (x)      = SUM(custo_manual) / SUM(custo_automatizado)
--   horas_economizadas = max((hosts*manual_min - elapsed/60)/60, 0)
-- =====================================================================
\set ON_ERROR_STOP on
WITH team_rates AS (
  -- custo/minuto por time, vindo da variavel :'custo_por_time' no formato time=valor,time=valor
  SELECT lower(trim(split_part(kv, '=', 1))) AS time_area,
         trim(split_part(kv, '=', 2))::numeric AS rate
  FROM regexp_split_to_table(:'custo_por_time', '\s*,\s*') AS kv
  WHERE kv ~ '^\s*[^=]+=\s*[0-9]+(\.[0-9]+)?\s*$'
),
template_labels AS (
  SELECT
    ujtl.unifiedjobtemplate_id AS template_id,
    MAX(CASE WHEN l.name ~ '^time[:=]'        THEN regexp_replace(l.name, '^time[:=]',        '') END) AS time_area,
    MAX(CASE WHEN l.name ~ '^dominio[:=]'     THEN regexp_replace(l.name, '^dominio[:=]',     '') END) AS dominio,
    MAX(CASE WHEN l.name ~ '^criticidade[:=]' THEN regexp_replace(l.name, '^criticidade[:=]', '') END) AS criticidade,
    MAX(CASE WHEN l.name ~ '^ambiente[:=]'    THEN regexp_replace(l.name, '^ambiente[:=]',    '') END) AS ambiente
  FROM main_unifiedjobtemplate_labels ujtl
  JOIN main_label l ON l.id = ujtl.label_id
  GROUP BY ujtl.unifiedjobtemplate_id
),
host_counts AS (
  SELECT job_id, COUNT(*) AS host_count
  FROM main_jobhostsummary
  GROUP BY job_id
),
job_meta AS (
  SELECT
    uj.id                          AS job_id,
    uj.unified_job_template_id     AS template_id,
    ujt.name                       AS template_name,
    org.name                       AS organization_name,
    uj.status,
    uj.elapsed,
    uj.created,
    ct.model                       AS job_type,
    COALESCE(hc.host_count, 0)     AS host_count,
    tl.time_area, tl.dominio, tl.criticidade, tl.ambiente,
    (COALESCE(hc.host_count, 1) * :manual_time_per_host_minutes *
      COALESCE(tr.rate, :employee_cost_per_minute)) AS manual_cost,
    (COALESCE(uj.elapsed,0) / 60.0 * :aap_cost_per_minute)                                      AS automated_cost,
    GREATEST(
      (COALESCE(hc.host_count,1) * :manual_time_per_host_minutes - COALESCE(uj.elapsed,0) / 60.0) / 60.0,
      0
    ) AS hours_saved
  FROM main_unifiedjob uj
  JOIN django_content_type ct           ON ct.id = uj.polymorphic_ctype_id
  LEFT JOIN main_unifiedjobtemplate ujt ON ujt.id = uj.unified_job_template_id
  LEFT JOIN main_organization org       ON org.id = uj.organization_id
  LEFT JOIN host_counts hc              ON hc.job_id = uj.id
  JOIN template_labels tl ON tl.template_id = uj.unified_job_template_id
   AND tl.time_area IS NOT NULL AND tl.dominio IS NOT NULL
   AND tl.criticidade IS NOT NULL AND tl.ambiente IS NOT NULL
  LEFT JOIN team_rates tr               ON tr.time_area = tl.time_area
  WHERE ct.model IN ('job','workflowjob','adhoccommand')
    AND uj.status IN ('successful','failed','error','canceled')
    AND uj.created BETWEEN now() - (:'dias' || ' days')::interval AND now()
    AND tl.time_area    ~ '.*'
    AND tl.dominio      ~ '.*'
    AND tl.criticidade  ~ '.*'
    AND tl.ambiente     ~ '.*'
    AND COALESCE(org.name, '_sem_org') ~ '.*'
)

, base AS (
  SELECT template_name, time_area, dominio,
    COUNT(*) AS freq,
    SUM(manual_cost - automated_cost) AS saving,
    ROUND(SUM(hours_saved)::numeric,1) AS horas
  FROM job_meta WHERE template_name IS NOT NULL
  GROUP BY template_name, time_area, dominio
),
med AS (
  SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY freq)   AS f_med,
         percentile_cont(0.5) WITHIN GROUP (ORDER BY saving) AS s_med
  FROM base
)
SELECT
  b.template_name AS "Automação",
  b.time_area AS "Time", b.dominio AS "Domínio",
  b.freq AS "Execuções",
  ROUND(b.saving::numeric, 2) AS "Economia (R$)",
  b.horas AS "Horas econ.",
  CASE
    WHEN b.freq >= m.f_med AND b.saving >= m.s_med THEN '👑 Joia da coroa'
    WHEN b.freq <  m.f_med AND b.saving >= m.s_med THEN '🚀 Escalar'
    WHEN b.freq >= m.f_med AND b.saving <  m.s_med THEN '🔁 Alto volume / baixo retorno'
    ELSE '🔍 Revisar'
  END AS "Classificação"
FROM base b CROSS JOIN med m
ORDER BY b.saving DESC NULLS LAST LIMIT 20;
