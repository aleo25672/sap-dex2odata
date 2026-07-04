*&---------------------------------------------------------------------*
*& Report Z_DEX2ODATA
*&---------------------------------------------------------------------*
*& Discover extraction-enabled CDS views from IXTRCTNENBLDVW, classify
*& them (C_*DEX delta / I_* master-data full), and either display them or
*& act on the filtered set:
*&   * Activate ODP   - register the views as ODP sources (Step 1)
*&   * Publish        - generate / register the OData service recipe
*&
*& The action runs on ALL rows matching the selection-screen filter, so
*& narrow with the CDS entity pattern to target a subset.
*&---------------------------------------------------------------------*
REPORT z_dex2odata.

*----------------------------------------------------------------------*
* Selection screen
*----------------------------------------------------------------------*
SELECTION-SCREEN BEGIN OF BLOCK b_disc WITH FRAME TITLE TEXT-b01.
PARAMETERS p_ctx  TYPE c LENGTH 32 DEFAULT 'ABAP_CDS' OBLIGATORY.
PARAMETERS p_name TYPE c LENGTH 30 LOWER CASE. " entity pattern (case-sensitive), * = wildcard
PARAMETERS p_trx  AS CHECKBOX DEFAULT 'X'.     " include C_*DEX transactional (delta)
PARAMETERS p_mds  AS CHECKBOX DEFAULT 'X'.     " include I_* master data (full)
PARAMETERS p_rdy  AS CHECKBOX.                 " hide already-published
SELECTION-SCREEN END OF BLOCK b_disc.

SELECTION-SCREEN BEGIN OF BLOCK b_act WITH FRAME TITLE TEXT-b04.
PARAMETERS p_disp RADIOBUTTON GROUP act DEFAULT 'X'.  " display list only
PARAMETERS p_act  RADIOBUTTON GROUP act.              " activate ODP sources (Step 1)
PARAMETERS p_pub  RADIOBUTTON GROUP act.              " publish OData service
SELECTION-SCREEN END OF BLOCK b_act.

SELECTION-SCREEN BEGIN OF BLOCK b_sch WITH FRAME TITLE TEXT-b03.
PARAMETERS p_sngt RADIOBUTTON GROUP sch DEFAULT 'X'.  " master-data full reload: nightly
PARAMETERS p_swk  RADIOBUTTON GROUP sch.              " master-data full reload: weekly
SELECTION-SCREEN END OF BLOCK b_sch.

SELECTION-SCREEN BEGIN OF BLOCK b_pub WITH FRAME TITLE TEXT-b02.
PARAMETERS p_pkg   TYPE devclass DEFAULT '$TMP' OBLIGATORY.
PARAMETERS p_trans TYPE trkorr.
PARAMETERS p_prev  AS CHECKBOX DEFAULT 'X'.    " preview / dry-run (safe default)
PARAMETERS p_recr  AS CHECKBOX.                " recreate if already exists
SELECTION-SCREEN END OF BLOCK b_pub.

*----------------------------------------------------------------------*
* Application (local) class
*----------------------------------------------------------------------*
CLASS lcl_app DEFINITION CREATE PUBLIC.
  PUBLIC SECTION.
    METHODS run.

  PRIVATE SECTION.
    DATA mt_prov TYPE zcl_dex_odp_catalog=>ty_providers.

    METHODS load_providers.
    METHODS display_grid.
    METHODS activate_all.
    METHODS publish_all.
    METHODS set_columns
      IMPORTING io_cols TYPE REF TO cl_salv_columns_table.
    METHODS set_col_text
      IMPORTING io_cols TYPE REF TO cl_salv_columns_table
                iv_col  TYPE lvc_fname
                iv_text TYPE string.
ENDCLASS.

