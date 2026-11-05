# aap-roi-dashboard

Dashboard Grafana de **ROI executivo** para o **Ansible Automation Platform 2.5 / 2.7**: economia (R$),
retorno (×), horas economizadas, taxa de sucesso e ranking de automações, fatiados por time, domínio,
criticidade, ambiente e organization. Lê **diretamente o PostgreSQL do Automation Controller**: sem agente,
exporter, Prometheus ou Automation Analytics.

```
┌──────────────┐   SQL (SELECT, role grafana_ro)   ┌──────────────────────────────────┐
│   Grafana    │ ────────────────────────────────▶ │ PostgreSQL do Automation Controller│
│  dashboard   │                                   │ banco "awx", 7 tabelas main_*      │
└──────────────┘                                   └──────────────────────────────────┘
        ▲                                                           ▲
   parâmetros de custo                                   labels nos Job Templates
   (variáveis do dashboard)                              time: / dominio: / criticidade: / ambiente:
```

Testado em AAP 2.7 (controller 4.8.3, PostgreSQL 15) com Grafana 13.0.2. Funciona em Grafana ≥ 10.4.

## Conteúdo

```
.
├── README.md                     ← este guia
├── docs/
│   ├── GUIA-RAPIDO.md            ← versão resumida dos passos (para repassar a um time)
│   ├── CHECKLIST.md              ← lista de marcação
│   ├── TAXONOMIA-LABELS.md       ← convenção das 4 labels
│   └── FORMULA.md                ← como o ROI é calculado e onde mudar regras
├── grafana/
│   ├── dashboards/
│   │   ├── aap-roi-executive.import.json   ← import pela UI (pergunta a datasource)
│   │   └── aap-roi-executive.json          ← provisioning por arquivo (uid fixo aap-controller-db)
│   └── provisioning/
│       ├── datasources/aap-controller-db.yaml  ← datasource via variáveis de ambiente
│       └── dashboards/aap-roi.yaml             ← provider (pasta "AAP")
├── compose/
│   ├── podman-compose.yml        ← Grafana standalone (podman-compose / docker compose)
│   └── .env.example
├── sql/
│   ├── 01-grafana-readonly-role.sql   ← cria grafana_ro (SELECT em 7 tabelas, read-only, timeout)
│   ├── 02-validate-taxonomy.sql       ← cobertura de labels e o que falta
│   └── 03-roi-core-query.sql          ← fórmula em SQL puro para auditoria
└── ansible/
    ├── apply-labels.yml          ← aplica as 4 labels nos templates (ansible.controller)
    ├── vars/labels-example.yml   ← exemplo de vocabulário e lista de templates
    ├── requirements.yml
    └── ansible.cfg
```

## Pré-requisitos

| Item | Mínimo |
|---|---|
| AAP | 2.5 ou 2.7. As tabelas usadas são estáveis desde o 2.4. |
| PostgreSQL do controller | 13+ (AAP instala 15). Alcançável via TCP pelo Grafana. |
| Grafana | 10.4+. Datasource PostgreSQL é nativa; **nenhum plugin**. |
| Para o playbook de labels | collection `ansible.controller` ≥ 4.5 (está no EE *supported*) |

Tabelas lidas (schema `public`, banco `awx`): `main_unifiedjob`, `main_unifiedjobtemplate`,
`main_unifiedjobtemplate_labels`, `main_label`, `main_organization`, `main_jobhostsummary`, `django_content_type`.

---

## Instalação passo a passo

### 1. Liberar acesso ao banco do controller

Descubra o host do PostgreSQL no inventário do instalador (`controller_pg_host`, `controller_pg_database`, normalmente `awx`).

| Instalação | O que fazer |
|---|---|
| **Containerizada (podman)** | O container `postgresql` roda em rede *host*, porta 5432, e o `pg_hba.conf` já traz `host all all all md5`. Libere o firewall no host do AAP: `firewall-cmd --add-port=5432/tcp --permanent && firewall-cmd --reload`. Se o Grafana for subir **no mesmo host** em podman, use `AAP_PG_HOST=host.containers.internal` (o compose já configura `extra_hosts`). |
| **RPM** | `postgresql.conf`: `listen_addresses = '*'`. `pg_hba.conf`: `host awx grafana_ro <ip-do-grafana>/32 scram-sha-256`. `systemctl reload postgresql`. Libere a porta 5432. |
| **Banco externo / gerenciado** | O DBA libera o IP do Grafana e executa o script do passo 2. |
| **OpenShift (operator)** | O banco é um pod sem exposição externa. Rode o Grafana dentro do cluster apontando para o Service `<instância>-postgres-15:5432`, ou exponha via Service `LoadBalancer`/`NodePort`. Banco externo ao cluster: trate como "banco externo". |

