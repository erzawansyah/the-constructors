---
inclusion: fileMatch
fileMatchPattern: "**/*{schema,migration,supabase,database,rls}*"
---

# Database Schema — Supabase (PostgreSQL)

This steering file documents the database schema for The Constructors, deployed on **self-hosted Supabase** (Docker container).

## Core tables

### `scales`

Stores both app-built scales and published scales found during literature research.

```sql
CREATE TABLE scales (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  
  -- Metadata
  name TEXT NOT NULL,
  construct_name TEXT NOT NULL,
  source_type TEXT NOT NULL CHECK (source_type IN ('app_built', 'published')),
  
  -- For app-built scales
  creator_id UUID REFERENCES auth.users(id),
  creator_role TEXT CHECK (creator_role IN ('scientist', 'business', NULL)),
  data_policy TEXT CHECK (data_policy IN ('research', 'private', NULL)),
  
  -- For published scales
  citation TEXT,
  doi TEXT,
  license_status TEXT CHECK (license_status IN ('open', 'closed', 'unknown', NULL)),
  
  -- Scale content
  items JSONB NOT NULL, -- Array of {id, text, dimension, indicator, metadata}
  dimensions JSONB NOT NULL, -- Array of {name, definition, indicators}
  construct_framework JSONB, -- Full framework from literature research
  
  -- Validity ladder
  validity_tier INTEGER NOT NULL DEFAULT 0 CHECK (validity_tier BETWEEN 0 AND 5),
  -- 0=draft, 1=LLM screened, 2=structural screened, 3=smoke tested, 4=human data, 5=norms
  
  -- Pipeline artifacts
  dropped_items JSONB, -- Array of {item, stage, reason, metrics}
  traceability_log JSONB, -- Full pipeline log (models, prompts, decisions)
  
  -- Counts
  response_count INTEGER NOT NULL DEFAULT 0,
  
  -- Status
  status TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'published', 'archived')),
  
  -- Full-text search
  search_vector TSVECTOR GENERATED ALWAYS AS (
    to_tsvector('english', coalesce(name, '') || ' ' || coalesce(construct_name, ''))
  ) STORED
);

CREATE INDEX scales_creator_idx ON scales(creator_id);
CREATE INDEX scales_source_type_idx ON scales(source_type);
CREATE INDEX scales_status_idx ON scales(status);
CREATE INDEX scales_search_idx ON scales USING GIN(search_vector);
```

### `responses`

Stores individual respondent answers.

```sql
CREATE TABLE responses (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  
  scale_id UUID NOT NULL REFERENCES scales(id) ON DELETE CASCADE,
  respondent_id UUID REFERENCES auth.users(id), -- NULL for anonymous
  
  -- Response data
  answers JSONB NOT NULL, -- {item_id: likert_value}
  dimension_scores JSONB NOT NULL, -- {dimension_name: score}
  
  -- Metadata
  completion_time_seconds INTEGER,
  user_agent TEXT,
  
  -- RLS policy enforcement
  data_policy TEXT NOT NULL CHECK (data_policy IN ('research', 'private'))
);

CREATE INDEX responses_scale_idx ON responses(scale_id);
CREATE INDEX responses_respondent_idx ON responses(respondent_id);
CREATE INDEX responses_created_idx ON responses(created_at);
```

### `share_links`

Share links for published scales.

```sql
CREATE TABLE share_links (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  
  scale_id UUID NOT NULL REFERENCES scales(id) ON DELETE CASCADE,
  token TEXT NOT NULL UNIQUE,
  
  expires_at TIMESTAMPTZ,
  max_uses INTEGER,
  use_count INTEGER NOT NULL DEFAULT 0,
  
  active BOOLEAN NOT NULL DEFAULT true
);

CREATE INDEX share_links_token_idx ON share_links(token);
CREATE INDEX share_links_scale_idx ON share_links(scale_id);
```

### `users` (extends `auth.users`)

Additional user metadata.

```sql
CREATE TABLE user_profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  
  role TEXT CHECK (role IN ('scientist', 'business', 'respondent')),
  organization TEXT,
  
  -- Preferences
  preferred_language TEXT DEFAULT 'en',
  email_notifications BOOLEAN DEFAULT true
);
```

---

## Row-Level Security (RLS)

RLS enforces data policy rules (FR-RESP-2).

### `scales` RLS

```sql
ALTER TABLE scales ENABLE ROW LEVEL SECURITY;

-- Public read for published scales
CREATE POLICY "Published scales are viewable by everyone"
  ON scales FOR SELECT
  USING (status = 'published');

-- Creators can view their own drafts
CREATE POLICY "Creators can view own scales"
  ON scales FOR SELECT
  USING (auth.uid() = creator_id);

-- Creators can update their own drafts
CREATE POLICY "Creators can update own drafts"
  ON scales FOR UPDATE
  USING (auth.uid() = creator_id AND status = 'draft');

-- Creators can insert
CREATE POLICY "Authenticated users can create scales"
  ON scales FOR INSERT
  WITH CHECK (auth.uid() = creator_id);
```

### `responses` RLS

**Critical:** Business scale responses are private to that business. Research scale responses are pooled.

