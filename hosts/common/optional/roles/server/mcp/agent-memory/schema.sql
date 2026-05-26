-- Idempotent schema for the shared agent memory store.
-- Applied on every boot by the agent-memory-db-setup oneshot service.

CREATE EXTENSION IF NOT EXISTS vector;

CREATE TABLE IF NOT EXISTS projects (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name        text UNIQUE NOT NULL,
  description text,
  settings    jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS memories (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  content     text NOT NULL,
  embedding   vector(768) NOT NULL,           -- nomic-embed-text dimension
  source      text,
  project_id  uuid REFERENCES projects(id) ON DELETE SET NULL,
  tags        text[] NOT NULL DEFAULT '{}',
  metadata    jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS memories_project_id_idx ON memories (project_id);
CREATE INDEX IF NOT EXISTS memories_tags_gin_idx   ON memories USING gin (tags);
CREATE INDEX IF NOT EXISTS memories_embedding_hnsw
  ON memories USING hnsw (embedding vector_cosine_ops);