### 2. Criar a role de leitura

Nunca use `awx` ou `postgres` no Grafana. Execute como superusuário no banco `awx`:

```bash
# containerizado
podman exec -i postgresql psql -U postgres -d awx -v grafana_ro_password="'SenhaForte'" < sql/01-grafana-readonly-role.sql
# RPM
sudo -u postgres psql -d awx -v grafana_ro_password="'SenhaForte'" -f sql/01-grafana-readonly-role.sql
```

A role recebe só `SELECT` nas 7 tabelas, `statement_timeout = 60s` e `default_transaction_read_only = on`.
Teste a partir do servidor do Grafana:

```bash
psql -h <host-do-banco> -U grafana_ro -d awx -c "select count(*) from main_unifiedjob"
```

### 3. Grafana

Já tem Grafana ≥ 10.4? Vá ao passo 4. Senão, suba o incluído:

```bash
cd compose && cp .env.example .env && vi .env     # senha admin, host do banco, senha do grafana_ro, sslmode
podman-compose up -d                              # ou: docker compose up -d
```

O compose já monta `grafana/provisioning` e `grafana/dashboards`; ao subir, datasource e dashboard aparecem prontos (passos 4 e 5 ficam automáticos).

### 4. Datasource

**A) Pela UI.** Connections → Data sources → Add data source → PostgreSQL:

| Campo | Valor |
|---|---|
| Name | `AAP Controller DB` |
| Host | `<host-do-banco>:5432` |
| Database | `awx` |
| User / Password | `grafana_ro` / senha do passo 2 |
| TLS/SSL Mode | `require` (o PostgreSQL do AAP sobe com certificado) ou `disable` |
| Version | `15` |

Save & test → "Database Connection OK". Não precisa anotar UID.

**B) Por provisioning.** Copie `grafana/provisioning/datasources/aap-controller-db.yaml` para
`/etc/grafana/provisioning/datasources/` e exporte no ambiente do Grafana: `AAP_PG_HOST`, `AAP_PG_PORT`,
`AAP_PG_DATABASE`, `AAP_PG_USER`, `AAP_PG_PASSWORD`, `AAP_PG_SSLMODE`. O uid `aap-controller-db` precisa ser mantido.

### 5. Dashboard

**A) Import pela UI.** Dashboards → New → Import → Upload `grafana/dashboards/aap-roi-executive.import.json` →
no campo "Banco do Automation Controller (PostgreSQL)" escolha a datasource do passo 4 → Import.

**B) Provisioning.** Copie `grafana/dashboards/aap-roi-executive.json` para `/etc/grafana/dashboards/` e
`grafana/provisioning/dashboards/aap-roi.yaml` para `/etc/grafana/provisioning/dashboards/`. Reinicie o Grafana.
O dashboard aparece na pasta **AAP**.

### 6. Rotular os templates (obrigatório)

O ROI só considera jobs cujo template tem **4 labels, uma por eixo**:

| Label | Significado | Exemplos |
|---|---|---|
| `time:<valor>` | time dono (chave do custo/minuto) | `time:linux`, `time:security` |
| `dominio:<valor>` | o que a automação faz | `dominio:patching`, `dominio:provisioning` |
| `criticidade:<valor>` | risco/valor protegido | `alta` · `media` · `baixa` |
| `ambiente:<valor>` | onde atua | `prd` · `hml` · `dev` |

Formato: minúsculo, sem acento, sem espaço, um único `:`. Convenção completa em [docs/TAXONOMIA-LABELS.md](docs/TAXONOMIA-LABELS.md).

Aplicar como código:

```bash
cd ansible
ansible-galaxy collection install -r requirements.yml
export CONTROLLER_HOST=https://aap.exemplo.local
export CONTROLLER_OAUTH_TOKEN=<token com escopo write>
export CONTROLLER_VERIFY_SSL=true
cp vars/labels-example.yml vars/labels.yml && vi vars/labels.yml
ansible-playbook apply-labels.yml -e @vars/labels.yml --check --diff   # revisar
ansible-playbook apply-labels.yml -e @vars/labels.yml                  # aplicar
```

`labels` no módulo é declarativo: a lista enviada vira a lista final do template. Revise o `--diff`.

Verifique o que falta: `psql -h <host> -U grafana_ro -d awx -f sql/02-validate-taxonomy.sql`.

