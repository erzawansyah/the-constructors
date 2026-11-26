# Spec 02 — Setup Supabase Schema and Seed Data

**Status:** Draft  
**Priority:** P0 (foundation for FR-CAT, FR-RESP)  
**Requirements:** FR-CAT, FR-RESP, NFR-6  
**Dependencies:** None

---

## Goal

Set up self-hosted Supabase container with:
1. Database schema (scales, responses, share_links, user_profiles)
2. Row-Level Security (RLS) policies enforcing data privacy rules
3. Seed data: 5–10 public-domain scales for catalog launch
4. Supabase auth configuration
5. Connection from Next.js verified

---

## Success criteria

- [ ] Supabase container running (self-hosted, not cloud)
- [ ] All tables created with correct schema
- [ ] RLS policies enforced (research vs private data policies)
- [ ] Triggers working (response_count, updated_at)
- [ ] Seed scales loaded and queryable
- [ ] Supabase JS client can connect from Next.js
- [ ] Environment variables documented
- [ ] Migration files committed

---

## Non-goals (for this spec)

- Production deployment configuration
- Performance tuning or indexing optimization
- Full analytics views (future spec)
- Advanced auth (SSO, MFA) — basic email/password sufficient

---

## Technical approach

### Directory structure

```
supabase/
├── config.toml                # Supabase CLI config
├── migrations/
│   └── 20261126120000_initial_schema.sql
├── seed.sql                   # Seed public-domain scales
├── tests/
│   ├── test_schema.sql        # Schema integrity tests
│   └── test_rls.sql           # RLS policy tests
└── README.md                  # Setup instructions
```

### Supabase setup (self-hosted)

**Option 1: Supabase CLI (recommended for development)**

```bash
# Install Supabase CLI
npm install -g supabase

# Initialize
cd supabase
supabase init

# Start containers (Postgres, Auth, Storage, etc.)
supabase start

# Output includes:
# - API URL: http://localhost:54321
# - Anon key: eyJ...
# - Service role key: eyJ...
```

**Option 2: Docker Compose (for production-like setup)**

```yaml
# docker-compose.yml (at repo root)
version: '3.8'
services:
  postgres:
    image: supabase/postgres:15.1.0.117
    ports:
      - "5432:5432"
    environment:
      POSTGRES_PASSWORD: your-super-secret-password
    volumes:
      - postgres-data:/var/lib/postgresql/data

  supabase-auth:
    image: supabase/gotrue:v2.99.0
    depends_on:
      - postgres
    environment:
      GOTRUE_DB_DATABASE_URL: postgres://postgres:your-super-secret-password@postgres:5432/postgres
      GOTRUE_SITE_URL: http://localhost:3000
      GOTRUE_JWT_SECRET: your-jwt-secret

  # ... (other Supabase services)

volumes:
  postgres-data:
```

**For this spec, use Supabase CLI** (simpler for hackathon development).

### Schema migration

**File:** `supabase/migrations/20261126120000_initial_schema.sql`

See `04-database-schema.md` steering file for full schema. Key tables:

#### `scales` table

```sql
CREATE TABLE scales (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  
  name TEXT NOT NULL,
  construct_name TEXT NOT NULL,
  source_type TEXT NOT NULL CHECK (source_type IN ('app_built', 'published')),
  
  creator_id UUID REFERENCES auth.users(id),
  creator_role TEXT CHECK (creator_role IN ('scientist', 'business', NULL)),
  data_policy TEXT CHECK (data_policy IN ('research', 'private', NULL)),
  
  citation TEXT,
  doi TEXT,
  license_status TEXT CHECK (license_status IN ('open', 'closed', 'unknown', NULL)),
  
  items JSONB NOT NULL,
  dimensions JSONB NOT NULL,
  construct_framework JSONB,
  
  validity_tier INTEGER NOT NULL DEFAULT 0 CHECK (validity_tier BETWEEN 0 AND 5),
  
  dropped_items JSONB,
  traceability_log JSONB,
  
  response_count INTEGER NOT NULL DEFAULT 0,
  
  status TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'published', 'archived')),
  
  search_vector TSVECTOR GENERATED ALWAYS AS (
    to_tsvector('english', coalesce(name, '') || ' ' || coalesce(construct_name, ''))
  ) STORED
);

CREATE INDEX scales_creator_idx ON scales(creator_id);
CREATE INDEX scales_source_type_idx ON scales(source_type);
CREATE INDEX scales_status_idx ON scales(status);
CREATE INDEX scales_search_idx ON scales USING GIN(search_vector);
```

