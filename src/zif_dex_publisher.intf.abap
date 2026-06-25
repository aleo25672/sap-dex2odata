"! <p class="shorttext synchronized">DEX publisher contract: expose one provider as OData</p>
"! Implementations turn one extraction/CDC-enabled CDS view (ODP provider) into a
"! consumable ODP-OData service. The mechanism (SEGW ODP reference, @OData.publish,
"! Service Binding, ...) is hidden behind this interface so it can be swapped.
INTERFACE zif_dex_publisher
  PUBLIC.

  "! Extraction strategy assigned per CDS family
  CONSTANTS:
    BEGIN OF c_mode,
      delta TYPE c LENGTH 5 VALUE 'DELTA',  " C_*DEX transactional, CDC delta (ODP)
      full  TYPE c LENGTH 5 VALUE 'FULL',   " I_* master data, full reload (plain OData)
    END OF c_mode.

  "! Full-reload schedule (only relevant for FULL mode)
  CONSTANTS:
    BEGIN OF c_schedule,
      none    TYPE c LENGTH 8 VALUE space,
      nightly TYPE c LENGTH 8 VALUE 'NIGHTLY',
      weekly  TYPE c LENGTH 8 VALUE 'WEEKLY',
    END OF c_schedule.

  "! Generated object names for one OData service
  TYPES:
    BEGIN OF ty_names,
      segw_project    TYPE c LENGTH 30,
      service_name    TYPE c LENGTH 30,
      service_version TYPE n LENGTH 4,
      external_name   TYPE c LENGTH 30,
    END OF ty_names,

    "! Options that steer a publish run
    BEGIN OF ty_options,
      package   TYPE devclass,
      transport TYPE trkorr,
      preview   TYPE abap_bool,
      recreate  TYPE abap_bool,
      mode      TYPE c LENGTH 5,   " see c_mode (DELTA / FULL)
      schedule  TYPE c LENGTH 8,   " see c_schedule (FULL only)
    END OF ty_options,

    "! Outcome of publishing one provider.
    "! status: S success | E error | P pending manual step | V preview | K skipped
    BEGIN OF ty_result,
      odp_context  TYPE c LENGTH 32,
      odp_name     TYPE c LENGTH 60,
      mode         TYPE c LENGTH 5,
      schedule     TYPE c LENGTH 8,
      segw_project TYPE c LENGTH 30,
      service_name TYPE c LENGTH 30,
      service_url  TYPE string,
      status       TYPE c LENGTH 1,
      message      TYPE string,
    END OF ty_result,
    ty_results TYPE STANDARD TABLE OF ty_result WITH DEFAULT KEY.

  "! Publish a single ODP provider as an OData service.
  "! @parameter iv_context  | ODP context (e.g. ABAP_CDS)
  "! @parameter iv_odp_name | ODP provider / CDS entity name
  "! @parameter is_names    | derived target object names
  "! @parameter is_options  | run options (package, transport, preview, recreate)
  "! @parameter rs_result   | publish outcome
  METHODS publish
    IMPORTING
      iv_context       TYPE clike
      iv_odp_name      TYPE clike
      is_names         TYPE ty_names
      is_options       TYPE ty_options
    RETURNING
      VALUE(rs_result) TYPE ty_result.

ENDINTERFACE.
