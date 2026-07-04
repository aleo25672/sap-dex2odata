*&---------------------------------------------------------------------*
*& Report Z_ODP_ACTIVATE_ALL_DEX
*&---------------------------------------------------------------------*
*& Bulk-activate all classic ODP-CDS extraction sources listed in
*& RSODPABAPCDSVIEW (Step 1). Standalone helper - the same activation is
*& also available per-selection in Z_DEX2ODATA (Action: Activate ODP).
*&
*& Note: RSODPABAPCDSVIEW only holds classic CDS views (with a SQL view
*& name); CDS view entities are not listed here and are not activated.
*&---------------------------------------------------------------------*
REPORT z_odp_activate_all_dex.

DATA: lt_ds  TYPE rodps_t_datasource,
      ls_ds  LIKE LINE OF lt_ds,
      lt_msg TYPE rodps_t_msg.

SELECT sqlviewname, ddlname
  FROM rsodpabapcdsview
  INTO TABLE @DATA(lt_views).

DATA(lv_count) = lines( lt_views ).
WRITE: / '=== Activating', lv_count, 'ODP sources ==='.

LOOP AT lt_views INTO DATA(ls_v).
  CLEAR: lt_ds, lt_msg.
  ls_ds-datasource = ls_v-sqlviewname.
  APPEND ls_ds TO lt_ds.

  CALL FUNCTION 'RODPS_UTILS_DATASOURCE_ACT'
    EXPORTING
      it_datasource  = lt_ds
      i_no_transport = 'X'
      i_reset_cust   = 'X'
    IMPORTING
      et_msg         = lt_msg.

  DATA(lv_flag) = COND string( WHEN sy-subrc = 0 THEN '✓' ELSE '✗' ).
  WRITE: / lv_flag, ls_v-sqlviewname, '(', ls_v-ddlname, ')'.
ENDLOOP.
