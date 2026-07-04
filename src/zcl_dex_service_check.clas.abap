" Detect whether an OData service is already registered + active on the Gateway
" hub. Checks the registered-services catalog /IWFND/I_MED_SRH for an ACTIVE
" service whose technical (OBJECT_NAME) or external (SERVICE_NAME) name matches
" the derived service name (Z_<entity>_SRV). Used to flag already-published views
" (Published / Service columns).
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

    " @parameter iv_service_name | derived technical service name (Z_<entity>_SRV)
    METHODS check
      IMPORTING
        iv_service_name  TYPE clike
      RETURNING
        VALUE(rs_status) TYPE ty_status.
ENDCLASS.


CLASS zcl_dex_service_check IMPLEMENTATION.

  METHOD check.
    rs_status-determinable = abap_true.
    IF iv_service_name IS INITIAL.
      RETURN.
    ENDIF.

    " Registered + active services on the SAP Gateway hub. Match either the
    " technical service name (OBJECT_NAME) or the external name (SERVICE_NAME).
    SELECT SINGLE service_name
      FROM /iwfnd/i_med_srh
      WHERE ( object_name  = @iv_service_name
           OR service_name = @iv_service_name )
        AND is_active = @abap_true
      INTO @DATA(lv_found).

    IF sy-subrc = 0.
      rs_status-exists       = abap_true.
      rs_status-service_name = lv_found.
    ENDIF.
  ENDMETHOD.

ENDCLASS.
