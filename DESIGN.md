# kris — design document

A single Go binary for managing every mutable database in `krisyotam.com`,
plus two thin wrapper scripts (`kris-upload`, `kris-notebook`) for
LLM-mediated tasks. Replaces the bin-layer bash scripts (`write`, `dwrite`,
`create`, `dcreate`, `edit`, `dedit`, `dread`, `dbrowse`, `dnotes`, `dlog`,
`tag`) with one source of truth.

Status: **structure locked, code not yet written.**

---

## 1. Why

The current bin layer is ~2,800 lines of bash split into eight near-duplicate
scripts. Three real problems:

1. **CLI/dmenu pairs are duplicates.** `create`/`dcreate`, `edit`/`dedit`,
   `write`/`dwrite` carry the same taxonomy and DB logic twice, with only
   the prompt UI differing. Every schema change touches two files.
2. **Hand-rolled SQL with shell quoting is a footgun.** Quotes are escaped
   with `${var//\'/\'\'}`. One title containing `';--` and you eat data.
3. **Taxonomy lives in N places.** Content type lists, valid statuses,
   valid confidences appear in `create`, `edit`, `dwrite`, `dcreate`, the
   internal repo scripts, and `~/.claude/docs/`. They drift.

A single Go binary solves all three: shared types, parameterized SQL via
`database/sql`, single config + taxonomy file consumed everywhere.

In addition the bin layer only covers ~10 of the ~120 mutable tables. Total
control over content authoring across all eight DBs requires expanding scope
beyond what a shell rewrite would justify.

## 2. Scope

`kris` mutates seven of the eight DBs in `~/dev/krisyotam.com/public/data/`:

| DB | Mutable | Purpose |
|---|---|---|
| `content.db` (8.7M) | yes | Long-form authorial content (blog/essays/fiction/papers/progym/reviews/verse/diary), academic (lectures/courses/textbooks/workbooks/research), notebooks/prayers/prompts, sequences, categories, tags |
| `system.db` (2.4M) | yes | TIL/now/quotes/words/sources, blogroll/podroll, shop_*, changelog_*, people/locations/supporters, scripts*, twitch*/youtube* |
| `reference.db` (59M) | partial | Curated additions to `poems`, `essais`, `prayer`, `rules_of_the_internet`, `symbols`. **Read-only**: `kjv_1611`, `merriam_webster`, `oed`, `mitzvot`, `cpi` |
| `media.db` (656K) | yes | All `reading_*`, `watched`/`anime_watched`/`tv_watched`, `fav_*`, `library`, `want_to_read`, `films`/`games`/`movies`, `music`/`playlist` |
| `music.db` (20K) | yes | playlists, registry |
| `lab.db` (28K) | yes | surveys + survey_responses |
| `interactions.db` (120K) | **no** | Comments/reactions — site writes; `kris` reads only |
| `storage.db` (40K) | **no** | Buckets/objects (Vercel Blob index) — `kris` reads only |

Read-only tables are listed in `[readonly]` in `config.toml` and `kris`
refuses writes unless `--force` is passed.

## 3. Out of scope

- **Site rendering / Next.js code.** `kris` does not touch JSX/TSX.
- **`generateMetadata.js` rewrite.** Stays as-is; `kris create` shells out to it.
- **Internal `public/scripts/` rewrite.** `dev/`, `prose/`, `verse/`, `prod/`,
  `doc/` stay as Node/Go/Python. They are correctly placed by language affinity.
- **Bubbletea TUI.** Picker stays fzf+nnn+dmenu+CLI prompts.
- **Web UI.** The site itself is the web UI for browsing.
- **Building.** No `make build` or `go build` runs automatically; user invokes manually.

## 4. Shell stack

| Layer | Role |
|---|---|
| `sh` | POSIX baseline (`#!/bin/sh` shebang for any shipped wrapper) |
| `mksh` | Primary user shell (POSIX-compliant + Korn extensions) |
| `rc` | Occasional alternate; doesn't constrain script-writing |

Implications:

- The Go binary itself is shell-agnostic (no shell features used).
- `kris-notebook` and any cron/hook glue use POSIX sh.
- `kris-upload` uses Python (YAML parsing + JSON prompt assembly + JSON
  response parsing — three things sh is bad at).
- Shell completions ship for fish, bash, mksh, zsh.

