"! <p class="shorttext synchronized">Discover extraction-enabled CDS views (2 families)</p>
"! Reads the released CDS view I_DataExtractionEnabledView (SQL name IXTRCTNENBLDVW)
"! and classifies the rows into two families with different extraction strategies:
"!
"! * C_*DEX transactional, released + CDC enabled -> DELTA (ODP-OData)
"! * I_* master data, released (CDC ignored)       -> FULL  (plain OData, scheduled)
"!
"! Rows matching neither family are skipped.
CLASS zcl_dex_odp_catalog DEFINITION
  PUBLIC
  CREATE PUBLIC.

  PUBLIC SECTION.
    "! One candidate provider (one CDS view) with its assigned strategy
    TYPES:
      BEGIN OF ty_provider,
        entity_name     TYPE c LENGTH 60,
        family          TYPE c LENGTH 13,   " 'TRANSACTIONAL' / 'MASTER DATA'
        is_released     TYPE abap_bool,
        is_cdc_enabled  TYPE abap_bool,
        extraction_mode TYPE c LENGTH 5,    " see ZIF_DEX_PUBLISHER=>c_mode
        schedule        TYPE c LENGTH 8,    " see ZIF_DEX_PUBLISHER=>c_schedule
        odp_context     TYPE c LENGTH 32,
        has_service     TYPE abap_bool,
        service_name    TYPE c LENGTH 30,
        readiness       TYPE c LENGTH 12,
        reason          TYPE string,
      END OF ty_provider,
      ty_providers TYPE STANDARD TABLE OF ty_provider WITH DEFAULT KEY.

    CONSTANTS:
      c_family_transactional TYPE c LENGTH 13 VALUE 'TRANSACTIONAL',
      c_family_master        TYPE c LENGTH 13 VALUE 'MASTER DATA'.

    "! @parameter iv_context | ODP context the providers belong to (default ABAP_CDS)
    METHODS constructor
      IMPORTING iv_context TYPE clike DEFAULT 'ABAP_CDS'.

    "! Read released extraction-enabled CDS views and classify them.
    "! @parameter iv_name_pattern       | optional entity filter; '*' wildcards allowed
    "! @parameter iv_incl_transactional | include C_*DEX delta family
    "! @parameter iv_incl_master        | include I_* master-data (full) family
    "! @parameter iv_master_schedule    | schedule assigned to the master-data family
    "! @parameter io_service_check      | optional, marks already-published providers
    METHODS get_providers
      IMPORTING
        iv_name_pattern       TYPE clike   OPTIONAL
        iv_incl_transactional TYPE abap_bool DEFAULT abap_true
        iv_incl_master        TYPE abap_bool DEFAULT abap_true
        iv_master_schedule    TYPE clike   DEFAULT 'NIGHTLY'
        io_service_check      TYPE REF TO zcl_dex_service_check OPTIONAL
      RETURNING
        VALUE(rt_providers)   TYPE ty_providers.

  PRIVATE SECTION.
    DATA mv_context TYPE c LENGTH 32.

    METHODS enrich_service
      IMPORTING io_service_check TYPE REF TO zcl_dex_service_check
      CHANGING  cs_provider      TYPE ty_provider.
ENDCLASS.


CLASS zcl_dex_odp_catalog IMPLEMENTATION.

  METHOD constructor.
    mv_context = iv_context.
    TRANSLATE mv_context TO UPPER CASE.
  ENDMETHOD.

  METHOD get_providers.
    " Optional name filter; treat '*' as the SQL wildcard '%'.
    DATA(lv_pattern) = |{ iv_name_pattern }|.
    IF lv_pattern IS INITIAL.
      lv_pattern = '%'.
    ELSE.
      REPLACE ALL OCCURRENCES OF '*' IN lv_pattern WITH '%'.
    ENDIF.

    " Released, extraction-enabled CDS views from the extraction-enabled-views
    " catalog. We read the SQL view IXTRCTNENBLDVW directly because its column
    " names (ENTITYNAME / IS_RELEASED / IS_CDC_ENABLED) are guaranteed; the
    " released CDS entity I_DataExtractionEnabledView exposes the same data but
    " under CamelCase element names that vary by release.
    SELECT entityname,
           is_released,
           is_cdc_enabled
      FROM ixtrctnenbldvw
      WHERE is_released = @abap_true
        AND entityname LIKE @lv_pattern
      ORDER BY entityname
      INTO TABLE @DATA(lt_views).

    LOOP AT lt_views INTO DATA(ls_view).
      DATA(ls_prov) = VALUE ty_provider(
        entity_name    = ls_view-entityname
        is_released    = ls_view-is_released
        is_cdc_enabled = ls_view-is_cdc_enabled
        odp_context    = mv_context
        readiness      = 'Ready' ).

      " ---- classify into a family + strategy -----------------------------
      IF iv_incl_transactional = abap_true
         AND ls_view-entityname CP 'C_*DEX'
         AND ls_view-is_cdc_enabled = abap_true.
        ls_prov-family          = c_family_transactional.
        ls_prov-extraction_mode = zif_dex_publisher=>c_mode-delta.
        ls_prov-schedule        = zif_dex_publisher=>c_schedule-none.

      ELSEIF iv_incl_master = abap_true
             AND ls_view-entityname CP 'I_*'.
        ls_prov-family          = c_family_master.
        ls_prov-extraction_mode = zif_dex_publisher=>c_mode-full.
        ls_prov-schedule        = iv_master_schedule.

      ELSE.
        CONTINUE.   " not one of the two target families
      ENDIF.

      IF io_service_check IS BOUND.
        enrich_service( EXPORTING io_service_check = io_service_check
                        CHANGING  cs_provider      = ls_prov ).
      ENDIF.

      APPEND ls_prov TO rt_providers.
    ENDLOOP.
  ENDMETHOD.

  METHOD enrich_service.
    DATA(ls_svc) = io_service_check->check( cs_provider-entity_name ).
    IF ls_svc-determinable = abap_true AND ls_svc-exists = abap_true.
      cs_provider-has_service  = abap_true.
      cs_provider-service_name = ls_svc-service_name.
      cs_provider-readiness    = 'Published'.
    ENDIF.
  ENDMETHOD.

ENDCLASS.