### 7. Calibrar os custos

Variáveis no topo do dashboard:

| Variável | Significado | Default |
|---|---|---|
| `employee_cost_per_minute` | custo/minuto de trabalho manual para times fora do mapa | 2.50 |
| `custo_por_time` | mapa `time=valor,time=valor` com custo/minuto por valor da label `time:` | exemplo |
| `aap_cost_per_minute` | custo/minuto de execução no AAP | 0.10 |
| `manual_time_per_host_minutes` | minutos que a tarefa manual levaria **por host** | 15 |

Como estimar:

- custo/minuto de uma pessoa = (salário + encargos mensais) ÷ (horas úteis do mês × 60)
- `aap_cost_per_minute` = (subscrição anual ÷ 12 + infra mensal) ÷ minutos de job executados no mês. O painel "Custo Automatizado" ajuda a conferir.
- O tempo manual é **por host** porque é o que escala com o inventário. Se a tarefa não varia por host, estime a média por execução dividida pela média de hosts por job.

Para fixar os valores como padrão: edite `query` e `current` de cada variável em `templating.list` no JSON, ou salve o dashboard na UI (provider com `allowUiUpdates: true`).

### 8. Validar

1. Datasource: "Database Connection OK".
2. Painel **Cobertura Taxonomia** > 0 %. Se 0 %, volte ao passo 6.
3. **Jobs Executados** coerente com a tela Jobs do controller no mesmo período, só templates rotulados.
4. Um número conferido fora do Grafana:

```bash
psql -h <host> -U grafana_ro -d awx -v dias=30 -v employee_cost_per_minute=2.50 \
  -v aap_cost_per_minute=0.10 -v manual_time_per_host_minutes=15 \
  -v custo_por_time="'linux=2.50,security=3.00'" -f sql/03-roi-core-query.sql
```

---

## Ajustes opcionais

| Ajuste | Como |
|---|---|
| Moeda | JSON usa `currencyBRL` (11×) e "R$" (19×): `sed -i 's/currencyBRL/currencyUSD/g; s/R\$/US$/g' grafana/dashboards/aap-roi-executive*.json` |
| Período padrão | `time.from` = `now-30d`; trimestral: `now-90d` |
| Refresh | `5m`. Bancos grandes: `15m` |
| Só jobs com sucesso | `AND uj.status = 'successful'` no `WHERE` de `job_meta` (26 queries, texto idêntico) |
| Sem ad-hoc commands | remover `'adhoccommand'` de `ct.model IN (...)` |
| Um único time | deixar `custo_por_time` vazio: tudo usa `employee_cost_per_minute` |
| Organizations com `(`, `+`, `.` no nome | o filtro usa regex; escape ou troque `~` por `=` onde aparece `organization:regex` |
| Compartilhar externamente | Share → Public dashboard (Grafana ≥ 10). Variáveis ficam fixas no valor salvo |

Fórmula completa e decisões embutidas em [docs/FORMULA.md](docs/FORMULA.md).

## Segurança e operação

- A datasource provisionada lê a senha de variável de ambiente; não versione `compose/.env` (já está no `.gitignore`).
- Role `grafana_ro`: menor privilégio, read-only, timeout 60s.
- As queries varrem `main_unifiedjob` pelo período. Em bancos com milhões de jobs, confirme índice em `created` e aumente o refresh.
- Upgrade do AAP não quebra o dashboard enquanto as 7 tabelas mantiverem os nomes.

## Problemas comuns

| Sintoma | Causa provável |
|---|---|
| `password authentication failed` | senha/role ou método em `pg_hba` |
| `connection refused` / timeout | `listen_addresses`, firewall 5432, host errado (`host.containers.internal` só no mesmo host) |
| `datasource aap-controller-db not found` | uid diferente; use o `.import.json` ou corrija o uid |
| Tudo em 0 / "No data" | nenhum template com as 4 labels (`sql/02-validate-taxonomy.sql`) |
| Retorno (×) na casa dos milhares | `aap_cost_per_minute` baixo demais ou jobs com `elapsed` ≈ 0 |
| Filtro de time vazio | labels fora do formato `time:<valor>` |

## Compatibilidade

| Componente | Versões |
|---|---|
| AAP | 2.4, 2.5, 2.7 (esquema das tabelas inalterado) |
| PostgreSQL | 13, 15 |
| Grafana | 10.4 → 13.x (painéis core: stat, gauge, timeseries, piechart, barchart, bargauge, table) |
