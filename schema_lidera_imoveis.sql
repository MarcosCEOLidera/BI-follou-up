-- Schema base para controle de blocos de 30 leads - Lidera Imóveis

create table if not exists corretores (
  corretor_id serial primary key,
  nome_corretor varchar(120) not null unique,
  email_login varchar(180) not null unique,
  senha_hash text not null,
  perfil varchar(20) not null check (perfil in ('admin','corretor')),
  ativo boolean not null default true,
  created_at timestamp not null default now(),
  updated_at timestamp not null default now()
);

create table if not exists blocos (
  bloco_id bigserial primary key,
  corretor_id int not null references corretores(corretor_id),
  ordem_bloco int not null,
  status_bloco varchar(20) not null check (status_bloco in ('pendente','ativo','concluido')),
  dt_ativacao timestamp,
  dt_conclusao timestamp,
  qtd_leads_planejada int not null default 30,
  created_at timestamp not null default now(),
  updated_at timestamp not null default now(),
  unique (corretor_id, ordem_bloco)
);

-- garante no máximo 1 bloco ativo por corretor
create unique index if not exists ux_blocos_ativo_por_corretor
  on blocos(corretor_id)
  where status_bloco = 'ativo';

create table if not exists leads (
  lead_id bigserial primary key,
  bloco_id bigint not null references blocos(bloco_id),
  nome_lead varchar(180) not null,
  telefone varchar(40),
  email varchar(180),
  status_contato_atual varchar(30) not null default 'nao_iniciado' check (status_contato_atual in ('nao_iniciado','contato_realizado')),
  created_at timestamp not null default now(),
  updated_at timestamp not null default now()
);

create table if not exists atividades_contato (
  contato_id bigserial primary key,
  lead_id bigint not null references leads(lead_id),
  corretor_id int not null references corretores(corretor_id),
  data_contato timestamp not null default now(),
  contato_realizado boolean not null default false,
  atendeu boolean,
  respondido boolean,
  cadastrado_no_crm boolean,
  observacoes text,
  created_at timestamp not null default now()
);

create or replace view vw_lead_status_atual as
select
  l.lead_id,
  l.bloco_id,
  b.corretor_id,
  l.nome_lead,
  l.telefone,
  l.email,
  coalesce(a.contato_realizado, false) as contato_realizado,
  a.atendeu,
  a.respondido,
  a.cadastrado_no_crm,
  a.data_contato as ultima_data_contato
from leads l
join blocos b on b.bloco_id = l.bloco_id
left join lateral (
  select ac.*
  from atividades_contato ac
  where ac.lead_id = l.lead_id
  order by ac.data_contato desc, ac.contato_id desc
  limit 1
) a on true;
