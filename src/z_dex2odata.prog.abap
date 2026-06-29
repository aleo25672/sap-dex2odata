*&---------------------------------------------------------------------*
*& Report Z_DEX2ODATA
*&---------------------------------------------------------------------*
*& Discover extraction-enabled CDS views from the released catalog entity
*& I_DataExtractionEnabledView, show them in an ALV, and publish the
*& selected ones as OData services. Two CDS families are handled:
*&   * C_*DEX transactional (released + CDC) -> DELTA via ODP-OData
*&   * I_* master data       (released)      -> FULL reload, plain OData
*&                                              (nightly / weekly)
*&
*& Phase 1 (this list)        : inventory + readiness
*& Phase 2 ("Publish" button) : generate / register the OData service
*&
*& See ZCL_DEX_* classes for the building blocks. Publishing automation is
*& release-dependent and isolated in ZCL_DEX_SEGW_ODP_PUBLISHER (delta) and
*& ZCL_DEX_CDS_PUBLISHER (full).
*&---------------------------------------------------------------------*
REPORT z_dex2odata.

*----------------------------------------------------------------------*
* Selection screen
*----------------------------------------------------------------------*
SELECTION-SCREEN BEGIN OF BLOCK b_disc WITH FRAME TITLE TEXT-b01.
PARAMETERS p_ctx  TYPE c LENGTH 32 DEFAULT 'ABAP_CDS' OBLIGATORY.
PARAMETERS p_name TYPE c LENGTH 30.            " entity name pattern, * = wildcard
PARAMETERS p_trx  AS CHECKBOX DEFAULT 'X'.     " include C_*DEX transactional (delta)
PARAMETERS p_mds  AS CHECKBOX DEFAULT 'X'.     " include I_* master data (full)
PARAMETERS p_rdy  AS CHECKBOX.                 " hide already-published
SELECTION-SCREEN END OF BLOCK b_disc.

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
    METHODS on_added_function
      FOR EVENT added_function OF cl_salv_events_table
      IMPORTING e_salv_function.

  PRIVATE SECTION.
    DATA mt_prov TYPE zcl_dex_odp_catalog=>ty_providers.
    DATA mo_alv  TYPE REF TO cl_salv_table.

    METHODS build_grid.
    METHODS set_columns.
    METHODS set_col_text
      IMPORTING io_cols TYPE REF TO cl_salv_columns_table
                iv_col  TYPE lvc_fname
                iv_text TYPE string.
    METHODS publish_selected.
    METHODS show_results
      IMPORTING it_results TYPE zif_dex_publisher=>ty_results.
ENDCLASS.

