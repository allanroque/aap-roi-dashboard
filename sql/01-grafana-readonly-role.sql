-- =====================================================================
-- Role de leitura para o Grafana no banco do Automation Controller (awx)
-- Executar como superusuario (postgres) no banco "awx":
--   psql -U postgres -d awx -v grafana_ro_password="'SenhaForte'" -f 01-grafana-readonly-role.sql
-- Containerizado:  podman exec -i postgresql psql -U postgres -d awx -v grafana_ro_password="'SenhaForte'" < 01-grafana-readonly-role.sql
-- RPM:             sudo -u postgres psql -d awx -v grafana_ro_password="'SenhaForte'" -f 01-grafana-readonly-role.sql
-- =====================================================================
\set ON_ERROR_STOP on

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'grafana_ro') THEN
    EXECUTE format('CREATE ROLE grafana_ro LOGIN PASSWORD %L', :'grafana_ro_password');
  ELSE
    EXECUTE format('ALTER ROLE grafana_ro WITH LOGIN PASSWORD %L', :'grafana_ro_password');
  END IF;
END $$;

ALTER ROLE grafana_ro SET statement_timeout = '60s';   -- protege o banco do controller
ALTER ROLE grafana_ro SET default_transaction_read_only = on;

GRANT CONNECT ON DATABASE awx TO grafana_ro;
GRANT USAGE ON SCHEMA public TO grafana_ro;

-- Somente as tabelas que o dashboard le (principio do menor privilegio)
GRANT SELECT ON
  public.main_unifiedjob,
  public.main_unifiedjobtemplate,
  public.main_unifiedjobtemplate_labels,
  public.main_label,
  public.main_organization,
  public.main_jobhostsummary,
  public.django_content_type
TO grafana_ro;

-- Verificacao
SELECT rolname, rolcanlogin, rolsuper FROM pg_roles WHERE rolname = 'grafana_ro';
SELECT table_name, privilege_type FROM information_schema.role_table_grants
 WHERE grantee = 'grafana_ro' ORDER BY 1;
