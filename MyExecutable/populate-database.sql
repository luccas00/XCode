-- Insert simples
INSERT INTO public.users (name) VALUES ('Neo');

-- Insert com retorno de ID (recomendado p/ app)
INSERT INTO public.users (name) VALUES ('Trinity') RETURNING id, name;

-- Insert parametrizado (psql / drivers)
-- $1 é o placeholder do Postgres
INSERT INTO public.users (name) VALUES ($1) RETURNING id, name;


CREATE TABLE IF NOT EXISTS public.users (
  id   SERIAL PRIMARY KEY,
  name TEXT NOT NULL
);
