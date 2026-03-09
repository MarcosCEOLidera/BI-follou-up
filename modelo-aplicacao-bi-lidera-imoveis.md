# Modelo de Aplicação + BI — Lidera Imóveis

## 1) Arquitetura de dados sugerida

## Visão geral (camadas)
- **Camada transacional (App):** cadastro de corretores, blocos, leads e atividades.
- **Camada analítica (BI):** visão diária consolidada por corretor e por período.
- **Camada de visualização:** dashboard com KPIs, gráficos e tabela detalhada.

## Modelo relacional (tabelas principais)

### `corretores`
- `corretor_id` (PK)
- `nome_corretor` (UNIQUE)
- `email_login` (UNIQUE)
- `senha_hash`
- `perfil` (`admin` ou `corretor`)
- `ativo` (boolean)
- `created_at`, `updated_at`

### `blocos`
- `bloco_id` (PK)
- `corretor_id` (FK -> `corretores.corretor_id`)
- `ordem_bloco` (inteiro: 1,2,3... por corretor)
- `status_bloco` (`pendente`, `ativo`, `concluido`)
- `dt_ativacao`
- `dt_conclusao`
- `qtd_leads_planejada` (default 30)
- `created_at`, `updated_at`

**Regra de integridade importante:** `UNIQUE (corretor_id, ordem_bloco)`.

### `leads`
- `lead_id` (PK)
- `bloco_id` (FK -> `blocos.bloco_id`)
- `nome_lead`
- `telefone`
- `email`
- `status_contato_atual` (`nao_iniciado`, `contato_realizado`)
- `created_at`, `updated_at`

### `atividades_contato`
- `contato_id` (PK)
- `lead_id` (FK -> `leads.lead_id`)
- `corretor_id` (FK -> `corretores.corretor_id`)
- `data_contato` (timestamp)
- `contato_realizado` (boolean)
- `atendeu` (boolean)
- `respondido` (boolean)
- `cadastrado_no_crm` (boolean)
- `observacoes` (texto)
- `created_at`

> Recomendação: manter histórico completo em `atividades_contato` e usar a atividade mais recente para o status operacional do lead.

### `vw_lead_status_atual` (view)
View para retornar **última atividade de cada lead** + status consolidado, usada na tela do corretor.

### `fato_produtividade_diaria` (tabela materializada/ETL)
Granularidade: **1 linha por corretor por dia**.
- `data_ref`
- `corretor_id`
- `contatos_realizados`
- `ligacoes_atendidas`
- `contatos_respondidos`
- `cadastros_crm`
- `blocos_concluidos`
- `streak_blocos` (dias consecutivos com >=1 bloco concluído)

## Relacionamentos
- 1 corretor -> N blocos
- 1 bloco -> 30 leads
- 1 lead -> N atividades

---

## 2) Lógica de negócio

## 2.1 Atribuição e ativação inicial de blocos
1. Cadastrar todos os blocos com `status_bloco = 'pendente'`.
2. Para cada corretor, ativar apenas o bloco de menor `ordem_bloco`:
   - `status_bloco = 'ativo'`
   - preencher `dt_ativacao`.
3. Garantir regra: **máximo 1 bloco ativo por corretor** (constraint + validação de serviço).

## 2.2 Regras da tela “Meus 30 leads atuais”
- O corretor autenticado só consulta leads do seu bloco `ativo`.
- Cada update de lead grava novo registro em `atividades_contato`.
- Lead é considerado “trabalhado” quando última atividade possui `contato_realizado = true`.
- Barra de progresso:
  - `trabalhados = count(leads do bloco ativo com contato_realizado=true)`
  - Exibir `trabalhados/30`.

## 2.3 Conclusão de bloco e liberação automática do próximo
Fluxo transacional recomendado (trigger ou serviço backend):

1. Após salvar atividade, recalcular `% concluído` do bloco ativo.
2. Se `30/30` leads trabalhados:
   - atualizar bloco atual para `concluido` com `dt_conclusao=now()`.
3. Buscar próximo bloco do mesmo corretor:
   - `ordem_bloco = ordem_atual + 1` e `status_bloco='pendente'`.
4. Se existir:
   - marcar próximo bloco como `ativo`, setar `dt_ativacao=now()`.
