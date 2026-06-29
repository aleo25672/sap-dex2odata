" <p class="shorttext synchronized">Publish a DEX CDS view as an ODP-OData service</p>
" Implements ZIF_DEX_PUBLISHER via the SEGW "Data Source Reference -&gt; ODP" route:
" a SEGW project references the ODP provider (context ABAP_CDS), runtime objects are
" generated, and the service is registered on the Gateway hub. Delta semantics of the
" DEX/CDC view are preserved by the ODP reference.
"
" IMPORTANT (see plan): the programmatic SEGW generation + registration uses
" /IWBEP/ and /IWFND/ APIs whose exact signatures are release-dependent. Those calls
" are isolated in CREATE_SEGW_ODP_PROJECT( ). Until validated on the target release
" that method returns status 'P' (pending) with the exact manual steps, so the tool
" is fully usable today and the automation is a localized, well-marked extension point.
CLASS zcl_dex_segw_odp_publisher DEFINITION
  PUBLIC
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES zif_dex_publisher.

    METHODS constructor
      IMPORTING io_namer TYPE REF TO zcl_dex_namer OPTIONAL.

  PRIVATE SECTION.
    DATA mo_namer TYPE REF TO zcl_dex_namer.

    " Release-dependent core. Returns only status + message of the attempt.
    METHODS create_segw_odp_project
      IMPORTING
        iv_context       TYPE clike
        iv_odp_name      TYPE clike
        is_names         TYPE zif_dex_publisher=>ty_names
        is_options       TYPE zif_dex_publisher=>ty_options
      RETURNING
        VALUE(rs_partial) TYPE zif_dex_publisher=>ty_result.
ENDCLASS.


CLASS zcl_dex_segw_odp_publisher IMPLEMENTATION.

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

    " Dry-run: report what would be created, touch nothing.
    IF is_options-preview = abap_true.
      rs_result-status  = 'V'.
      rs_result-message =
        |Preview: would create SEGW project { is_names-segw_project } | &&
        |(ODP { iv_odp_name } / context { iv_context }) and register service | &&
        |{ is_names-service_name } in package { is_options-package }|.
      RETURN.
    ENDIF.

    TRY.
        DATA(ls_partial) = create_segw_odp_project(
          iv_context  = iv_context
          iv_odp_name = iv_odp_name
          is_names    = is_names
          is_options  = is_options ).
        rs_result-status  = ls_partial-status.
        rs_result-message = ls_partial-message.
      CATCH cx_root INTO DATA(lx).
        rs_result-status  = 'E'.
        rs_result-message = lx->get_text( ).
    ENDTRY.
  ENDMETHOD.

  METHOD create_segw_odp_project.
    "==================================================================
    " >>> RELEASE-DEPENDENT AUTOMATION EXTENSION POINT <<<
    " Implement programmatic creation here once the APIs are validated on
    " the target S/4HANA release (plan: "API validation first"):
    "   1. Create SEGW project IS_NAMES-segw_project in IS_OPTIONS-package
    "      / transport via the /IWBEP/ Service Builder model API.
    "   2. Import a Data Source Reference of type ODP referencing
    "      context IV_CONTEXT + ODP IV_ODP_NAME (maps structure + delta).
    "   3. Generate runtime objects (MPC/DPC + model/registration).
    "   4. Register/activate service IS_NAMES-service_name on the hub
    "      via the /IWFND/ add-service API.
    " On success: rs_partial-status = 'S'.
    "==================================================================

    " Guided manual fallback (no objects created):
    rs_partial-status  = 'P'.
    rs_partial-message =
      |Manual: SEGW > create project { is_names-segw_project } > Data Model > right-click > | &&
      |Import > Data Source Reference > type 'ODP' > local system alias > context | &&
      |{ iv_context } > ODP '{ iv_odp_name }' > Finish > Generate Runtime Objects > | &&
      |then register service '{ is_names-service_name }' in /IWFND/MAINT_SERVICE.|.
  ENDMETHOD.

ENDCLASS.