## 5. Distribution layout

```
~/dev/kris/
├── DESIGN.md                  # this file
├── README.md
├── Makefile                   # documents build steps; never auto-runs
├── .gitignore
├── go.mod / go.sum            # initialized when first Go file is written
├── cmd/
│   ├── kris/                  # main binary
│   ├── kris-upload/           # Python LLM wrapper
│   └── kris-notebook/         # POSIX sh wrapper
├── internal/
│   ├── config/                # loads ~/.config/kris/config.toml
│   ├── taxonomy/              # loads ~/.config/kris/taxonomy.toml
│   ├── db/                    # parameterized SQLite layer (modernc.org/sqlite, no CGO)
│   ├── slug/                  # slugify + global collision check
│   ├── picker/                # fzf | dmenu dispatch
│   ├── editor/                # draft | code | $EDITOR by extension
│   ├── meta/                  # shells out to generateMetadata.js
│   ├── backup/                # snapshot DB before writes
│   ├── audit/                 # append-only mutation log
│   ├── form/                  # generic per-table form runner
│   ├── fav/                   # ranked-list operations (sort_order)
│   ├── ref/                   # read-only reference lookups
│   ├── shop/                  # composite shop_items wizard
│   ├── survey/                # composite survey wizard
│   ├── sync/                  # post-write hook orchestration
│   └── doctor/                # validation / orphan detection
├── completions/               # generated by `make completions`
├── docs/                      # extra docs (taxonomy notes, schema dumps)
└── scripts/                   # one-shot dev helpers (schema dump, migration)
```

```
~/.config/kris/
├── config.toml                # paths, UI prefs, backup, hooks, readonly
├── taxonomy.toml              # content types, enums, per-table column shapes
├── cdn-map.yaml               # kris-upload destination map
└── notebook-map.yaml          # kris-notebook frontmatter template

~/.local/state/kris/
├── backups/                   # rolling DB snapshots
└── audit.log                  # JSONL mutation log
```

## 6. Subcommand surface

```
# Long-form authorial (the existing surface)
kris create [type] [--manual] [--with-claude]   # default: manual
kris edit   [type] [slug]                       # field-by-field fzf flow
kris open   [type] [slug]                       # nnn picks file, draft/code opens it
kris browse [type]                              # was dbrowse/dread

# Atomic quick-adds
kris quote add                                  # quotes (text/author/source/character)
kris word  add <word>                           # words
kris source add <url>                           # sources

# Consumption logs (media.db)
kris log read <book|paper|essay|blog|speech|verse|audiobook>
kris log watch <film|tv|anime>
kris log play <game>
kris log listen <music>
kris fav  add <category> <item> [--rank N]      # ranked list, bumps others
kris fav  rm  <category> <item>                 # closes the gap
kris fav  move <category> <item> <new-rank>
kris fav  reorder <category>                    # opens $EDITOR with numbered list
kris want <category> <item>                     # want_to_read

# Catalogs (system.db)
kris catalog blogroll [add|edit|rm|list]
kris catalog podroll  [...]
kris catalog scripts  [...]
kris catalog twitch   [...]
kris catalog youtube  [...]
kris catalog people   [...]
kris catalog location [...]
kris catalog source   [...]

# Composites (multi-table — wizard mode by default)
kris shop item   [new|edit|variant|option|image|related|list]
kris survey      [new|edit|results|list]
kris seq         [new|add|rm|reorder|list]      # sequences

# System metadata
kris changelog content add
kris changelog infra   add
kris til  add|edit|list
kris now  add|edit|list

# Read-only reference lookups
kris ref  kjv  "John 3:16"
kris ref  oed  <word>
kris ref  webster <word>
kris ref  mitzvot <n>
kris ref  rule  <n>
kris ref  symbol <slug>
kris ref  search <db>:<table> "<query>"          # FTS5

# Cross-cutting
kris info    <slug>                             # any DB, global slug lookup
kris search  <query>                            # FTS across titles+previews
kris stats
kris check-slug <slug>
kris doctor                                     # validate refs, orphans, drift
kris export  <type|all> [--out file.json]
kris import  [--in file.json] [--dry-run]
kris sync                                       # run [hooks].post_create
kris backup  [list|restore <ts>|prune]
kris audit   [tail|grep <pat>|since <ts>]
kris tag     [list|add|rm|merge|rename|prune]
kris completion <shell>                         # emit completion script

# Global flags
  --dmenu                                       # use dmenu instead of fzf
  --dry-run                                     # show SQL/effect, don't write
  --json                                        # machine output
  --force                                       # bypass readonly guard
  --no-backup                                   # skip pre-write snapshot
  --no-audit                                    # skip audit log entry
  --config <path>                               # override ~/.config/kris/config.toml
```