CLASS lcl_app IMPLEMENTATION.

  METHOD run.
    DATA(lo_check)   = NEW zcl_dex_service_check( ).
    DATA(lo_catalog) = NEW zcl_dex_odp_catalog( p_ctx ).

    DATA(lv_sched) = COND string(
      WHEN p_swk = abap_true THEN zif_dex_publisher=>c_schedule-weekly
      ELSE zif_dex_publisher=>c_schedule-nightly ).

    mt_prov = lo_catalog->get_providers(
      iv_name_pattern       = p_name
      iv_incl_transactional = p_trx
      iv_incl_master        = p_mds
      iv_master_schedule    = lv_sched
      io_service_check      = lo_check ).

    IF p_rdy = abap_true.
      DELETE mt_prov WHERE has_service = abap_true.
    ENDIF.

    IF mt_prov IS INITIAL.
      MESSAGE 'No released, CDC-enabled CDS views found for the filter'(m01)
              TYPE 'S' DISPLAY LIKE 'W'.
      RETURN.
    ENDIF.

    build_grid( ).
    mo_alv->display( ).
  ENDMETHOD.

  METHOD build_grid.
    TRY.
        cl_salv_table=>factory(
          IMPORTING r_salv_table = mo_alv
          CHANGING  t_table      = mt_prov ).
      CATCH cx_salv_msg INTO DATA(lx).
        MESSAGE lx->get_text( ) TYPE 'E'.
    ENDTRY.

    " Standard toolbar + a custom "Publish selected" function.
    DATA(lo_funcs) = mo_alv->get_functions( ).
    lo_funcs->set_default( abap_true ).
    TRY.
        lo_funcs->add_function(
          name     = 'PUBLISH'
          icon     = space
          text     = 'Publish selected'
          tooltip  = 'Publish selected providers as ODP-OData services'
          position = if_salv_c_function_position=>right_of_salv_functions ).
      CATCH cx_salv_existing cx_salv_wrong_call.
        " non-fatal: button just won't be added
    ENDTRY.

    " Multiple-row selection (leading checkbox column).
    mo_alv->get_selections( )->set_selection_mode(
      if_salv_c_selection_mode=>multiple ).

    SET HANDLER me->on_added_function FOR mo_alv->get_event( ).

    mo_alv->get_display_settings( )->set_list_header(
      |DEX CDS views -> ODP-OData ({ p_ctx })| ).

    set_columns( ).
  ENDMETHOD.

  METHOD set_columns.
    DATA(lo_cols) = mo_alv->get_columns( ).
    lo_cols->set_optimize( abap_true ).

    set_col_text( io_cols = lo_cols iv_col = 'ENTITY_NAME'     iv_text = 'CDS Entity' ).
    set_col_text( io_cols = lo_cols iv_col = 'DESCRIPTION'     iv_text = 'Description' ).
    set_col_text( io_cols = lo_cols iv_col = 'FAMILY'          iv_text = 'Family' ).
    set_col_text( io_cols = lo_cols iv_col = 'EXTRACTION_MODE' iv_text = 'Mode' ).
    set_col_text( io_cols = lo_cols iv_col = 'SCHEDULE'        iv_text = 'Schedule' ).
    set_col_text( io_cols = lo_cols iv_col = 'IS_RELEASED'     iv_text = 'Released' ).
    set_col_text( io_cols = lo_cols iv_col = 'IS_CDC_ENABLED'  iv_text = 'CDC/Delta' ).
    set_col_text( io_cols = lo_cols iv_col = 'ODP_CONTEXT'     iv_text = 'ODP Context' ).
    set_col_text( io_cols = lo_cols iv_col = 'HAS_SERVICE'    iv_text = 'Published' ).
    set_col_text( io_cols = lo_cols iv_col = 'SERVICE_NAME'   iv_text = 'Service' ).
    set_col_text( io_cols = lo_cols iv_col = 'READINESS'      iv_text = 'Readiness' ).
    set_col_text( io_cols = lo_cols iv_col = 'REASON'         iv_text = 'Reason' ).
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

  METHOD on_added_function.
    CASE e_salv_function.
      WHEN 'PUBLISH'.
        publish_selected( ).
    ENDCASE.
  ENDMETHOD.

  METHOD publish_selected.
    DATA(lt_rows) = mo_alv->get_selections( )->get_selected_rows( ).
    IF lt_rows IS INITIAL.
      MESSAGE 'Select at least one provider first'(m02)
              TYPE 'S' DISPLAY LIKE 'W'.
      RETURN.
    ENDIF.

    DATA(lo_namer) = NEW zcl_dex_namer( ).
    " One publisher per strategy: delta -> ODP, full -> plain CDS OData.
    DATA(lo_delta) = CAST zif_dex_publisher(
                       NEW zcl_dex_segw_odp_publisher( lo_namer ) ).
    DATA(lo_full)  = CAST zif_dex_publisher(
                       NEW zcl_dex_cds_publisher( lo_namer ) ).

    DATA lt_results TYPE zif_dex_publisher=>ty_results.
    LOOP AT lt_rows INTO DATA(lv_row).
      READ TABLE mt_prov INDEX lv_row INTO DATA(ls_prov).
      IF sy-subrc <> 0.
        CONTINUE.
      ENDIF.

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

    show_results( lt_results ).
  ENDMETHOD.

  METHOD show_results.
    DATA lt_res TYPE zif_dex_publisher=>ty_results.
    lt_res = it_results.

    TRY.
        cl_salv_table=>factory(
          IMPORTING r_salv_table = DATA(lo_res)
          CHANGING  t_table      = lt_res ).
        lo_res->get_columns( )->set_optimize( abap_true ).
        lo_res->get_display_settings( )->set_list_header(
          |Publish results ({ COND string( WHEN p_prev = abap_true THEN `preview` ELSE `live` ) })| ).
        lo_res->set_screen_popup(
          start_column = 5
          end_column   = 130
          start_line   = 2
          end_line     = 25 ).
        lo_res->display( ).
      CATCH cx_salv_msg INTO DATA(lx).
        MESSAGE lx->get_text( ) TYPE 'I'.
    ENDTRY.
  ENDMETHOD.

ENDCLASS.

*----------------------------------------------------------------------*
START-OF-SELECTION.
  DATA(go_app) = NEW lcl_app( ).
  go_app->run( ).
