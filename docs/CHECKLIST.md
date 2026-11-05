# Checklist — portar o dashboard AAP ROI Executivo

## Acesso ao banco do controller
- [ ] Identifiquei host/porta/banco do PostgreSQL do controller (`controller_pg_host`, banco `awx`)
- [ ] Rede liberada: Grafana → PostgreSQL :5432 (firewall / pg_hba / listen_addresses)
- [ ] Executei `sql/01-grafana-readonly-role.sql` como `postgres` (role `grafana_ro` criada)
- [ ] `psql -h <host> -U grafana_ro -d awx -c "select 1"` funciona a partir do host do Grafana

## Grafana
- [ ] Grafana 10.4+ disponível (ou subi `compose/podman-compose.yml` com `.env` preenchido)
- [ ] Datasource PostgreSQL criada (uid `aap-controller-db` se provisionada por arquivo) → "Database Connection OK"
- [ ] Dashboard carregado (provisioning `aap-roi-executive.json` **ou** import `aap-roi-executive.import.json`)

## Taxonomia (sem isso não há ROI)
- [ ] Vocabulário definido e registrado: valores de `time:`, `dominio:`, `criticidade:`, `ambiente:`
- [ ] Labels aplicadas em todos os Job Templates e Workflows (`ansible/apply-labels.yml` ou UI)
- [ ] `sql/02-validate-taxonomy.sql` → cobertura ≥ 90 % e seção 3 vazia (ou só com templates que devem ficar fora)

## Calibração
- [ ] `employee_cost_per_minute` e `custo_por_time` com valores reais de custo/minuto por time
- [ ] `aap_cost_per_minute` = (subscrição/12 + infra mensal) ÷ minutos executados no mês
- [ ] `manual_time_per_host_minutes` acordado com os donos das automações (média por host)
- [ ] Defaults salvos no JSON (ou dashboard salvo na UI) e moeda/período ajustados

## Validação
- [ ] "Cobertura Taxonomia" > 0 % e "Jobs Executados" coerente com a tela Jobs do controller
- [ ] Um número conferido com `sql/03-roi-core-query.sql`
- [ ] Dashboard compartilhado (link / public dashboard / snapshot) com os executivos
