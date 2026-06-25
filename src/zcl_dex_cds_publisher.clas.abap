"! <p class="shorttext synchronized">Publish a master-data CDS view as a full-reload OData service</p>
"! Implements ZIF_DEX_PUBLISHER for the I_* master-data family: these views are NOT
"! ODP/CDC extraction-enabled but are small in volume, so they are exposed as a plain
"! (non-ODP) OData service consumed by full reload on a nightly/weekly schedule.
"!
"! Mechanism: SEGW project with a CDS reference data source (no ODP / no delta), or an
"! equivalent Service Binding. As with the ODP publisher, the programmatic creation +
"! registration is release-dependent and isolated in CREATE_FULL_SERVICE( ); until
"! validated it returns status 'P' with the exact manual steps.
CLASS zcl_dex_cds_publisher DEFINITION
  PUBLIC
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES zif_dex_publisher.

    METHODS constructor
      IMPORTING io_namer TYPE REF TO zcl_dex_namer OPTIONAL.

  PRIVATE SECTION.
    DATA mo_namer TYPE REF TO zcl_dex_namer.

    METHODS create_full_service
      IMPORTING
        iv_entity         TYPE clike
        is_names          TYPE zif_dex_publisher=>ty_names
        is_options        TYPE zif_dex_publisher=>ty_options
      RETURNING
        VALUE(rs_partial) TYPE zif_dex_publisher=>ty_result.
ENDCLASS.


CLASS zcl_dex_cds_publisher IMPLEMENTATION.

  METHOD constructor.
    mo_namer = io_namer.
  ENDMETHOD.

  METHOD zif_dex_publisher~publish.
    rs_result-odp_context  = iv_context.
    rs_result-odp_name     = iv_odp_name.
    rs_result-mode         = is_options-mode.
    rs_result-schedule     = is_options-schedule.
    rs_result-segw_project = is_names-segw_project.
    rs_result-service_name = is_names-service_name.
    rs_result-service_url  = |/sap/opu/odata/sap/{ is_names-service_name }/|.

    IF is_options-preview = abap_true.
      rs_result-status  = 'V'.
      rs_result-message =
        |Preview: would expose master-data view { iv_odp_name } as full-reload OData | &&
        |service { is_names-service_name } ({ is_options-schedule } schedule) in | &&
        |package { is_options-package }|.
      RETURN.
    ENDIF.

    TRY.
        DATA(ls_partial) = create_full_service(
          iv_entity  = iv_odp_name
          is_names   = is_names
          is_options = is_options ).
        rs_result-status  = ls_partial-status.
        rs_result-message = ls_partial-message.
      CATCH cx_root INTO DATA(lx).
        rs_result-status  = 'E'.
        rs_result-message = lx->get_text( ).
    ENDTRY.
  ENDMETHOD.

  METHOD create_full_service.
    "==================================================================
    " >>> RELEASE-DEPENDENT AUTOMATION EXTENSION POINT <<<
    " Implement programmatic creation once APIs are validated on the
    " target release:
    "   1. Create SEGW project IS_NAMES-segw_project (package/transport).
    "   2. Import a Data Source Reference to the CDS entity IV_ENTITY
    "      (Business Entity / CDS reference - NOT ODP, no delta).
    "   3. Generate runtime objects.
    "   4. Register service IS_NAMES-service_name on the hub (/IWFND/).
    "   5. (Optional) create the background job for the full reload on the
    "      IS_OPTIONS-schedule cadence, or leave scheduling to the consumer.
    " On success: rs_partial-status = 'S'.
    "==================================================================

    DATA(lv_sched) = COND string(
      WHEN is_options-schedule IS INITIAL THEN `on demand`
      ELSE |on a { to_lower( is_options-schedule ) } schedule| ).

    rs_partial-status  = 'P'.
    rs_partial-message =
      |Manual: SEGW > create project { is_names-segw_project } > Data Model > Import > | &&
      |Data Source Reference > CDS entity '{ iv_entity }' (plain, no ODP) > Generate | &&
      |Runtime > register '{ is_names-service_name }' in /IWFND/MAINT_SERVICE. | &&
      |Consume via full reload { lv_sched }.|.
  ENDMETHOD.

ENDCLASS.
