
-- cria DB e tabela mock
CREATE DATABASE appdb;

\connect appdb;

CREATE TABLE IF NOT EXISTS public.users (
  id   SERIAL PRIMARY KEY,
  name TEXT NOT NULL
);

INSERT INTO public.users (name) VALUES ('Neo'), ('Trinity')
ON CONFLICT DO NOTHING;