#### `responses` table

```sql
CREATE TABLE responses (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  
  scale_id UUID NOT NULL REFERENCES scales(id) ON DELETE CASCADE,
  respondent_id UUID REFERENCES auth.users(id),
  
  answers JSONB NOT NULL,
  dimension_scores JSONB NOT NULL,
  
  completion_time_seconds INTEGER,
  user_agent TEXT,
  
  data_policy TEXT NOT NULL CHECK (data_policy IN ('research', 'private'))
);

CREATE INDEX responses_scale_idx ON responses(scale_id);
CREATE INDEX responses_respondent_idx ON responses(respondent_id);
CREATE INDEX responses_created_idx ON responses(created_at);
```

#### `share_links` table

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

#### `user_profiles` table

```sql
CREATE TABLE user_profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  
  role TEXT CHECK (role IN ('scientist', 'business', 'respondent')),
  organization TEXT,
  
  preferred_language TEXT DEFAULT 'en',
  email_notifications BOOLEAN DEFAULT true
);
```

### RLS Policies

**Critical requirement (FR-RESP-2):** Research scale responses are pooled; Business scale responses are private.

**Scales RLS:**

```sql
ALTER TABLE scales ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Published scales viewable by everyone"
  ON scales FOR SELECT
  USING (status = 'published');

CREATE POLICY "Creators can view own scales"
  ON scales FOR SELECT
  USING (auth.uid() = creator_id);

CREATE POLICY "Creators can update own drafts"
  ON scales FOR UPDATE
  USING (auth.uid() = creator_id AND status = 'draft');

CREATE POLICY "Authenticated users can create scales"
  ON scales FOR INSERT
  WITH CHECK (auth.uid() = creator_id);
```

**Responses RLS (most critical):**

```sql
ALTER TABLE responses ENABLE ROW LEVEL SECURITY;

-- Research scales: creator can see aggregated data
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

-- Private (business) scales: only creator sees responses
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

-- Anyone can submit responses (anonymous or authenticated)
CREATE POLICY "Anyone can submit responses"
  ON responses FOR INSERT
  WITH CHECK (true);
```

**Share links RLS:**

```sql
ALTER TABLE share_links ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Active share links viewable by everyone"
  ON share_links FOR SELECT
  USING (active = true);

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

### Triggers

**Update response_count on scales:**

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

**Update updated_at timestamps:**

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

### Seed data (FR-CAT-2)

**Task:** Research 5–10 public-domain scales to seed the catalog.

**Candidates to research:**
1. **IPIP Big Five** (50-item or 100-item) — public domain, Goldberg
2. **PANAS** (20-item) — Positive and Negative Affect Schedule, may have open versions
3. **Rosenberg Self-Esteem Scale** (10-item) — widely used, check license
4. **Brief COPE** (28-item) — coping strategies, check license
5. **Satisfaction With Life Scale** (5-item) — Diener et al., check license

**Research steps:**
1. Search for each scale in literature databases (OpenAlex, Semantic Scholar)
2. Verify license status (public domain, CC license, or unclear)
3. If open: include full items in seed
4. If closed/unclear: include citation only (no items)

**File:** `supabase/seed.sql`

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
  'Goldberg, L. R. (1992). The development of markers for the Big-Five factor structure. Psychological Assessment, 4(1), 26-42.',
  '10.1037/0033-2909.117.1.21',
  'open',
  '[
    {"id": "ipip_e1", "text": "I am the life of the party.", "dimension": "Extraversion", "indicator": "sociability"},
    {"id": "ipip_e2", "text": "I talk to a lot of different people at parties.", "dimension": "Extraversion", "indicator": "sociability"},
    ...
  ]'::jsonb,
  '[
    {"name": "Extraversion", "definition": "Energy, positive emotions, surgency, assertiveness, sociability and the tendency to seek stimulation in the company of others."},
    {"name": "Agreeableness", "definition": "A tendency to be compassionate and cooperative rather than suspicious and antagonistic towards others."},
    ...
  ]'::jsonb,
  5, -- Has norms
  'published'
);

-- Add 4-9 more scales (to be researched)
```

**Note:** If a scale is found but has closed/unclear license, still seed it with citation only (no `items` field), so the catalog can recommend it during literature research.

### Testing

**Schema tests** (`supabase/tests/test_schema.sql`):

```sql
-- Verify all tables exist
SELECT table_name FROM information_schema.tables 
WHERE table_schema = 'public';

-- Verify RLS is enabled
SELECT tablename, rowsecurity FROM pg_tables 
WHERE schemaname = 'public';

-- Verify triggers exist
SELECT trigger_name, event_manipulation, event_object_table 
FROM information_schema.triggers 
WHERE trigger_schema = 'public';
```

