-- =====================================================================
-- Validacao da taxonomia de labels (pre-requisito do ROI)
-- Executar com qualquer usuario com SELECT (ex.: grafana_ro):
--   psql -h <host> -U grafana_ro -d awx -f 02-validate-taxonomy.sql
-- =====================================================================

\echo '== 1) Valores existentes por eixo (time / dominio / criticidade / ambiente)'
SELECT split_part(l.name, ':', 1) AS eixo,
       split_part(l.name, ':', 2) AS valor,
       o.name                      AS organization,
       COUNT(ujtl.unifiedjobtemplate_id) AS templates
FROM main_label l
JOIN main_organization o ON o.id = l.organization_id
LEFT JOIN main_unifiedjobtemplate_labels ujtl ON ujtl.label_id = l.id
WHERE l.name ~ '^(time|dominio|criticidade|ambiente)[:=]'
GROUP BY 1,2,3 ORDER BY 1,2,3;

\echo '== 2) Cobertura: % de Job Templates + Workflows com os 4 eixos'
WITH labeled AS (
  SELECT ujtl.unifiedjobtemplate_id AS tid,
    bool_or(l.name ~ '^time[:=]')        AS t,
    bool_or(l.name ~ '^dominio[:=]')     AS d,
    bool_or(l.name ~ '^criticidade[:=]') AS c,
    bool_or(l.name ~ '^ambiente[:=]')    AS a
  FROM main_unifiedjobtemplate_labels ujtl
  JOIN main_label l ON l.id = ujtl.label_id
  GROUP BY 1
),
jt AS (
  SELECT ujt.id FROM main_unifiedjobtemplate ujt
  JOIN django_content_type ct ON ct.id = ujt.polymorphic_ctype_id
  WHERE ct.model IN ('jobtemplate','workflowjobtemplate')
)
SELECT COUNT(*) AS templates,
       COUNT(*) FILTER (WHERE lb.t AND lb.d AND lb.c AND lb.a) AS completos,
       ROUND(100.0 * COUNT(*) FILTER (WHERE lb.t AND lb.d AND lb.c AND lb.a) / NULLIF(COUNT(*),0), 1) AS pct
FROM jt LEFT JOIN labeled lb ON lb.tid = jt.id;

\echo '== 3) Templates INCOMPLETOS (nao entram no ROI) e o que falta'
WITH labeled AS (
  SELECT ujtl.unifiedjobtemplate_id AS tid,
    bool_or(l.name ~ '^time[:=]')        AS t,
    bool_or(l.name ~ '^dominio[:=]')     AS d,
    bool_or(l.name ~ '^criticidade[:=]') AS c,
    bool_or(l.name ~ '^ambiente[:=]')    AS a
  FROM main_unifiedjobtemplate_labels ujtl
  JOIN main_label l ON l.id = ujtl.label_id
  GROUP BY 1
)
SELECT o.name AS organization, ct.model AS tipo, ujt.name AS template,
       concat_ws(' ',
         CASE WHEN COALESCE(lb.t,false) THEN '' ELSE 'time' END,
         CASE WHEN COALESCE(lb.d,false) THEN '' ELSE 'dominio' END,
         CASE WHEN COALESCE(lb.c,false) THEN '' ELSE 'criticidade' END,
         CASE WHEN COALESCE(lb.a,false) THEN '' ELSE 'ambiente' END) AS faltando
FROM main_unifiedjobtemplate ujt
JOIN django_content_type ct ON ct.id = ujt.polymorphic_ctype_id
LEFT JOIN main_organization o ON o.id = ujt.organization_id
LEFT JOIN labeled lb ON lb.tid = ujt.id
WHERE ct.model IN ('jobtemplate','workflowjobtemplate')
  AND NOT (COALESCE(lb.t,false) AND COALESCE(lb.d,false) AND COALESCE(lb.c,false) AND COALESCE(lb.a,false))
ORDER BY 1,2,3;

\echo '== 4) Jobs dos ultimos 30 dias: quantos entram no ROI'
WITH tl AS (
  SELECT ujtl.unifiedjobtemplate_id AS tid,
    bool_or(l.name ~ '^time[:=]') t, bool_or(l.name ~ '^dominio[:=]') d,
    bool_or(l.name ~ '^criticidade[:=]') c, bool_or(l.name ~ '^ambiente[:=]') a
  FROM main_unifiedjobtemplate_labels ujtl JOIN main_label l ON l.id = ujtl.label_id GROUP BY 1)
SELECT ct.model AS tipo, COUNT(*) AS jobs,
       COUNT(*) FILTER (WHERE tl.t AND tl.d AND tl.c AND tl.a) AS entram_no_roi,
       ROUND(SUM(COALESCE(uj.elapsed,0))/3600.0, 1) AS horas_execucao
FROM main_unifiedjob uj
JOIN django_content_type ct ON ct.id = uj.polymorphic_ctype_id
LEFT JOIN tl ON tl.tid = uj.unified_job_template_id
WHERE uj.created > now() - interval '30 days'
  AND uj.status IN ('successful','failed','error','canceled')
GROUP BY 1 ORDER BY 2 DESC;

\echo '== 5) Labels fora do padrao eixo:valor (ignoradas pelo dashboard)'
SELECT o.name AS organization, l.name AS label
FROM main_label l JOIN main_organization o ON o.id = l.organization_id
WHERE l.name !~ '^(time|dominio|criticidade|ambiente)[:=]' ORDER BY 1,2;
