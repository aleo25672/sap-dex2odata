# sap-dex2odata

ABAP tool for **S/4HANA** that discovers **data-extraction (DEX) CDS views** and helps expose
the selected ones as **OData services** for third-party (ODP) extraction.

It reads the extraction-enabled-views catalog **`IXTRCTNENBLDVW`**, resolves each view's **ODP
technical name** (see [Name resolution](#how-the-odp-technical-name-is-resolved)), and classifies
each view into one of two families with a different extraction strategy:

| Family | Match | Strategy | Mechanism |
|--------|-------|----------|-----------|
| Transactional | `C_*DEX`, released **+ CDC** | **delta** (CDC) | ODP-OData (SEGW ODP redefinition) |
| Master data | `I_*`, released (CDC ignored) | **full reload**, nightly/weekly | plain (non-ODP) OData |

## Objects

| Object | Type | Purpose |
|--------|------|---------|
| `Z_DEX2ODATA` | report | selection screen + ALV (`CL_SALV_TABLE`) + actions |
| `Z_ODP_ACTIVATE_ALL_DEX` | report | standalone: bulk-activate all classic ODP-CDS sources |
| `ZIF_DEX_PUBLISHER` | interface | publish contract + shared types/constants |
| `ZCL_DEX_ODP_CATALOG` | class | discovery, ODP-name resolution (`RSODPABAPCDSVIEW` + `@Analytics.technicalName`), family classification |
| `ZCL_DEX_ODP_ACTIVATOR` | class | activate views as ODP sources (`RODPS_UTILS_DATASOURCE_ACT`) |
| `ZCL_DEX_SERVICE_CHECK` | class | detect already-registered services (Gateway hub `/IWFND/I_MED_SRH`) |
| `ZCL_DEX_NAMER` | class | collision-free SEGW/service name derivation |
| `ZCL_DEX_SEGW_ODP_PUBLISHER` | class | delta family: SEGW ODP redefinition recipe |
| `ZCL_DEX_CDS_PUBLISHER` | class | master-data family: plain CDS OData, full reload |

## Using `Z_DEX2ODATA`

Run the report in SAP GUI (`SE38` / `SA38`).

### 1. Selection screen

| Field | Meaning |
|-------|---------|
| **ODP context** | ODP context shown for the providers (default `ABAP_CDS`) |
| **CDS entity pattern** | optional name filter, **case-sensitive**. Plain text = contains search (`PurchaseOrder`); `*` = explicit wildcard (`C_Purchase*DEX`); blank = all |
| **Action** | **Display list only** / **Activate ODP sources** / **Publish OData service** — runs on the filtered set |
| **Include C_*DEX (delta)** | include the transactional/delta family |
| **Include I_* master data (full)** | include the master-data/full family |
| **Hide already published** | drop rows already exposed as a service |
| **Nightly / Weekly** | full-reload schedule assigned to the master-data family |
| **Target package** | package for generated objects (use a local package for testing) |
| **Transport request** | transport for generated objects (blank for local) |
| **Preview (dry-run)** | when set, *Publish* only reports what it would do — creates nothing (default on) |
| **Recreate if exists** | recreate objects that already exist |

### 2. The list

Each row is one DEX CDS view, with the names you need downstream already derived:

- **CDS Entity** / **Description** — the view and its text
- **SQL View** — the resolved **ODP technical name** (classic view: `SQLVIEWNAME`, e.g.
  `CMMPRITMDEX`; view entity: `@Analytics.technicalName`, e.g. `CMMPURORDDEX`)
- **Family / Mode / Schedule** — classification + strategy (DELTA / FULL, nightly/weekly)
- **Released / CDC-Delta** — the catalog flags
- **ODP Src $F** — the value to type into the SEGW redefinition: `<name>$F`
- **Facts set / Delta set** — the OData entity sets the service exposes
  (`FactsOf<name>` = full, `DeltaLinksOf<name>` = delta)
- **Published / Service** — set when a matching **active** service (`Z_<entity>_SRV`) is already
  registered on the Gateway hub (checked against `/IWFND/I_MED_SRH`). Use **Hide already
  published** to drop these rows.
- **Reason** — filled when a name could not be resolved

### 3. Actions

Pick an **Action** on the selection screen. It runs on **all rows matching the filter** — narrow
with the entity pattern to target a subset. (Selection is on the selection screen, not via ALV
row-selection.)

- **Display list only** — just show the grid.
- **Activate ODP sources** — *Step 1.* Activates the views as ODP sources
  (`RODPS_UTILS_DATASOURCE_ACT`) so SEGW can find them; a results ALV shows the outcome per row.
- **Publish OData service** — routes by family and, in **Preview**, prints the per-view recipe
  (project name, ODP source `<name>$F`, entity sets). With Preview off it runs the publish path
  (see *Status* below).

### 4. End-to-end workflow

1. Run the report, filter to the views you want.
2. Set **Action = Activate ODP sources** (narrow with the entity pattern). Verify in
   `RODPS_REPL_TEST` (context `ABAP_CDS`, ODP name = the **SQL View**).
3. In **SEGW**: create a project → *Data Model → Redefine → ODP Extraction* →
   ODP context **ABAP Core Data Services**, ODP source = the **ODP Src $F** value from the grid →
   **Generate Runtime Objects**. (The grid's *Publish/Preview* gives you the project + names.)
4. In **`/IWFND/MAINT_SERVICE`** → *Add Service* → system alias `LOCAL` → the generated technical
   service → *Add Selected Services*.
5. **Activate the ICF node.** The service returns HTTP 403 until its ICF node is active: in
   `SICF`, go to `default_host/sap/opu/odata/sap/<service>` and *Activate Service*
   (right-click → Activate Service). Some systems auto-activate it on registration — check, and
   activate if the node is grey/inactive.
6. Test: `GET /sap/opu/odata/sap/<service>/$metadata` → the `FactsOf…` / `DeltaLinksOf…`
   entity sets should be present; a delta request then returns only changes.

## How the ODP technical name is resolved

Every extraction view needs an **ODP technical name** — that's what SEGW's *Redefine → ODP
Extraction* expects (as `<name>$F`), and it differs by view kind:

| View kind | How to tell (SE11 → *Data type* → DDL Source) | ODP technical name | Where the tool reads it |
|-----------|-----------------------------------------------|--------------------|-------------------------|
| **Classic CDS view** | `@AbapCatalog.sqlViewName: 'CMM…'` + `define view …` | the SQL view name (e.g. `CMMPRITMDEX`) | `RSODPABAPCDSVIEW.SQLVIEWNAME` |
| **CDS view entity** | `define view entity …` (no `sqlViewName`) + `@Analytics.technicalName: 'CMM…'` | the technical name (e.g. `CMMPURORDDEX`) | `RSODPABAPCDSVIEW.STRUCTOBJNAME`, else the `@Analytics.technicalName` header annotation in **`DDHEADANNO`** |

`ZCL_DEX_ODP_CATALOG` resolves in this order:

1. **`RSODPABAPCDSVIEW`** by `DDLNAME` (matched **case-insensitively** — `DDLNAME` is stored upper
   case while the catalog view name is mixed case): use `SQLVIEWNAME` if present, else
   `STRUCTOBJNAME`.
2. **Fallback: `DDHEADANNO`** where `NAME = 'Analytics.technicalName'`, keyed on `STRUCOBJN` =
   entity. The stored `VALUE` keeps the source quotes (`'CMM…'`) — the tool strips them.

The resolved name shows in the **SQL View** column and drives `<name>$F` / `FactsOf<name>` /
`DeltaLinksOf<name>`. The authoritative cross-check is **SEGW's F4** on the ODP source field: it
lists the live ODP framework (context `ABAP_CDS`) — the same names.

## Notes & gotchas (learned the hard way)

- **`RODPS_REPL_TEST` only finds *activated* ODP sources.** A view that isn't activated yet won't
  appear there under any name — activate it first (Step 1), then test.
- **`RSODPABAPCDSVIEW` is not a complete list.** It reliably holds classic views; view entities
  may be absent, which is why the tool falls back to `@Analytics.technicalName`.
- **`RODPS_UTILS_DATASOURCE_ACT` `sy-subrc` is unreliable** — it can return `0` even when nothing
  was activated. Confirm real availability in `RODPS_REPL_TEST` (or that SEGW can find the `$F`).
- **A registered service returns HTTP 403** until its **ICF node** is activated in `SICF`.
- Field-name / casing surprises worth remembering: `IXTRCTNENBLDVW` columns are
  `DATAEXTRACTIONVIEWNAME` / `DATAEXTRACTIONVIEWDESCRIPTION` / `ISSAPRELEASEDVIEW` /
  `DELTACHGDATACAPTUREISSUPPORTED` (not `IS_RELEASED` etc.); `RSODPABAPCDSVIEW` columns are
  `SQLVIEWNAME` / `DDLNAME` / `STRUCTOBJNAME`; `DDLNAME` is upper case; `DDHEADANNO.VALUE` keeps
  the annotation's quotes.

## Status / automation

- **Step 1 (ODP activation)** and **Step 2 (SQL view + `$F` + entity-set names)** are **automated**
  in the tool.
- **Step 3 (SEGW project + ODP redefinition + Generate)** and **Step 4 (`/IWFND` registration)**
  are currently **manual but fully recipe-driven** — the grid hands you every name. Programmatic
  generation is isolated behind `ZCL_DEX_SEGW_ODP_PUBLISHER` / `ZCL_DEX_CDS_PUBLISHER`
  (`/IWBEP/` + `/IWFND/` APIs are release-dependent); until wired they return the manual steps
  (status `P`). Use **Preview** first.

## Installing & importing with abapGit

This repo is serialized in [abapGit](https://abapgit.org) format (`src/` layout, prefix folder
logic). To get it into an S/4HANA system:

### 1. Install abapGit (one-time)

1. Download the standalone report from
   <https://raw.githubusercontent.com/abapGit/build/main/zabapgit_standalone.prog.abap>.
2. `SE38` → create program **`ZABAPGIT_STANDALONE`** (type *Executable program*, no TOP include).
3. Paste the whole file, **Save**, **Activate** (Ctrl+F3), run it (F8).

### 2. Trust GitHub's TLS certificate (one-time)

Without this, clone fails with `SSL handshake … SSSLERR_PEER_CERT_UNTRUSTED`.

1. In a browser open <https://github.com>, view the certificate, and export the **CA chain** as
   Base64 `.cer` files — currently *Sectigo Public Server Authentication CA DV E36*,
   *Sectigo … Root E46*, and the root *USERTrust ECC Certification Authority*.
   *(Or via openssl: `openssl s_client -connect github.com:443 -servername github.com -showcerts`.)*
2. `STRUST` → **Display ↔ Change** → double-click **SSL client SSL Client (Standard)**.
3. **Import Certificate** (bottom) → pick a CA file (Base64) → **Add to Certificate List**.
   Repeat for each CA (import the **root first**). Do the same for **SSL Client (Anonymous)** if
   present. **Save**.
4. `SMICM` → **Administration → ICM → Exit Soft → Global** (reloads the trust store).

### 3. Create a GitHub Personal Access Token (private repos only)

GitHub no longer accepts your account password over HTTPS — use a PAT as the password.

1. GitHub → avatar → **Settings → Developer settings → Personal access tokens → Tokens (classic)**.
2. **Generate new token (classic)** → set an expiry → scope **`repo`** (covers clone *and* push).
3. **Generate** and **copy** the token (shown once).

*(Public repos need no token.)*

### 4. Create a target package

- **Local / testing:** create a `$`-prefixed package, e.g. **`$DEX2ODATA`** (`SE80` → Package →
  create). `$` packages are local: no software component, no transport prompt. *(abapGit blocks
  the literal `$TMP`, so use a named `$…` package.)*
- **Transportable:** a normal `Z…` package with software component **`HOME`** and a transport
  request.

### 5. Clone the repo

In abapGit: **+ New Online** →
- URL: `https://github.com/aleo25672/sap-dex2odata.git`
- Branch: `main`
- Package: your package from step 4
- When prompted for credentials: **User** = your GitHub user, **Password** = the **PAT**.

### 6. Pull & activate

After clone, the objects show as new → **Pull**. Then **activate all objects together**
(select them all and mass-activate) so dependencies resolve in the right order — in particular
`ZCL_DEX_ODP_CATALOG` must activate before `ZCL_DEX_ODP_ACTIVATOR`/`Z_DEX2ODATA`.

### 7. Getting later updates

When the repo changes, open it in abapGit → **Pull** → mass-activate the changed objects again.

### Release dependencies to confirm

Tables `IXTRCTNENBLDVW`, `RSODPABAPCDSVIEW`, `DDHEADANNO`, `/IWFND/I_MED_SRH`, and function
module `RODPS_UTILS_DATASOURCE_ACT` (+ types `rodps_t_datasource` / `rodps_t_msg`) must exist on
your release.

## License

See [LICENSE](LICENSE).