CLASS lcl_app IMPLEMENTATION.

  METHOD run.
    load_providers( ).

    IF mt_prov IS INITIAL.
      MESSAGE 'No released, CDC-enabled CDS views found for the filter'(m01)
              TYPE 'S' DISPLAY LIKE 'W'.
      RETURN.
    ENDIF.

    CASE abap_true.
      WHEN p_act.
        activate_all( ).
      WHEN p_pub.
        publish_all( ).
      WHEN OTHERS.
        display_grid( ).
    ENDCASE.
  ENDMETHOD.

  METHOD load_providers.
    DATA(lv_sched) = COND string(
      WHEN p_swk = abap_true THEN zif_dex_publisher=>c_schedule-weekly
      ELSE zif_dex_publisher=>c_schedule-nightly ).

    mt_prov = NEW zcl_dex_odp_catalog( p_ctx )->get_providers(
      iv_name_pattern       = p_name
      iv_incl_transactional = p_trx
      iv_incl_master        = p_mds
      iv_master_schedule    = lv_sched
      io_service_check      = NEW zcl_dex_service_check( ) ).

    IF p_rdy = abap_true.
      DELETE mt_prov WHERE has_service = abap_true.
    ENDIF.
  ENDMETHOD.

  METHOD display_grid.
    DATA lo_alv TYPE REF TO cl_salv_table.
    TRY.
        cl_salv_table=>factory(
          IMPORTING r_salv_table = lo_alv
          CHANGING  t_table      = mt_prov ).
      CATCH cx_salv_msg INTO DATA(lx).
        MESSAGE lx->get_text( ) TYPE 'E'.
    ENDTRY.

    lo_alv->get_functions( )->set_default( abap_true ).
    set_columns( lo_alv->get_columns( ) ).
    lo_alv->get_display_settings( )->set_list_header(
      |DEX CDS views ({ p_ctx }) - { lines( mt_prov ) } rows| ).
    lo_alv->display( ).
  ENDMETHOD.

  METHOD activate_all.
    DATA(lt_res) = NEW zcl_dex_odp_activator( )->activate( mt_prov ).
    TRY.
        cl_salv_table=>factory(
          IMPORTING r_salv_table = DATA(lo_res)
          CHANGING  t_table      = lt_res ).
        lo_res->get_functions( )->set_default( abap_true ).
        DATA(lo_cols) = lo_res->get_columns( ).
        lo_cols->set_optimize( abap_true ).
        set_col_text( io_cols = lo_cols iv_col = 'ENTITY_NAME'   iv_text = 'CDS Entity' ).
        set_col_text( io_cols = lo_cols iv_col = 'SQL_VIEW_NAME' iv_text = 'ODP Source' ).
        set_col_text( io_cols = lo_cols iv_col = 'STATUS'        iv_text = 'Status' ).
        set_col_text( io_cols = lo_cols iv_col = 'MESSAGE'       iv_text = 'Message' ).
        lo_res->get_display_settings( )->set_list_header(
          |ODP activation results - { lines( lt_res ) } source(s)| ).
        lo_res->display( ).
      CATCH cx_salv_msg INTO DATA(lx).
        MESSAGE lx->get_text( ) TYPE 'I'.
    ENDTRY.
  ENDMETHOD.

  METHOD publish_all.
    DATA(lo_namer) = NEW zcl_dex_namer( ).
    " One publisher per strategy: delta -> ODP, full -> plain CDS OData.
    DATA(lo_delta) = CAST zif_dex_publisher(
                       NEW zcl_dex_segw_odp_publisher( lo_namer ) ).
    DATA(lo_full)  = CAST zif_dex_publisher(
                       NEW zcl_dex_cds_publisher( lo_namer ) ).

    DATA lt_results TYPE zif_dex_publisher=>ty_results.
    LOOP AT mt_prov INTO DATA(ls_prov).
      DATA(ls_names) = lo_namer->derive( ls_prov-entity_name ).
      DATA(ls_opt)   = VALUE zif_dex_publisher=>ty_options(
        package   = p_pkg
        transport = p_trans
        preview   = p_prev
        recreate  = p_recr
        mode      = ls_prov-extraction_mode
        schedule  = ls_prov-schedule ).

      DATA(lo_pub) = COND #(
        WHEN ls_prov-extraction_mode = zif_dex_publisher=>c_mode-delta
        THEN lo_delta ELSE lo_full ).

      APPEND lo_pub->publish(
        iv_context  = ls_prov-odp_context
        iv_odp_name = ls_prov-entity_name
        is_names    = ls_names
        is_options  = ls_opt ) TO lt_results.
    ENDLOOP.

    TRY.
        cl_salv_table=>factory(
          IMPORTING r_salv_table = DATA(lo_res)
          CHANGING  t_table      = lt_results ).
        lo_res->get_functions( )->set_default( abap_true ).
        DATA(lo_cols) = lo_res->get_columns( ).
        lo_cols->set_optimize( abap_true ).
        set_col_text( io_cols = lo_cols iv_col = 'ODP_NAME'     iv_text = 'CDS Entity' ).
        set_col_text( io_cols = lo_cols iv_col = 'MODE'         iv_text = 'Mode' ).
        set_col_text( io_cols = lo_cols iv_col = 'SCHEDULE'     iv_text = 'Schedule' ).
        set_col_text( io_cols = lo_cols iv_col = 'SEGW_PROJECT' iv_text = 'SEGW Project' ).
        set_col_text( io_cols = lo_cols iv_col = 'SERVICE_NAME' iv_text = 'Service' ).
        set_col_text( io_cols = lo_cols iv_col = 'SERVICE_URL'  iv_text = 'Service URL' ).
        set_col_text( io_cols = lo_cols iv_col = 'STATUS'       iv_text = 'Status' ).
        set_col_text( io_cols = lo_cols iv_col = 'MESSAGE'      iv_text = 'Message / recipe' ).
        set_col_text( io_cols = lo_cols iv_col = 'ODP_CONTEXT'  iv_text = 'Context' ).
        lo_res->get_display_settings( )->set_list_header(
          |Publish results ({ COND string( WHEN p_prev = abap_true THEN `preview` ELSE `live` ) })| ).
        lo_res->display( ).
      CATCH cx_salv_msg INTO DATA(lx).
        MESSAGE lx->get_text( ) TYPE 'I'.
    ENDTRY.
  ENDMETHOD.

  METHOD set_columns.
    io_cols->set_optimize( abap_true ).
    set_col_text( io_cols = io_cols iv_col = 'ENTITY_NAME'     iv_text = 'CDS Entity' ).
    set_col_text( io_cols = io_cols iv_col = 'DESCRIPTION'     iv_text = 'Description' ).
    set_col_text( io_cols = io_cols iv_col = 'SQL_VIEW_NAME'   iv_text = 'SQL View' ).
    set_col_text( io_cols = io_cols iv_col = 'FAMILY'          iv_text = 'Family' ).
    set_col_text( io_cols = io_cols iv_col = 'EXTRACTION_MODE' iv_text = 'Mode' ).
    set_col_text( io_cols = io_cols iv_col = 'SCHEDULE'        iv_text = 'Schedule' ).
    set_col_text( io_cols = io_cols iv_col = 'IS_RELEASED'     iv_text = 'Released' ).
    set_col_text( io_cols = io_cols iv_col = 'IS_CDC_ENABLED'  iv_text = 'CDC/Delta' ).
    set_col_text( io_cols = io_cols iv_col = 'ODP_SOURCE'      iv_text = 'ODP Src $F' ).
    set_col_text( io_cols = io_cols iv_col = 'FACTS_SET'       iv_text = 'Facts set' ).
    set_col_text( io_cols = io_cols iv_col = 'DELTA_SET'       iv_text = 'Delta set' ).
    set_col_text( io_cols = io_cols iv_col = 'ODP_CONTEXT'     iv_text = 'ODP Context' ).
    set_col_text( io_cols = io_cols iv_col = 'HAS_SERVICE'     iv_text = 'Published' ).
    set_col_text( io_cols = io_cols iv_col = 'SERVICE_NAME'    iv_text = 'Service' ).
    set_col_text( io_cols = io_cols iv_col = 'READINESS'       iv_text = 'Readiness' ).
    set_col_text( io_cols = io_cols iv_col = 'REASON'          iv_text = 'Reason' ).
  ENDMETHOD.

  METHOD set_col_text.
    TRY.
        DATA(lo_col) = io_cols->get_column( iv_col ).
        lo_col->set_short_text(  CONV scrtext_s( iv_text ) ).
        lo_col->set_medium_text( CONV scrtext_m( iv_text ) ).
        lo_col->set_long_text(   CONV scrtext_l( iv_text ) ).
      CATCH cx_salv_not_found.
        " unknown column: ignore
    ENDTRY.
  ENDMETHOD.

ENDCLASS.

*----------------------------------------------------------------------*
START-OF-SELECTION.
  NEW lcl_app( )->run( ).