```sql
ALTER TABLE responses ENABLE ROW LEVEL SECURITY;

-- Research scales: responses visible to scale creator and aggregated analytics
CREATE POLICY "Research responses viewable by scale creator"
  ON responses FOR SELECT
  USING (
    data_policy = 'research' AND
    EXISTS (
      SELECT 1 FROM scales
      WHERE scales.id = responses.scale_id
      AND scales.creator_id = auth.uid()
    )
  );

-- Private (business) scales: responses visible only to scale creator
CREATE POLICY "Private responses viewable by creator only"
  ON responses FOR SELECT
  USING (
    data_policy = 'private' AND
    EXISTS (
      SELECT 1 FROM scales
      WHERE scales.id = responses.scale_id
      AND scales.creator_id = auth.uid()
    )
  );

-- Respondents can view their own responses
CREATE POLICY "Respondents can view own responses"
  ON responses FOR SELECT
  USING (auth.uid() = respondent_id);

-- Anyone can insert responses (anonymous or authenticated)
CREATE POLICY "Anyone can submit responses"
  ON responses FOR INSERT
  WITH CHECK (true);
```

### `share_links` RLS

```sql
ALTER TABLE share_links ENABLE ROW LEVEL SECURITY;

-- Public read for active links
CREATE POLICY "Active share links are viewable by everyone"
  ON share_links FOR SELECT
  USING (active = true);

-- Creators can manage their scale's links
CREATE POLICY "Creators can manage own scale links"
  ON share_links FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM scales
      WHERE scales.id = share_links.scale_id
      AND scales.creator_id = auth.uid()
    )
  );
```

---

## Functions and triggers

### Update `response_count` on `scales`

```sql
CREATE OR REPLACE FUNCTION update_scale_response_count()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE scales
  SET response_count = (
    SELECT COUNT(*) FROM responses WHERE scale_id = NEW.scale_id
  )
  WHERE id = NEW.scale_id;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER response_count_trigger
AFTER INSERT ON responses
FOR EACH ROW
EXECUTE FUNCTION update_scale_response_count();
```

### Update `updated_at` timestamps

```sql
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER scales_updated_at
BEFORE UPDATE ON scales
FOR EACH ROW
EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER user_profiles_updated_at
BEFORE UPDATE ON user_profiles
FOR EACH ROW
EXECUTE FUNCTION update_updated_at();
```

---

## Seed data (FR-CAT-2)

The catalog is seeded with public-domain scales at deployment. Research task: find 5–10 established scales with clear open licenses (e.g., IPIP Big Five, PANAS public domain).

Seed script: `supabase/seed.sql`

```sql
-- Example seed (actual scales to be researched)
INSERT INTO scales (
  name,
  construct_name,
  source_type,
  citation,
  doi,
  license_status,
  items,
  dimensions,
  validity_tier,
  status
) VALUES (
  'IPIP Big Five (50-item)',
  'Big Five Personality',
  'published',
  'Goldberg, L. R. (1992). The development of markers for the Big-Five factor structure.',
  '10.1037/0033-2909.117.1.21',
  'open',
  '[...]', -- Full item JSON
  '[...]', -- Dimensions JSON
  5, -- Has norms
  'published'
);
```

---

## Migrations

Migrations live in `supabase/migrations/` and are applied via Supabase CLI.

**Naming convention:** `YYYYMMDDHHMMSS_description.sql`

Example: `20261126120000_initial_schema.sql`

**Rule:** Never edit migrations that have been applied to production. Create new migrations for schema changes.

---

## Analytics views (future)

For norm calculation and progress display (FR-RESP-3):

```sql
CREATE VIEW scale_response_stats AS
SELECT
  s.id AS scale_id,
  s.name,
  s.response_count,
  CASE
    WHEN s.response_count < 100 THEN 'tier1_self_reflection'
    WHEN s.response_count < 1000 THEN 'tier2_provisional'
    ELSE 'tier3_norms'
  END AS feedback_tier,
  jsonb_object_agg(
    dim.name,
    jsonb_build_object(
      'mean', AVG((r.dimension_scores->>dim.name)::FLOAT),
      'sd', STDDEV((r.dimension_scores->>dim.name)::FLOAT),
      'percentiles', percentile_cont(ARRAY[0.25, 0.5, 0.75]) WITHIN GROUP (ORDER BY (r.dimension_scores->>dim.name)::FLOAT)
    )
  ) AS dimension_stats
FROM scales s
CROSS JOIN LATERAL jsonb_array_elements(s.dimensions) AS dim(name)
LEFT JOIN responses r ON r.scale_id = s.id
WHERE s.status = 'published' AND s.data_policy = 'research'
GROUP BY s.id, s.name, s.response_count;
```

---

## Connection from Next.js

Use Supabase JS client:

```typescript
import { createClient } from '@supabase/supabase-js';

const supabase = createClient(
  process.env.SUPABASE_URL!,
  process.env.SUPABASE_ANON_KEY!
);

// RLS enforces policy automatically
const { data: scales } = await supabase
  .from('scales')
  .select('*')
  .eq('status', 'published');
```

Environment variables:
- `SUPABASE_URL`: `http://localhost:54321` (default for self-hosted)
- `SUPABASE_ANON_KEY`: Generated during Supabase setup
- `SUPABASE_SERVICE_ROLE_KEY`: For admin operations (never expose to client)

---

## Testing

**Migration tests:** Run migrations on a test database, verify schema structure.

**RLS tests:** Test policy enforcement with different user roles and data policies.

**Seed tests:** Verify seed scales load correctly and are queryable.

Test files: `supabase/tests/`
