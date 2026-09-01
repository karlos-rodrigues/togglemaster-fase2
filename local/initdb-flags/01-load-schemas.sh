#!/bin/bash
# Aplica os schemas em cada banco lógico desta instância.
#
# Os arquivos .sql vêm montados de dentro dos próprios repositórios da FIAP
# (services/*/db/init.sql), em vez de copiados para cá — assim não existem duas
# cópias do schema que possam divergir.
set -euo pipefail

echo "==> aplicando schema do flag-service em flag_db"
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname flag_db \
     -f /schemas/flag-init.sql

echo "==> aplicando schema do targeting-service em targeting_db"
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname targeting_db \
     -f /schemas/targeting-init.sql

echo "==> schemas aplicados"
