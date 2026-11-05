# Guia rápido de instalação

Este repositório contém o export do dashboard e tudo que é necessário para rodá-lo contra o seu Ansible Automation Platform 2.5/2.7:

| Arquivo | Para quê |
|---|---|
| `grafana/dashboards/aap-roi-executive.import.json` | **Export do dashboard** para importar pela interface do Grafana |
| `grafana/dashboards/aap-roi-executive.json` | Mesmo dashboard, para quem provisiona Grafana por arquivo |
| `grafana/provisioning/` | Datasource e provider prontos para provisioning por arquivo |
| `compose/` | Grafana pronto em container, caso vocês ainda não tenham Grafana |
| `sql/01-grafana-readonly-role.sql` | Cria o usuário de leitura `grafana_ro` no banco do controller |
| `sql/02-validate-taxonomy.sql` | Mostra quais templates ainda faltam rotular |
| `sql/03-roi-core-query.sql` | A mesma fórmula do dashboard em SQL, para auditoria |
| `ansible/apply-labels.yml` | Playbook que aplica as labels nos templates (opcional) |
| `README.md` e `docs/CHECKLIST.md` | Guia completo e checklist |

### Como o dashboard funciona

Ele não precisa de agente, exporter, Prometheus nem Automation Analytics. O Grafana lê **diretamente o banco PostgreSQL do Automation Controller** (banco `awx`) e calcula economia, retorno (×), horas economizadas e taxa de sucesso a partir do histórico de jobs. Por isso, os pré-requisitos são apenas:

1. Acesso de leitura ao banco do controller a partir do Grafana.
2. Um Grafana 10.4 ou superior (testamos na 13.0.2). Nenhum plugin é necessário.
3. Os Job Templates e Workflows rotulados com 4 labels (explico no passo 5).

### Passo 1 — Liberar acesso ao banco do controller

Localize o PostgreSQL do controller no inventário da instalação (`controller_pg_host`, banco `controller_pg_database`, normalmente `awx`).

- **Instalação containerizada (podman):** o PostgreSQL já aceita conexões externas por senha. Basta liberar a porta no host do AAP:
  `firewall-cmd --add-port=5432/tcp --permanent && firewall-cmd --reload`
- **Instalação RPM:** em `postgresql.conf` garanta `listen_addresses = '*'`, em `pg_hba.conf` adicione `host awx grafana_ro <IP-do-Grafana>/32 scram-sha-256`, recarregue o serviço e libere a porta 5432.
- **Banco externo/gerenciado:** peça ao DBA para liberar o IP do Grafana e executar o script do passo 2.
- **OpenShift (operator):** rode o Grafana dentro do cluster apontando para o Service do PostgreSQL, ou exponha o banco via Service TCP. Detalhes no README.

### Passo 2 — Criar o usuário de leitura (não use o usuário `awx`)

Execute como `postgres` no banco `awx`:

```
# containerizado
podman exec -i postgresql psql -U postgres -d awx -v grafana_ro_password="'SenhaForte'" < sql/01-grafana-readonly-role.sql
# RPM
sudo -u postgres psql -d awx -v grafana_ro_password="'SenhaForte'" -f sql/01-grafana-readonly-role.sql
```

O script cria a role `grafana_ro` apenas com SELECT nas 7 tabelas que o dashboard usa, em modo somente leitura e com timeout de 60 segundos, para não impactar o controller. Teste a partir do servidor do Grafana:

```
psql -h <host-do-banco> -U grafana_ro -d awx -c "select count(*) from main_unifiedjob"
```

### Passo 3 — Criar o Data Source no Grafana

Acesse o Grafana (ex.: `http://<grafana-url>:3000`) e vá em **Connections → Data sources → Add data source → PostgreSQL**:

| Campo | Valor |
|---|---|
| Name | `AAP Controller DB` |
| Host | `<host-do-banco>:5432` |
| Database | `awx` |
| User / Password | `grafana_ro` / a senha definida no passo 2 |
| TLS/SSL Mode | `require` (o PostgreSQL do AAP já sobe com certificado) ou `disable` se não houver TLS |
| Version | `15` |

