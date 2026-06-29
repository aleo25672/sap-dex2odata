" <p class="shorttext synchronized">Discover extraction-enabled CDS views (2 families)</p>
" Reads the released CDS view I_DataExtractionEnabledView (SQL name IXTRCTNENBLDVW)
" and classifies the rows into two families with different extraction strategies:
"
" * C_*DEX transactional, released + CDC enabled -> DELTA (ODP-OData)
" * I_* master data, released (CDC ignored)       -> FULL  (plain OData, scheduled)
"
" Rows matching neither family are skipped.
CLASS zcl_dex_odp_catalog DEFINITION
  PUBLIC
  CREATE PUBLIC.

  PUBLIC SECTION.
    " One candidate provider (one CDS view) with its assigned strategy
    TYPES:
      BEGIN OF ty_provider,
        entity_name     TYPE c LENGTH 60,
        description     TYPE c LENGTH 60,
        sql_view_name   TYPE c LENGTH 30,   " from RSODPABAPCDSVIEW, used in ODP/entity-set names
        family          TYPE c LENGTH 13,   " 'TRANSACTIONAL' / 'MASTER DATA'
        is_released     TYPE abap_bool,
        is_cdc_enabled  TYPE abap_bool,
        extraction_mode TYPE c LENGTH 5,    " see ZIF_DEX_PUBLISHER=>c_mode
        schedule        TYPE c LENGTH 8,    " see ZIF_DEX_PUBLISHER=>c_schedule
        odp_source      TYPE c LENGTH 35,   " <SQLVIEW>$F  -> type into SEGW ODP redefine
        facts_set       TYPE c LENGTH 60,   " FactsOf<SQLVIEW>      (initial/full entity set)
        delta_set       TYPE c LENGTH 60,   " DeltaLinksOf<SQLVIEW> (delta/CDC entity set)
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

    " @parameter iv_context | ODP context the providers belong to (default ABAP_CDS)
    METHODS constructor
      IMPORTING iv_context TYPE clike DEFAULT 'ABAP_CDS'.

    " Read released extraction-enabled CDS views and classify them.
    " @parameter iv_name_pattern       | optional entity filter; '*' wildcards allowed
    " @parameter iv_incl_transactional | include C_*DEX delta family
    " @parameter iv_incl_master        | include I_* master-data (full) family
    " @parameter iv_master_schedule    | schedule assigned to the master-data family
    " @parameter io_service_check      | optional, marks already-published providers
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

    " Released, extraction-enabled CDS views from IXTRCTNENBLDVW. Columns:
    "   DATAEXTRACTIONVIEWNAME / ...DESCRIPTION / ISSAPRELEASEDVIEW /
    "   DELTACHGDATACAPTUREISSUPPORTED
    SELECT dataextractionviewname,
           dataextractionviewdescription,
           issapreleasedview,
           deltachgdatacaptureissupported
      FROM ixtrctnenbldvw
      WHERE issapreleasedview = @abap_true
        AND dataextractionviewname LIKE @lv_pattern
      ORDER BY dataextractionviewname
      INTO TABLE @DATA(lt_views).

    " SQL view name per view, from RSODPABAPCDSVIEW (DDLNAME -> SQLVIEWNAME),
    " matched case-INSENSITIVELY: IXTRCTNENBLDVW keeps the raw mixed-case view
    " name while DDLNAME is stored upper case, so a direct join never matches.
    SELECT ddlname, sqlviewname
      FROM rsodpabapcdsview
      INTO TABLE @DATA(lt_map).

    TYPES: BEGIN OF ty_sqlview,
             ddl_up  TYPE string,
             sqlview TYPE c LENGTH 30,
           END OF ty_sqlview.
    DATA lt_sqlview TYPE SORTED TABLE OF ty_sqlview WITH NON-UNIQUE KEY ddl_up.
    LOOP AT lt_map INTO DATA(ls_map).
      INSERT VALUE #( ddl_up  = to_upper( ls_map-ddlname )
                      sqlview = ls_map-sqlviewname ) INTO TABLE lt_sqlview.
    ENDLOOP.

    LOOP AT lt_views INTO DATA(ls_view).
      DATA(ls_prov) = VALUE ty_provider(
        entity_name    = ls_view-dataextractionviewname
        description    = ls_view-dataextractionviewdescription
        is_released    = ls_view-issapreleasedview
        is_cdc_enabled = ls_view-deltachgdatacaptureissupported
        odp_context    = mv_context
        readiness      = 'Ready' ).

      " Resolve SQL view name + derive the SEGW/ODP names.
      READ TABLE lt_sqlview INTO DATA(ls_sv)
           WITH KEY ddl_up = to_upper( ls_view-dataextractionviewname ).
      IF sy-subrc = 0 AND ls_sv-sqlview IS NOT INITIAL.
        ls_prov-sql_view_name = ls_sv-sqlview.
        ls_prov-odp_source    = |{ ls_sv-sqlview }$F|.
        ls_prov-facts_set     = |FactsOf{ ls_sv-sqlview }|.
        ls_prov-delta_set     = |DeltaLinksOf{ ls_sv-sqlview }|.
      ELSE.
        " No classic SQL view name: typically a CDS view entity, or the ODP
        " source is not registered yet. Flag it so the blank is explained.
        ls_prov-reason = 'No SQL view in RSODPABAPCDSVIEW (view entity or ODP source not registered)'.
      ENDIF.

      " ---- classify into a family + strategy -----------------------------
      IF iv_incl_transactional = abap_true
         AND ls_view-dataextractionviewname CP 'C_*DEX'
         AND ls_view-deltachgdatacaptureissupported = abap_true.
        ls_prov-family          = c_family_transactional.
        ls_prov-extraction_mode = zif_dex_publisher=>c_mode-delta.
        ls_prov-schedule        = zif_dex_publisher=>c_schedule-none.

      ELSEIF iv_incl_master = abap_true
             AND ls_view-dataextractionviewname CP 'I_*'.
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
