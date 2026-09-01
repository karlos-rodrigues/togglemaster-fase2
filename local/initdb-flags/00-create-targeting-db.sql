-- Roda contra o POSTGRES_DB (flag_db) na primeira inicialização do volume.
-- O enunciado pede 2 instâncias PostgreSQL locais para 3 serviços, então esta
-- instância hospeda dois bancos lógicos: flag_db (criado pelo entrypoint via
-- POSTGRES_DB) e targeting_db, criado aqui.
--
-- Na AWS isso vira 3 instâncias RDS independentes, como o checklist da etapa 2 exige.
CREATE DATABASE targeting_db OWNER togglemaster;
