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
        service_name    TYPE c LENGTH 40,
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
                iv_service_name  TYPE clike
      CHANGING  cs_provider      TYPE ty_provider.
ENDCLASS.


CLASS zcl_dex_odp_catalog IMPLEMENTATION.

  METHOD constructor.
    mv_context = iv_context.
    TRANSLATE mv_context TO UPPER CASE.
  ENDMETHOD.

  METHOD get_providers.
    " Optional name filter (case-sensitive):
    "   empty        -> all
    "   contains '*' -> '*' acts as the wildcard (e.g. C_Purchase*DEX)
    "   plain text   -> contains search (e.g. PurchaseOrder -> %PurchaseOrder%)
    DATA(lv_pattern) = condense( CONV string( iv_name_pattern ) ).
    IF lv_pattern IS INITIAL.
      lv_pattern = '%'.
    ELSEIF lv_pattern CA '*'.
      REPLACE ALL OCCURRENCES OF '*' IN lv_pattern WITH '%'.
    ELSE.
      lv_pattern = |%{ lv_pattern }%|.
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

    " ODP technical name per view, from RSODPABAPCDSVIEW. A view is either:
    "   classic      -> name is in SQLVIEWNAME     (e.g. CMMPRITMDEX)
    "   view entity  -> SQLVIEWNAME blank, name is in STRUCTOBJNAME
    "                   (= @Analytics.technicalName, e.g. CMMPURORDDEX)
    " Matched case-INSENSITIVELY (DDLNAME is stored upper case).
    SELECT ddlname, sqlviewname, structobjname
      FROM rsodpabapcdsview
      INTO TABLE @DATA(lt_map).

    TYPES: BEGIN OF ty_sqlview,
             ddl_up TYPE string,
             name   TYPE c LENGTH 30,   " effective ODP technical name
           END OF ty_sqlview.
    DATA lt_sqlview TYPE SORTED TABLE OF ty_sqlview WITH NON-UNIQUE KEY ddl_up.
    LOOP AT lt_map INTO DATA(ls_map).
      INSERT VALUE #( ddl_up = to_upper( ls_map-ddlname )
                      name   = COND #( WHEN ls_map-sqlviewname IS NOT INITIAL
                                       THEN ls_map-sqlviewname
                                       ELSE ls_map-structobjname ) )
             INTO TABLE lt_sqlview.
    ENDLOOP.

    " Fallback source: the @Analytics.technicalName header annotation, stored in
    " DDHEADANNO (STRUCOBJN = entity, NAME = annotation, VALUE = value). This is
    " where a view entity's ODP technical name (e.g. CMMPURORDDEX) lives when the
    " view is not in RSODPABAPCDSVIEW.
    SELECT strucobjn, value AS techname
      FROM ddheadanno
      WHERE upper( name ) = 'ANALYTICS.TECHNICALNAME'
      INTO TABLE @DATA(lt_anno).

    TYPES: BEGIN OF ty_tech,
             key_up   TYPE string,
             techname TYPE c LENGTH 30,
           END OF ty_tech.
    DATA lt_tech TYPE SORTED TABLE OF ty_tech WITH NON-UNIQUE KEY key_up.
    LOOP AT lt_anno INTO DATA(ls_anno).
      " DDHEADANNO stores the value as written in source, incl. the surrounding
      " quotes ('CMMPURORDDEX') - strip them so $F attaches to the name.
      DATA(lv_tech) = ls_anno-techname.
      REPLACE ALL OCCURRENCES OF `'` IN lv_tech WITH ``.
      CONDENSE lv_tech.
      INSERT VALUE #( key_up   = to_upper( ls_anno-strucobjn )
                      techname = lv_tech ) INTO TABLE lt_tech.
    ENDLOOP.

    DATA(lo_namer) = NEW zcl_dex_namer( ).

    LOOP AT lt_views INTO DATA(ls_view).
      DATA(ls_prov) = VALUE ty_provider(
        entity_name    = ls_view-dataextractionviewname
        description    = ls_view-dataextractionviewdescription
        is_released    = ls_view-issapreleasedview
        is_cdc_enabled = ls_view-deltachgdatacaptureissupported
        odp_context    = mv_context
        readiness      = 'Ready' ).

      " Resolve the ODP technical name: RSODPABAPCDSVIEW first (classic + view
      " entities registered there), else @Analytics.technicalName (DDHEADANNO).
      DATA lv_name TYPE c LENGTH 30.
      CLEAR lv_name.
      READ TABLE lt_sqlview INTO DATA(ls_sv)
           WITH KEY ddl_up = to_upper( ls_view-dataextractionviewname ).
      IF sy-subrc = 0.
        lv_name = ls_sv-name.
      ENDIF.
      IF lv_name IS INITIAL.
        READ TABLE lt_tech INTO DATA(ls_tech)
             WITH KEY key_up = to_upper( ls_view-dataextractionviewname ).
        IF sy-subrc = 0.
          lv_name = ls_tech-techname.
        ENDIF.
      ENDIF.

      IF lv_name IS NOT INITIAL.
        ls_prov-sql_view_name = lv_name.
        ls_prov-odp_source    = |{ lv_name }$F|.
        ls_prov-facts_set     = |FactsOf{ lv_name }|.
        ls_prov-delta_set     = |DeltaLinksOf{ lv_name }|.
      ELSE.
        ls_prov-reason = 'No ODP technical name (RSODPABAPCDSVIEW / @Analytics.technicalName)'.
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
        DATA(lv_srv) = lo_namer->derive( ls_prov-entity_name )-service_name.
        enrich_service( EXPORTING io_service_check = io_service_check
                                  iv_service_name  = lv_srv
                        CHANGING  cs_provider      = ls_prov ).
      ENDIF.

      APPEND ls_prov TO rt_providers.
    ENDLOOP.
  ENDMETHOD.

  METHOD enrich_service.
    DATA(ls_svc) = io_service_check->check( iv_service_name ).
    IF ls_svc-exists = abap_true.
      cs_provider-has_service  = abap_true.
      cs_provider-service_name = ls_svc-service_name.
      cs_provider-readiness    = 'Published'.
    ENDIF.
  ENDMETHOD.

ENDCLASS.
