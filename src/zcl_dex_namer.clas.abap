" <p class="shorttext synchronized">Derive collision-free SEGW/service names</p>
" Turns a (possibly long, mixed-case) ODP/CDS entity name into valid, &lt;=30 char,
" unique repository object names. Stateful: remembers names already issued in this
" run so two long entities that truncate to the same stem get distinct names.
CLASS zcl_dex_namer DEFINITION
  PUBLIC
  CREATE PUBLIC.

  PUBLIC SECTION.
    CONSTANTS c_prefix TYPE string VALUE 'Z_'.
    CONSTANTS c_suffix TYPE string VALUE '_SRV'.

    " Derive target names for one ODP provider / CDS entity.
    METHODS derive
      IMPORTING
        iv_odp_name     TYPE clike
      RETURNING
        VALUE(rs_names) TYPE zif_dex_publisher=>ty_names.

  PRIVATE SECTION.
    DATA mt_used TYPE SORTED TABLE OF string WITH UNIQUE KEY table_line.

    METHODS sanitize
      IMPORTING iv_in         TYPE clike
      RETURNING VALUE(rv_out) TYPE string.

    METHODS make_unique
      IMPORTING iv_base        TYPE string
                iv_maxlen      TYPE i
      RETURNING VALUE(rv_name) TYPE string.
ENDCLASS.


CLASS zcl_dex_namer IMPLEMENTATION.

  METHOD derive.
    " Names follow Z_<entity>_SRV. The entity already carries its C_/I_ prefix,
    " so this yields e.g. C_PurchaseOrderDEX -> project Z_C_PURCHASEORDERDEX,
    " service Z_C_PURCHASEORDERDEX_SRV  (and Z_I_..._SRV for master data).
    DATA(lv_core) = sanitize( iv_odp_name ).
    " Reserve room for the trailing suffix within the 30-char object-name limit.
    DATA(lv_stem) = make_unique( iv_base   = |{ c_prefix }{ lv_core }|
                                 iv_maxlen = 30 - strlen( c_suffix ) ).
    rs_names-segw_project    = lv_stem.
    rs_names-service_name    = |{ lv_stem }{ c_suffix }|.
    rs_names-external_name   = |{ lv_stem }{ c_suffix }|.
    rs_names-service_version = '0001'.
  ENDMETHOD.

  METHOD sanitize.
    DATA lv_char TYPE c LENGTH 1.
    DATA lv_res  TYPE string.

    DATA(lv_up) = |{ iv_in }|.
    TRANSLATE lv_up TO UPPER CASE.

    DATA(lv_len) = strlen( lv_up ).
    DATA lv_i TYPE i.
    WHILE lv_i < lv_len.
      lv_char = lv_up+lv_i(1).
      IF lv_char CA 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_'.
        lv_res = lv_res && lv_char.
      ELSE.
        lv_res = lv_res && '_'.
      ENDIF.
      lv_i = lv_i + 1.
    ENDWHILE.

    rv_out = lv_res.
  ENDMETHOD.

  METHOD make_unique.
    DATA(lv_base) = iv_base.
    IF strlen( lv_base ) > iv_maxlen.
      lv_base = lv_base(iv_maxlen).
    ENDIF.

    DATA(lv_candidate) = lv_base.
    DATA lv_seq TYPE i VALUE 1.
    WHILE line_exists( mt_used[ table_line = lv_candidate ] ).
      DATA(lv_suffix) = |{ lv_seq }|.
      DATA(lv_keep)   = iv_maxlen - strlen( lv_suffix ).
      IF lv_keep < 0.
        lv_keep = 0.
      ENDIF.
      IF strlen( lv_base ) > lv_keep.
        lv_candidate = |{ lv_base(lv_keep) }{ lv_suffix }|.
      ELSE.
        lv_candidate = |{ lv_base }{ lv_suffix }|.
      ENDIF.
      lv_seq = lv_seq + 1.
    ENDWHILE.

    INSERT lv_candidate INTO TABLE mt_used.
    rv_name = lv_candidate.
  ENDMETHOD.

ENDCLASS.