## 7. Locked design decisions

### 7.1 `kris create`: manual by default
- Manual flow prompts for category, tags, status, confidence, importance.
- `--with-claude` opts into Claude-driven metadata determination (the current
  `create` script's behavior).
- Both paths end at `node $generate_meta` with the same arg shape.

### 7.2 `kris edit`: field-by-field fzf flow
- Show metadata box, fzf to pick field, edit, return to box.
- Same UX as the existing `edit` script. No bubbletea full-screen form.
- Tag editing is a sub-flow: `[a]dd / [r]emove / [d]one`.

### 7.3 `kris sync`: post-write hooks only
- Configured in `[hooks].post_create` / `post_edit` / `post_delete`.
- Default: `["kris sync"]` runs slug-collision audit + sitemap regen.
- Does **not** orchestrate the full `public/scripts/dev/sync*.js` graph;
  those remain manually invoked.

### 7.4 Ranking on fav/log: bump-down on insert
The actual column is `sort_order INTEGER DEFAULT 999` (confirmed across all
ranked tables: `fav_anime`, `fav_anime_studios`, `fav_directors`,
`fav_actors`, `fav_tv_shows`, `fav_anime_characters`, `fav_film_characters`,
`anime_watched`, `tv_watched`).

```sql
-- kris fav add anime "Princess Mononoke" --rank 3
BEGIN;
  UPDATE fav_anime SET sort_order = sort_order + 1 WHERE sort_order >= 3;
  INSERT INTO fav_anime (title, sort_order) VALUES ('Princess Mononoke', 3);
COMMIT;

-- kris fav rm anime "Princess Mononoke"
BEGIN;
  DELETE FROM fav_anime WHERE title = 'Princess Mononoke' RETURNING sort_order INTO :n;
  UPDATE fav_anime SET sort_order = sort_order - 1 WHERE sort_order > :n;
COMMIT;

-- kris fav move anime "Princess Mononoke" 7
-- (transactional shift between old and new positions)
```

If `--rank` is omitted, append at `MAX(sort_order)+1`.

Tables that **don't** have `sort_order` and need a migration if ranking is
wanted: `reading_log`, `reading_now`, `reading_books`, `want_to_read`,
`watched`, `playlist`. For these, ordering is by date column (`reading_log.date`,
`watched.watched_date`) until/unless a column is added.

### 7.5 Resolution: Option 3 (free text + near-dup warn)
When inserting into a fav/catalog table, kris fuzzy-matches the input against
existing titles in the same table. If matches exist, prompt:

```
Near-matches in fav_anime:
  - "Madhouse" (sort_order 4)
  - "Mad Men" (sort_order 12)
Continue with "Madhose"? [y/N]
```

Threshold: edit distance ≤ 2 OR substring match. Tunable via
`[ui].dup_distance` (default 2).

### 7.6 Reference DB: append-then-immutable, full-text searchable
- `poems`, `essais`, `prayer`, `symbols`, `rules_of_the_internet` accept
  inserts via `kris create poems|essais|prayer|symbol` and
  `kris ref rule add`.
- `kjv_1611`, `merriam_webster`, `oed`, `mitzvot`, `cpi` are listed in
  `[readonly]`. No mutation ever.
- All ref tables get FTS5 virtual indexes. `kris ref search reference.db:oed
  "alchemy"` returns matches with snippets.
- Index regeneration is part of `kris doctor --rebuild-fts`.

### 7.7 Composites: wizard by default
- `kris shop item new` walks through item → variants → options →
  option_values → variant_options → images → related, in that order, with
  fzf for picking referenced rows.
- `kris survey new` walks survey → response schema.
- Pure flag-driven mode is available (`kris shop item new --title=... --price=...`)
  for scripting.

## 8. Editor dispatch

Single function, extension map (configurable in `config.toml`):

| Extension | Launcher |
|---|---|
| `.mdx`, `.md`, `.txt`, `.rst`, `.org` | `draft` (nvim writing config) |
| `.ts`, `.tsx`, `.js`, `.go`, `.py`, `.sh`, `.css`, `.sql`, `.toml`, `.yaml`, `.json`, `.rs`, `.c`, `.h` | `code` (vscode) |
| anything else | `$EDITOR` |

`KRIS_EDITOR_OVERRIDE` environment variable wins for one-off cases.

## 9. The eleven extras

Locked in from the planning rounds:

1. **DB backup-on-write.** Snapshot to `~/.local/state/kris/backups/<db>.<ts>`
   before any UPDATE/INSERT/DELETE. Pruned to last 30 per DB. ~50 ms cost.
2. **Audit log.** Append a JSON line per mutation to
   `~/.local/state/kris/audit.log`:
   `{ts, cmd, db, table, slug, field, old, new}`. Greppable, freely
   tail-able for "what did I change today."
3. **Tag bulk operations.** `kris tag merge old new`, `kris tag rename`,
   `kris tag prune` (drop unused tags).
4. **Status validation with warnings.** Backwards transitions
   (Finished → Draft) print a warning but proceed.
5. **`kris doctor`.** Validates: every `category_slug` exists; every
   `content_tags` row points to a real entry; no orphaned rows; slugs
   match filenames in `~/content/`; taxonomy.toml matches DB enums.
6. **Shell completions.** Generated via cobra; ship for fish/bash/mksh/zsh.
7. **`kris info <slug>`** without specifying type. Cross-table lookup,
   since slugs are globally unique by convention.
8. **Path portability.** Nothing hardcoded; everything reads from
   `[paths]` in `config.toml`. Same binary works on krislaptop after
   stowing a different `config.toml`.
9. **JSON output mode.** `--json` flag on every read command. Lets the
   binary be called from `kris-upload` and `kris-notebook` cleanly.
10. **Dry-run on every write.** `--dry-run` prints SQL and effect, exits
    without writing. Backup and audit log skipped.
11. **`kris export` / `kris import`.** Dump and reload entries as JSON.
    Useful before risky migrations or for moving content between DBs.

## 10. Hooks

`config.toml` `[hooks]` section runs commands after writes:

```toml
[hooks]
post_create = ["kris sync"]
post_edit   = []
post_delete = []
```

Each entry is a command; arguments allowed. The mutation's slug/type are
passed as env vars: `KRIS_TYPE`, `KRIS_SLUG`, `KRIS_DB`, `KRIS_TABLE`.

Hook failures don't roll back the mutation — they print a warning. The
mutation is already committed.

## 11. Wrapper scripts (separate concerns)

### 11.1 `kris-upload` (Python)

Reads `~/.config/kris/cdn-map.yaml` (committed alongside `config.toml`) and
classifies arbitrary files for upload to stargate.

```
kris-upload <file> [<file>...] [--category <cat>] [--subtype <sub>] [--dry-run]
```

Flow:
1. Load YAML map.
2. For each file: build a JSON prompt for `claude -p` with the map embedded
   and the filename + (optional) head bytes/exiftool output.
3. Claude returns `{"category", "subtype", "target_filename"}`.
4. Show the user the proposed `scp` command(s); confirm.
5. `scp file server:/mnt/storage/cdn/<category>/<subtype>/<target_filename>`.
6. Print resulting public URL(s).

Why Python and not Go: YAML parsing + JSON ↔ Claude is three lines in
Python and twenty in Go. The wrapper is invoked rarely; speed doesn't matter.

### 11.2 `kris-notebook` (POSIX sh)

Reads `~/.config/kris/notebook-map.yaml`, scaffolds a notebook entry with
proper frontmatter, then registers it via `kris create notebook`.

```
kris-notebook new <topic>
kris-notebook list
kris-notebook open <slug>
```

Why sh and not Go: it's mostly templating + calling `kris`. POSIX sh is
fine; saves a binary build.

## 12. Things that change at the site (krisyotam.com) side

These are not blockers for `kris` v1, but worth doing eventually:

1. **Reference taxonomy.toml from site code.** Today
   `public/data/taxonomy.json` (or its equivalents in JS) duplicates the
   `[content_types]` lists. Site code should read `taxonomy.toml` (via a
   small loader) so changes propagate.
2. **Add `sort_order` to date-driven media tables** if you want to override
   strict date ordering: `reading_log`, `reading_now`, `reading_books`,
   `want_to_read`, `watched`, `playlist`.
3. **Reconcile `people` vs `fav_actors`/`fav_directors` overlap.** The
   `people` table has per-type sort columns (`sort_actor`, `sort_artist`,
   etc.) suggesting it was meant as the canonical store, but separate
   `fav_actors` / `fav_directors` tables exist in `media.db`. Either is
   fine; documented in taxonomy.toml as `sort_columns_by_type` for
   `people`. Worth deciding which is canonical before wiring `kris fav`
   for actors/directors.

## 13. Migration / install path

When the user is ready to wire it:

```sh
# 1. Initialize Go module
cd ~/dev/kris
go mod init github.com/krisyotam/kris

# 2. Pull deps (no CGO sqlite)
go get modernc.org/sqlite
go get github.com/spf13/cobra
go get github.com/BurntSushi/toml
go get gopkg.in/yaml.v3

# 3. Build
make build

# 4. Install
sudo make install

# 5. Generate completions
make completions
cp completions/kris.fish ~/.config/fish/completions/
```

Old bash scripts (`write`, `dwrite`, `create`, `dcreate`, `edit`, `dedit`,
`dread`, `dbrowse`, `dnotes`, `dlog`, `tag`) get archived to
`~/.local/bin/.archived/` after `kris` reaches feature parity.

## 14. Build order recommendation

When code is started, build in this order so each step is testable on its
own:

1. `internal/config` + `internal/taxonomy` + `internal/db` → `kris info <slug>`
   works (read-only).
2. `internal/picker` + `internal/editor` → `kris open <type>` works.
3. `internal/backup` + `internal/audit` → safety nets in place before
   first write.
4. `internal/slug` + `internal/form` → `kris create [type]` (manual mode).
5. `kris edit` reusing `form` for field selection.
6. `internal/fav` → ranked list operations.
7. Atomic adds (`kris quote add`, `kris word add`).
8. Catalogs.
9. `internal/ref` → read-only lookups + FTS.
10. Composites (shop, survey, sequence).
11. `internal/doctor` + `kris export`/`import`.
12. Wrapper scripts (`kris-upload`, `kris-notebook`).
13. Completions + install scripts.

## 15. Open follow-ups (not blockers, decide later)

- **Search.** `kris search <q>` should hit FTS5 indexes on every
  searchable text column. Indexes need creation; that's its own migration.
- **Moderation.** `interactions.db` is read-only today, but eventually
  `kris mod hide <comment-id>` for spam is wanted. Drop the readonly
  entry when ready.
- **Sequences playlist.** `sequences.playlist` column exists but its semantics
  aren't documented. Need to spec what `kris seq` does with it before wiring.
- **Notebook DB destination.** `notebook-map.yaml` writes to `content.db`
  `notebooks`, but if notebooks should live somewhere else (e.g. a separate
  `notebooks.db`), change the YAML.
- **Test database.** A copy of each DB with synthetic rows for `make test`,
  so test runs don't touch real content.
- **Concurrency.** SQLite single-writer lock is fine for one user. If `kris`
  is ever invoked from multiple shells simultaneously, audit log + backup
  ordering needs a flock around the whole transaction.

## 16. What was created in this session

```
~/dev/kris/
├── DESIGN.md                  (this file)
├── Makefile                   (build targets, never auto-run)
├── .gitignore                 (extended for Go)
├── README.md                  (untouched, pre-existing stub)
├── cmd/{kris,kris-upload,kris-notebook}/   (empty dirs ready for code)
├── internal/{config,taxonomy,db,slug,picker,editor,meta,backup,audit,form,fav,ref,shop,survey,sync,doctor}/
├── completions/
├── docs/
└── scripts/

~/.config/kris/
├── config.toml                (paths, UI, backup, hooks, readonly)
├── taxonomy.toml              (content types, enums, per-table fields)
├── cdn-map.yaml               (kris-upload destination map)
└── notebook-map.yaml          (kris-notebook frontmatter template)

~/.local/state/kris/
├── backups/                   (empty; populated on first write)
└── audit.log                  (will be created on first write)
```

No Go source written yet. No `go mod init` yet. No build attempted.
The next session can `go mod init` and start at item 1 of §14.
