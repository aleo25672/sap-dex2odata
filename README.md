# sap-dex2odata

ABAP tool for **S/4HANA** that discovers **data-extraction (DEX) CDS views** and helps expose
the selected ones as **OData services** for third-party (ODP) extraction.

It reads the extraction-enabled-views catalog **`IXTRCTNENBLDVW`** (joined to
**`RSODPABAPCDSVIEW`** for the SQL view name) and classifies each view into one of two families
with a different extraction strategy:

| Family | Match | Strategy | Mechanism |
|--------|-------|----------|-----------|
| Transactional | `C_*DEX`, released **+ CDC** | **delta** (CDC) | ODP-OData (SEGW ODP redefinition) |
| Master data | `I_*`, released (CDC ignored) | **full reload**, nightly/weekly | plain (non-ODP) OData |

## Objects

| Object | Type | Purpose |
|--------|------|---------|
| `Z_DEX2ODATA` | report | selection screen + ALV (`CL_SALV_TABLE`) + actions |
| `ZIF_DEX_PUBLISHER` | interface | publish contract + shared types/constants |
| `ZCL_DEX_ODP_CATALOG` | class | discovery + family classification + name derivation |
| `ZCL_DEX_ODP_ACTIVATOR` | class | activate views as ODP sources (`RODPS_UTILS_DATASOURCE_ACT`) |
| `ZCL_DEX_SERVICE_CHECK` | class | detect already-published services |
| `ZCL_DEX_NAMER` | class | collision-free SEGW/service name derivation |
| `ZCL_DEX_SEGW_ODP_PUBLISHER` | class | delta family: SEGW ODP redefinition recipe |
| `ZCL_DEX_CDS_PUBLISHER` | class | master-data family: plain CDS OData, full reload |

## Using `Z_DEX2ODATA`

Run the report in SAP GUI (`SE38` / `SA38`).

### 1. Selection screen

| Field | Meaning |
|-------|---------|
| **ODP context** | ODP context shown for the providers (default `ABAP_CDS`) |
| **CDS entity pattern** | optional name filter, **case-sensitive**, `*` = wildcard (e.g. `C_Purchase*`) |
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
- **SQL View** — `SQLVIEWNAME` (e.g. `CMMPRITMDEX`)
- **Family / Mode / Schedule** — classification + strategy (DELTA / FULL, nightly/weekly)
- **Released / CDC-Delta** — the catalog flags
- **ODP Src $F** — the value to type into the SEGW redefinition: `<SQLVIEW>$F`
- **Facts set / Delta set** — the OData entity sets the service exposes
  (`FactsOf<SQLVIEW>` = full, `DeltaLinksOf<SQLVIEW>` = delta)

### 3. Toolbar actions

Tick one or more rows (leading checkbox), then:

- **Activate ODP** — *Step 1.* Activates the selected views as ODP sources
  (`RODPS_UTILS_DATASOURCE_ACT`) so SEGW can find them. A results popup shows success per row.
- **Publish selected** — routes by family and, in **Preview**, prints the exact per-view recipe
  (project name, ODP source `<SQLVIEW>$F`, service name, entity sets). With Preview off it runs
  the publish path (see *Status* below).

### 4. End-to-end workflow

1. Run the report, filter to the views you want.
2. Select rows → **Activate ODP**. Verify in `RODPS_REPL_TEST` (context `ABAP_CDS`,
   ODP name = the **SQL View**).
3. In **SEGW**: create a project → *Data Model → Redefine → ODP Extraction* →
   ODP context **ABAP Core Data Services**, ODP source = the **ODP Src $F** value from the grid →
   **Generate Runtime Objects**. (The grid's *Publish/Preview* gives you the project + names.)
4. In **`/IWFND/MAINT_SERVICE`** → *Add Service* → system alias `LOCAL` → the generated technical
   service → *Add Selected Services*.
5. Test: `GET /sap/opu/odata/sap/<service>/$metadata` → the `FactsOf…` / `DeltaLinksOf…`
   entity sets should be present; a delta request then returns only changes.

## Status / automation

- **Step 1 (ODP activation)** and **Step 2 (SQL view + `$F` + entity-set names)** are **automated**
  in the tool.
- **Step 3 (SEGW project + ODP redefinition + Generate)** and **Step 4 (`/IWFND` registration)**
  are currently **manual but fully recipe-driven** — the grid hands you every name. Programmatic
  generation is isolated behind `ZCL_DEX_SEGW_ODP_PUBLISHER` / `ZCL_DEX_CDS_PUBLISHER`
  (`/IWBEP/` + `/IWFND/` APIs are release-dependent); until wired they return the manual steps
  (status `P`). Use **Preview** first.

## Deploy

Import via [abapGit](https://abapgit.org) (`src/` layout, prefix folder logic) into a package
(a local package is fine for testing). **Activate all objects together** so dependencies resolve
in the right order. Then run `Z_DEX2ODATA`.

Dependencies to confirm on your release: tables `IXTRCTNENBLDVW` / `RSODPABAPCDSVIEW`, and
function module `RODPS_UTILS_DATASOURCE_ACT` (+ types `rodps_t_datasource` / `rodps_t_msg`).

## License

See [LICENSE](LICENSE).