5. Se não existir:
   - registrar estado “sem novos leads disponíveis”.

## 2.4 Controle de permissão
- Corretor: só visualiza e altera seus próprios leads do bloco ativo.
- Admin: visão global, reatribuição de blocos, filtros e auditoria.

## 2.5 Reatribuição de bloco (admin)
- Permitido para blocos `pendente`.
- Para bloco `ativo`, exigir confirmação e registrar auditoria.
- Ao reatribuir:
  - atualizar `corretor_id` no bloco.
  - recalcular coerência de `ordem_bloco` do novo corretor (se necessário).

---

## 3) Desenho do painel de BI

## Página 1 — Visão Executiva (diária)
**Filtros:** Data, corretor, status de bloco.

**KPIs:**
- Contatos realizados no dia
- Ligações atendidas
- Contatos respondidos
- Leads cadastrados no CRM
- Blocos concluídos no dia
- Taxa de conclusão dos blocos ativos (`trabalhados / 30` agregado)

**Gráficos:**
- Barras: contatos realizados por corretor (dia)
- Linha dupla: contatos realizados vs respondidos (evolução diária)
- Pizza/Rosca: atendido vs não atendido

## Página 2 — Produtividade por corretor
- Ranking diário/semanal por volume de contatos realizados
- Blocos concluídos por corretor (período)
- Streak de conclusão (dias consecutivos)
- Tempo médio para concluir 1 bloco (SLA operacional)

## Página 3 — Operação de blocos
- Matriz por corretor:
  - bloco atual ativo
  - progresso (x/30)
  - data de ativação
  - próximos blocos pendentes
- Tabela detalhada por corretor e por dia com todas as métricas

---

## 4) Implementação prática (rápida e escalável)

## Opção A — MVP em planilhas + AppSheet + Looker Studio
- **Google Sheets** como base de dados inicial (`corretores`, `blocos`, `leads`, `atividades_contato`).
- **AppSheet** para app operacional (login, formulário de atualização e regras).
- **Looker Studio** para dashboard com refresh automático.

**Prós:** implantação rápida, baixo custo inicial.  
**Contras:** limitações de escala e governança.

## Opção B — Produção em banco SQL + API + BI
- **PostgreSQL** para dados transacionais.
- **Backend** (Node.js/NestJS, Python/FastAPI ou similar) com:
  - autenticação (JWT)
  - controle de acesso por perfil
  - rotina de liberação automática de blocos
- **Power BI/Metabase/Looker** para dashboards.
- **ETL diário** (dbt/Airflow/Cron) para fato de produtividade.

**Prós:** robustez, auditoria, escala, governança.  
**Contras:** maior esforço de implantação.

---

## 5) KPIs e fórmulas recomendadas
- **Contatos realizados (dia):** `count(contato_id where contato_realizado=true and data=data_ref)`
- **Atendidas (dia):** `count(contato_id where atendeu=true and data=data_ref)`
- **Respondidos (dia):** `count(contato_id where respondido=true and data=data_ref)`
- **CRM (dia):** `count(contato_id where cadastrado_no_crm=true and data=data_ref)`
- **Blocos concluídos (dia):** `count(bloco_id where status='concluido' and dt_conclusao::date=data_ref)`
- **Streak:** sequência de dias em que `blocos_concluidos_dia >= 1` por corretor.

---

## 6) Fluxo operacional diário
1. Corretor faz login.
2. Visualiza os 30 leads do bloco ativo.
3. Registra contatos ao longo do dia.
4. Ao atingir 30/30 com contato realizado:
   - bloco atual conclui automaticamente.
   - próximo bloco é liberado automaticamente.
5. Admin acompanha tudo no BI, com comparativo por corretor e por dia.

---

## 7) Checklist de implantação
- [ ] Cadastrar 8 corretores e perfis de acesso.
- [ ] Importar blocos e leads com `ordem_bloco` por corretor.
- [ ] Ativar bloco inicial de cada corretor.
- [ ] Implementar validação “1 bloco ativo por corretor”.
- [ ] Implementar trigger/serviço de liberação automática.
- [ ] Publicar dashboard diário com KPIs e filtros.
- [ ] Definir rotina de qualidade de dados e auditoria.
