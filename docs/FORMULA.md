# Fórmula do ROI

Calculada por job, apenas para jobs cujo template tem os 4 eixos de label, dentro do intervalo de tempo do dashboard (coluna `created`).

## Universo

| Critério | Valor |
|---|---|
| Tipos (`django_content_type.model`) | `job`, `workflowjob`, `adhoccommand` |
| Status | `successful`, `failed`, `error`, `canceled` |
| Excluídos | `projectupdate`, `inventoryupdate`, `systemjob`, jobs em andamento |

## Por job

```
hosts               = COUNT(*) em main_jobhostsummary do job      (sem linhas, ex. workflow ⇒ 1)
custo_min(time)     = valor do time em custo_por_time             (ausente ⇒ employee_cost_per_minute)
custo_manual        = hosts × manual_time_per_host_minutes × custo_min(time)
custo_automatizado  = elapsed_segundos ÷ 60 × aap_cost_per_minute
economia            = custo_manual − custo_automatizado
horas_economizadas  = max( (hosts × manual_time_per_host_minutes − elapsed_segundos ÷ 60) ÷ 60 , 0 )
```

## Agregados

```
Economia Total        = Σ economia
Retorno (×)           = Σ custo_manual ÷ Σ custo_automatizado
Horas Economizadas    = Σ horas_economizadas
Taxa de Sucesso       = successful ÷ (successful + failed + error + canceled) × 100
Hosts Impactados      = COUNT(DISTINCT host) em main_jobhostsummary dos jobs do período
Automações Ativas     = COUNT(DISTINCT template) com job no período
Cobertura Taxonomia   = templates com 4 eixos ÷ templates (JT + WF) × 100   (não depende do período)
Quadrante de Decisão  = frequência (execuções) × economia, classificação por mediana
```

## Decisões embutidas (e onde mudar)

| Decisão | Motivo | Onde mudar |
|---|---|---|
| Jobs falhos/cancelados geram economia | o esforço manual evitado é o mesmo; a falha aparece na taxa de sucesso | `WHERE` de `job_meta`: `AND uj.status = 'successful'` |
| Workflow sem hosts conta como 1 host | evita zerar economia de workflows | `COALESCE(hc.host_count, 1)` |
| Horas economizadas nunca negativas | job mais lento que o manual não "deve" horas | `GREATEST(..., 0)` |
| Ad-hoc commands entram | são trabalho automatizado real | remover `'adhoccommand'` de `ct.model IN (...)` |

As 26 queries de valor compartilham o mesmo CTE `job_meta`; alterar a regra significa alterar nas 26
(busca e substituição no JSON funciona porque o texto é idêntico). `sql/03-roi-core-query.sql` tem a mesma
lógica em SQL puro para auditoria.
