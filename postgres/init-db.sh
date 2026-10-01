#!/bin/bash

set -e

psql -v ON_ERROR_STOP=1 --username $POSTGRES_USER --dbname postgres <<-EOSQL
    CREATE USER highlight WITH PASSWORD 'highlight';
    CREATE USER highlight_root WITH SUPERUSER PASSWORD 'highlight';
    CREATE DATABASE highlight;
    GRANT ALL PRIVILEGES ON DATABASE highlight TO highlight_root;
    \connect highlight;
    CREATE SCHEMA highlight;
    CREATE SCHEMA cvedb;

    -- Keycloak - dedicated database/schema, separate from the Highlight one
    \connect postgres;
    CREATE USER keycloak WITH PASSWORD 'keycloak';
    CREATE DATABASE keycloak OWNER keycloak;
    GRANT ALL PRIVILEGES ON DATABASE keycloak TO keycloak;
    \connect keycloak;
    CREATE SCHEMA IF NOT EXISTS keycloak AUTHORIZATION keycloak;
EOSQL
