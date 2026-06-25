# sap-dex2odata

ABAP tool for **S/4HANA** that discovers **data-extraction (DEX) CDS views** and publishes
the selected ones as **OData services** for third-party extraction.

It reads the **released catalog entity `I_DataExtractionEnabledView`** (SQL name
`IXTRCTNENBLDVW`) and classifies views into two families with different strategies:

| Family | Match | Strategy | Mechanism |
|--------|-------|----------|-----------|
| Transactional | `C_*DEX`, released **+ CDC** | **delta** (CDC) | ODP-OData (SEGW ODP DSR) |
| Master data | `I_*`, released (CDC ignored) | **full reload**, nightly/weekly | plain (non-ODP) OData |

It runs in two phases:

1. **Inventory + readiness** — selects from `I_DataExtractionEnabledView` (filtering
   `IS_RELEASED = 'X'`), classifies each row by family, assigns mode + schedule, and lists them
   in an ALV grid.
2. **Publish** — for the views you tick, routes by strategy: delta views become a SEGW project
   with an *ODP Data Source Reference* (delta), master-data views become a plain CDS-referenced
   OData service (full reload). Both generate runtime + register on the Gateway hub
   (`/IWFND/MAINT_SERVICE`), consumable at `/sap/opu/odata/sap/<service>`.

## Objects

| Object | Type | Purpose |
|--------|------|---------|
| `Z_DEX2ODATA` | report | selection screen + ALV (`CL_SALV_TABLE`) + publish orchestration |
| `ZIF_DEX_PUBLISHER` | interface | publish contract (mechanism is swap-able) |
| `ZCL_DEX_ODP_CATALOG` | class | discovery from `I_DataExtractionEnabledView` + family classification |
| `ZCL_DEX_SERVICE_CHECK` | class | detect already-published services |
| `ZCL_DEX_NAMER` | class | collision-free SEGW/service name derivation |
| `ZCL_DEX_SEGW_ODP_PUBLISHER` | class | delta family: SEGW ODP DSR → generate → register |
| `ZCL_DEX_CDS_PUBLISHER` | class | master-data family: plain CDS OData, full reload |

## Status / important note

Discovery and the full UI are functional. The **publish automation**
(`ZCL_DEX_SEGW_ODP_PUBLISHER`) uses `/IWBEP/` + `/IWFND/` APIs whose exact signatures are
**release-dependent**, so it is isolated behind one method and currently returns the precise
**manual steps** (status `P`) instead of fabricating unverified API calls. Run with the
**Preview** flag first; wire the automation per the in-code extension point after validating
the APIs on your release.

## Deploy

Import via [abapGit](https://abapgit.org) (`src/` layout, prefix folder logic). Then run
`Z_DEX2ODATA` in SAP GUI (SE38 / SA38).

## License

See [LICENSE](LICENSE).
