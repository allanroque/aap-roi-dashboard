# Taxonomia de labels `eixo:valor`

O dashboard calcula ROI **somente** para jobs cujo Job Template ou Workflow carrega **4 labels, uma por eixo**.
A label leva o eixo no nome (`dominio:patching`, nunca `patching` solto) para que o dado bruto seja
autoexplicativo e consumível por SQL/API sem tabela auxiliar.

## Os quatro eixos

| Eixo | Formato | Papel no dashboard | Sugestão de vocabulário |
|---|---|---|---|
| Time | `time:<valor>` | chave do custo/minuto (`custo_por_time`); pie/bar "por Time" | nome da organization dona, em minúsculo: `linux`, `security`, `cloud`, `network`, `platform`, `database` |
| Domínio | `dominio:<valor>` | "por Domínio", matriz Time × Domínio | `provisioning` `patching` `compliance` `deploy` `backup` `disaster-recovery` `operations` `observability` `self-healing` `security` `database` `network` `storage` `identity-management` `access-management` `integration` `governance` `assessment` |
| Criticidade | `criticidade:<valor>` | "por Criticidade" | `alta` · `media` · `baixa` |
| Ambiente | `ambiente:<valor>` | "por Ambiente" | `prd` · `hml` · `dev` |

## Regras de formato

- Minúsculo, sem acento (`media`, não `média`), sem espaço, **um único `:`**.
- Valor composto usa hífen (`self-healing`), nunca `_`.
- Exatamente uma label por eixo em cada template. Duas labels do mesmo eixo fazem o dashboard escolher uma delas arbitrariamente (`MAX`).
- Os valores são livres: os filtros do dashboard se preenchem a partir do banco. Mas fixe um **vocabulário fechado** e registre-o aqui antes de criar valor novo; label criada "no impulso" vira dívida de relatório.
- Labels são escopadas por organization. `criticidade:alta` precisa existir em cada org que tenha templates.

## Como aplicar

1. **Como código (recomendado):** `ansible/apply-labels.yml` com `ansible/vars/labels.yml` (copie de `labels-example.yml`). Rode com `--check --diff` antes. O parâmetro `labels` do módulo é declarativo: a lista enviada vira a lista final do template.
2. **UI:** Automation Execution → Templates → editar → Labels.
3. **API:** `POST /api/controller/v2/job_templates/<id>/labels/ {"name": "dominio:patching", "organization": <org_id>}`.

## Efeito no histórico

O dashboard lê as labels **atuais do template** (`main_unifiedjobtemplate_labels`), não as copiadas para o job no launch.
Consequências:

- Rotular um template hoje faz **todo o histórico dele** passar a contar, inclusive jobs antigos.
- Renomear um valor (`criticidade:high` → `criticidade:alta`) move o passado junto. Não há "degrau" no gráfico, mas também não há rastro da mudança.
- Templates excluídos deixam de contar (o join exige template existente).

## Verificação

```bash
psql -h <host> -U grafana_ro -d awx -f sql/02-validate-taxonomy.sql
```

Seção 2 mostra a cobertura (%); seção 3 lista cada template incompleto e qual eixo falta; seção 5 lista labels fora do padrão, que o dashboard ignora.