**RLS tests** (`supabase/tests/test_rls.sql`):

```sql
-- Test 1: Unauthenticated user can view published scales
SET ROLE anon;
SELECT COUNT(*) FROM scales WHERE status = 'published';
-- Expected: > 0

-- Test 2: Unauthenticated user cannot view drafts
SELECT COUNT(*) FROM scales WHERE status = 'draft';
-- Expected: 0

-- Test 3: Creator can view own drafts
SET ROLE authenticated;
SET request.jwt.claims.sub = '<creator_uuid>';
SELECT COUNT(*) FROM scales WHERE creator_id = '<creator_uuid>' AND status = 'draft';
-- Expected: > 0

-- Test 4: Business scale responses are private
-- (requires test data setup, deferred to integration tests)
```

Run tests:

```bash
psql -h localhost -U postgres -d postgres -f supabase/tests/test_schema.sql
psql -h localhost -U postgres -d postgres -f supabase/tests/test_rls.sql
```

### Next.js integration

**Environment variables** (`.env.local`):

```bash
SUPABASE_URL=http://localhost:54321
SUPABASE_ANON_KEY=eyJ...  # From supabase start output
SUPABASE_SERVICE_ROLE_KEY=eyJ...  # For admin operations (never expose to client)
```

**Client setup** (`src/lib/supabase.ts`):

```typescript
import { createClient } from '@supabase/supabase-js';

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL!;
const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!;

export const supabase = createClient(supabaseUrl, supabaseAnonKey);
```

**Smoke test query:**

```typescript
// Should be run as part of integration test, not this spec
const { data: scales, error } = await supabase
  .from('scales')
  .select('*')
  .eq('status', 'published')
  .limit(10);

console.log(`Found ${scales?.length} published scales`);
```

---

## Risks and mitigations

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| Seed scales have licensing issues | Medium | Research carefully; include citation-only entries for unclear licenses |
| RLS policies too permissive/restrictive | Medium | Write comprehensive RLS tests; test with different user roles |
| Migration fails on existing data | Low | This is initial migration, no existing data |
| Supabase CLI version mismatch | Low | Document exact version in README |

---

## Tasks

### Setup

- [ ] Install Supabase CLI: `npm install -g supabase`
- [ ] Initialize: `supabase init`
- [ ] Start Supabase: `supabase start`
- [ ] Document connection details in `supabase/README.md`

### Schema

- [ ] Create migration file: `20261126120000_initial_schema.sql`
- [ ] Add all table definitions (scales, responses, share_links, user_profiles)
- [ ] Add RLS policies for each table
- [ ] Add triggers (response_count, updated_at)
- [ ] Add indexes
- [ ] Apply migration: `supabase db push`

### Seed data

- [ ] Research 5–10 public-domain scales (IPIP, PANAS, Rosenberg, etc.)
- [ ] Verify license status for each
- [ ] Create `supabase/seed.sql` with scale data
- [ ] Load seed: `psql -h localhost -U postgres -d postgres -f supabase/seed.sql`
- [ ] Verify seed loaded: query scales table

### Testing

- [ ] Write schema tests: `supabase/tests/test_schema.sql`
- [ ] Write RLS tests: `supabase/tests/test_rls.sql`
- [ ] Run tests and verify output
- [ ] Document test execution in README

### Integration

- [ ] Install Supabase JS client: `npm install @supabase/supabase-js`
- [ ] Create `.env.local` with connection details
- [ ] Create `src/lib/supabase.ts` client
- [ ] Write smoke test query (run manually)
- [ ] Document environment variables in README

### Documentation

- [ ] `supabase/README.md`: setup, migration, seed, test instructions
- [ ] Add connection details template to README
- [ ] Document RLS policy logic and trade-offs

---

## Acceptance

This spec is complete when:

1. Supabase container is running and healthy
2. All migrations applied successfully
3. Seed scales loaded (5–10 scales)
4. RLS tests pass
5. Next.js client can connect and query scales
6. Code and migrations committed
7. Journal entry documents seed scales chosen and any license findings

---

## References

- PRD: FR-CAT (catalog), FR-RESP (responses and data policy), NFR-6 (security)
- Steering: `04-database-schema.md` (full schema reference)
- Supabase docs: https://supabase.com/docs
- Supabase CLI: https://supabase.com/docs/guides/cli

---

**Next spec:** `03-config-structure.md` (app-config/ foundation)