Clique em **Save & test** e confirme a mensagem "Database Connection OK".

Não é necessário copiar o UID do datasource nem editar o JSON: o arquivo de import pergunta qual datasource usar.

### Passo 4 — Importar o dashboard

1. **Dashboards → New → Import**.
2. **Upload dashboard JSON file** e selecione `grafana/dashboards/aap-roi-executive.import.json` (ou cole o conteúdo).
3. Na tela seguinte, no campo **"Banco do Automation Controller (PostgreSQL)"**, escolha o datasource criado no passo 3.
4. **Import**. O dashboard aparece como **AAP — ROI Executivo**.

Se vocês provisionam o Grafana por arquivo (podman/docker/Helm), use os arquivos de `grafana/provisioning/` e `grafana/dashboards/aap-roi-executive.json`; nesse caso o datasource precisa ter o uid `aap-controller-db`, como já está no YAML incluído.

### Passo 5 — Rotular os templates (sem isso o dashboard fica em zero)

O ROI é calculado apenas para jobs cujo template tem **4 labels, uma por eixo**:

| Label | Significado | Exemplos |
|---|---|---|
| `time:<valor>` | time/área dona da automação | `time:linux`, `time:security` |
| `dominio:<valor>` | o que a automação faz | `dominio:patching`, `dominio:provisioning` |
| `criticidade:<valor>` | risco/valor protegido | `criticidade:alta`, `criticidade:media`, `criticidade:baixa` |
| `ambiente:<valor>` | onde atua | `ambiente:prd`, `ambiente:hml`, `ambiente:dev` |

Regras: minúsculo, sem acento, sem espaço, um único `:`. Os valores são livres e os filtros do dashboard se preenchem sozinhos a partir do que existir no banco; definam um vocabulário fechado e mantenham. As labels são por organization, então crie-as em cada org que tenha templates.

Como aplicar: pela interface (Templates → editar → Labels), pela API, ou com o playbook `ansible/apply-labels.yml` (exemplo de variáveis em `ansible/vars/labels-example.yml`; rode primeiro com `--check --diff`). Para saber o que falta rotular, execute `sql/02-validate-taxonomy.sql` com o usuário `grafana_ro`.

Rotular um template faz o histórico dele passar a contar imediatamente, inclusive jobs antigos.

### Passo 6 — Calibrar os custos (variáveis no topo do dashboard)

| Variável | Significado | Default |
|---|---|---|
| `employee_cost_per_minute` | custo por minuto de trabalho manual (default para times não mapeados) | 2.50 |
| `custo_por_time` | custo por minuto por time, no formato `linux=2.50,security=3.00` (usa os valores da label `time:`) | exemplo incluído |
| `aap_cost_per_minute` | custo por minuto de execução no AAP: (subscrição anual ÷ 12 + infra mensal) ÷ minutos de job no mês | 0.10 |
| `manual_time_per_host_minutes` | minutos que a tarefa levaria manualmente, por host | 15 |

Custo por minuto de uma pessoa = (salário + encargos mensais) ÷ (horas úteis no mês × 60). Para fixar os valores de vocês como padrão, salve o dashboard após ajustar as variáveis (ou edite `templating.list` no JSON).

Moeda: o dashboard vem em R$ (`currencyBRL`). Para trocar, um `sed` no JSON resolve; o comando está no README.

### Passo 7 — Validar

- Painel **"Cobertura Taxonomia"** maior que 0 %. Se estiver em 0 %, voltem ao passo 5.
- **"Jobs Executados"** coerente com a tela Jobs do controller no mesmo período, considerando só templates rotulados.
- Opcional: conferir um número fora do Grafana com `sql/03-roi-core-query.sql`.

Qualquer dúvida em um dos passos, abra uma issue neste repositório.
