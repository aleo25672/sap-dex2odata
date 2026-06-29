" Activate DEX CDS views as ODP sources (Step 1).
" Before SEGW can redefine a CDS view as an ODP extraction source, the view must
" be activated in the ODP framework. This wraps RODPS_UTILS_DATASOURCE_ACT over a
" set of providers (keyed by their SQL view name) so it can be triggered from the
" report for the selected rows.
CLASS zcl_dex_odp_activator DEFINITION
  PUBLIC
  CREATE PUBLIC.

  PUBLIC SECTION.
    TYPES:
      BEGIN OF ty_result,
        entity_name   TYPE c LENGTH 60,
        sql_view_name TYPE c LENGTH 30,
        status        TYPE c LENGTH 1,   " S success | E error | K skipped
        message       TYPE string,
      END OF ty_result,
      ty_results TYPE STANDARD TABLE OF ty_result WITH DEFAULT KEY.

    " Activate the ODP sources for the given providers.
    METHODS activate
      IMPORTING
        it_providers      TYPE zcl_dex_odp_catalog=>ty_providers
      RETURNING
        VALUE(rt_results) TYPE ty_results.
ENDCLASS.


CLASS zcl_dex_odp_activator IMPLEMENTATION.

  METHOD activate.
    LOOP AT it_providers INTO DATA(ls_prov).
      " ODP datasource = classic SQL view name, else the entity name (view entities).
      DATA(lv_ds) = COND string(
        WHEN ls_prov-sql_view_name IS NOT INITIAL
        THEN ls_prov-sql_view_name
        ELSE ls_prov-entity_name ).

      DATA(ls_res) = VALUE ty_result(
        entity_name   = ls_prov-entity_name
        sql_view_name = lv_ds ).

      IF lv_ds IS INITIAL.
        ls_res-status  = 'K'.
        ls_res-message = 'Skipped: no datasource name'.
        APPEND ls_res TO rt_results.
        CONTINUE.
      ENDIF.

      DATA lt_ds  TYPE rodps_t_datasource.
      DATA lt_msg TYPE rodps_t_msg.
      CLEAR: lt_ds, lt_msg.
      APPEND VALUE #( datasource = lv_ds ) TO lt_ds.

      CALL FUNCTION 'RODPS_UTILS_DATASOURCE_ACT'
        EXPORTING
          it_datasource  = lt_ds
          i_no_transport = abap_true
          i_reset_cust   = abap_true
        IMPORTING
          et_msg         = lt_msg.

      IF sy-subrc = 0.
        ls_res-status  = 'S'.
        ls_res-message = |Activated ({ lines( lt_msg ) } message(s))|.
      ELSE.
        ls_res-status  = 'E'.
        ls_res-message = |Activation failed (subrc { sy-subrc }, { lines( lt_msg ) } message(s)) - check RODPS_REPL_TEST|.
      ENDIF.

      APPEND ls_res TO rt_results.
    ENDLOOP.
  ENDMETHOD.

ENDCLASS.
