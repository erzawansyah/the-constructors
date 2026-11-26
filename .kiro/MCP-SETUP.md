# MCP Setup Guide — The Constructors

## Development tools vs Application tools

**Development tools** — masuk `.kiro/settings/mcp.json`, dipakai Kiro/AI saat menulis kode:

- **Context7**: Lookup dokumentasi library (Strands SDK, EGAnet, lavaan, Next.js, Supabase, dll.)

**Application tools** — runtime, dipanggil oleh literature agent saat pipeline jalan:

- **Semantic Scholar API**: Cari paper psikometri, verifikasi sitasi
- **OpenAlex API**: Verifikasi DOI, cari existing scales
- **Crossref API**: Verifikasi DOI

Semantic Scholar, OpenAlex, Crossref **bukan MCP server** — diimplementasi sebagai HTTP clients di `src/lib/literature-apis/` (Spec 5).

---

## Setup Context7 (Development MCP)

Context7 by Upstash memberi AI akses dokumentasi library up-to-date saat coding (Strands, EGAnet, Next.js, Supabase, dll.).

Context7 menggunakan **streamable HTTP dengan OAuth** — tidak perlu API key, tidak perlu package npm.

**Edit `.kiro/settings/mcp.json`:**

```json
{
  "mcpServers": {
    "context7": {
      "url": "https://mcp.context7.com/mcp/oauth"
    }
  }
}
```

**Catatan:** Kiro menggunakan field `url`, bukan `serverUrl` (berbeda dari Gemini config).

**Sign in:**

1. Command palette → "MCP: Reconnect All Servers"
2. Browser akan terbuka otomatis — approve sign-in Context7
3. Selesai, token disimpan otomatis

**Verify:** Minta Kiro "Find Next.js docs for server components" — Context7 harus muncul sebagai tool yang dipakai.

---

## Catatan keamanan

`.kiro/settings/mcp.json` dengan OAuth tidak mengandung secret — token OAuth disimpan terpisah oleh sistem. File ini **aman untuk di-commit**.

---

## References

- Context7 get-started: https://context7.com/get-started.md
- Context7 all clients: https://context7.com/docs/resources/all-clients
- MCP servers registry: https://github.com/modelcontextprotocol/servers
