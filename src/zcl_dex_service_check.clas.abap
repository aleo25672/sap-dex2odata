" <p class="shorttext synchronized">Detect whether a provider already has an OData service</p>
" Used to mark providers that are already exposed so the report can show readiness
" and the publisher can skip them (idempotency).
"
" NOTE (release-dependent): the authoritative source is the Gateway hub service
" catalog (/IWFND/). The exact table/API differs by release, so the real lookup is
" isolated in CHECK( ) behind a TODO. Until wired on the target system the check
" reports "not determinable" (determinable = abap_false) and never blocks the run.
CLASS zcl_dex_service_check DEFINITION
  PUBLIC
  CREATE PUBLIC.

  PUBLIC SECTION.
    TYPES:
      BEGIN OF ty_status,
        exists       TYPE abap_bool,
        service_name TYPE c LENGTH 30,
        determinable TYPE abap_bool,
      END OF ty_status.

    " @parameter iv_entity | ODP provider / CDS entity name
    METHODS check
      IMPORTING
        iv_entity        TYPE clike
      RETURNING
        VALUE(rs_status) TYPE ty_status.
ENDCLASS.


CLASS zcl_dex_service_check IMPLEMENTATION.

  METHOD check.
    " >>> RELEASE-DEPENDENT lookup goes here <<<
    " Query the Gateway hub service catalog for a registered service whose data
    " source references CDS entity IV_ENTITY, e.g. via /IWFND/ model/registry APIs.
    " When found, set rs_status-exists = abap_true and -service_name accordingly.
    "
    " Left unwired on purpose: see class documentation. Default = not determinable,
    " which the report renders as '?' and the publisher treats as "attempt publish".
    rs_status-determinable = abap_false.
    rs_status-exists       = abap_false.
  ENDMETHOD.

ENDCLASS.
