# PocketGallery R4.7 full-gate diagnostic

- source_commit: 1ac326881863c8a41003c43b25ddb1c7cbb3a3e9
- workflow_run: 33615834926
- flutter: Flutter 3.47.2 • channel stable • https://github.com/flutter/flutter.git

## manifest

exit_code: 0

```text
```

## pub_get

exit_code: 0

```text
+ file_picker_darwin 1.0.4
+ file_picker_linux 1.0.2
+ file_picker_platform_interface 3.2.0
+ file_picker_web 3.0.3
+ flutter 0.0.0 from sdk flutter
+ flutter_gemma 1.7.0
+ flutter_gemma_embeddings 2.0.0
+ flutter_gemma_litertlm 1.6.1
+ flutter_gemma_rag_sqlite 1.3.1
+ flutter_lints 6.0.0
+ flutter_localizations 0.0.0 from sdk flutter
+ flutter_secure_storage 10.3.1 (11.0.0 available)
+ flutter_secure_storage_darwin 0.3.2 (0.4.0 available)
+ flutter_secure_storage_linux 3.0.2
+ flutter_secure_storage_platform_interface 2.0.3
+ flutter_secure_storage_web 2.1.1
+ flutter_secure_storage_windows 4.2.2
+ flutter_test 0.0.0 from sdk flutter
+ flutter_web_plugins 0.0.0 from sdk flutter
+ genai_primitives 0.2.4
+ glob 2.2.0
+ hooks 2.2.0
+ http 1.6.0
+ http_parser 4.1.2
+ image 4.9.2
+ intl 0.20.3
+ jni 1.0.3
+ jni_flutter 1.0.3
+ jni_util 1.0.0
+ json_schema_builder 0.1.7
+ large_file_handler 0.5.2
+ leak_tracker 11.0.2
+ leak_tracker_flutter_testing 3.0.10
+ leak_tracker_testing 3.0.2
+ lints 6.1.0
+ logging 1.3.0
+ matcher 0.12.20
+ material_color_utilities 0.13.0 (0.13.1 available)
+ material_ui 1.1.0
+ meta 1.19.0
+ mime 2.1.0
+ mutex 3.1.0
+ native_toolchain_c 0.19.3 (0.19.4 available)
+ objective_c 9.5.0 (9.6.0 available)
+ package_config 3.0.0
+ path 1.9.1
+ path_provider 2.1.6
+ path_provider_android 2.3.1
+ path_provider_foundation 2.6.0
+ path_provider_linux 2.2.2
+ path_provider_platform_interface 2.1.3
+ path_provider_windows 2.3.0
+ pdfium_dart 0.2.5
+ pdfium_flutter 0.2.3
+ pdfrx 2.5.0
+ pdfrx_engine 0.5.0
+ petitparser 7.0.2
+ platform 3.1.6
+ plugin_platform_interface 2.1.8
+ posix 6.5.2
+ pub_semver 2.2.1
+ rational 2.2.3
+ record_use 1.1.1
+ rxdart 0.28.0
+ shared_preferences 2.5.5
+ shared_preferences_android 2.4.28
+ shared_preferences_foundation 2.5.7
+ shared_preferences_linux 2.4.1
+ shared_preferences_platform_interface 2.4.2
+ shared_preferences_web 2.4.3
+ shared_preferences_windows 2.4.1
+ sky_engine 0.0.0 from sdk flutter
+ source_span 1.10.2
+ sqlite3 3.5.2
+ stack_trace 1.12.2
+ stream_channel 2.1.4
+ string_scanner 1.4.1
+ synchronized 3.4.1+2
+ term_glyph 1.2.2
+ test_api 0.7.12 (0.7.13 available)
+ typed_data 1.4.0
+ url_launcher 6.3.2
+ url_launcher_android 6.3.33
+ url_launcher_ios 6.4.2
+ url_launcher_linux 3.2.3
+ url_launcher_macos 3.2.6
+ url_launcher_platform_interface 2.3.2
+ url_launcher_web 2.4.3
+ url_launcher_windows 3.1.6
+ vector_math 2.4.2
+ vm_service 15.3.0
+ web 1.1.1
+ win32 6.4.0
+ windows_file_picker 1.1.0
+ xdg_directories 1.1.0
+ xml 7.0.1
+ yaml 3.1.4
Changed 119 dependencies!
7 packages have newer versions incompatible with dependency constraints.
Try `flutter pub outdated` for more information.
```

## format

exit_code: 1

```text
Changed lib/acceptance/handset_acceptance_runner.dart
Changed lib/acceptance/handset_acceptance_store.dart
Changed lib/experiments/retrieval_experiment_engine.dart
Changed lib/lineage/r45_vector_migration.dart
Changed lib/observability/trace_vector_space_service.dart
Changed lib/okf/okf_experiment_engine.dart
Changed lib/services/golden_gate_executor.dart
Changed lib/services/golden_test_report_store.dart
Changed lib/services/lexical_fts_store.dart
Changed lib/ui/chat_page.dart
Changed lib/ui/handset_acceptance_page.dart
Changed lib/ui/handset_acceptance_widgets.dart
Changed lib/ui/microscope/experiment_run_detail_page.dart
Changed lib/ui/microscope/lineage_dashboard_visuals.dart
Changed lib/ui/microscope/rag_lineage_dashboard_page.dart
Changed lib/ui/model_settings_page.dart
Changed test/r2_auto_model_bootstrap_test.dart
Changed test/r31_phone_recovery_test.dart
Changed test/r32_oauth_resume_test.dart
Changed test/r33_device_code_ux_test.dart
Changed test/r3_model_cache_contract_test.dart
Changed test/r3_oauth_device_flow_test.dart
Changed test/r401_phone_realworld_recovery_test.dart
Changed test/r402_chat_attachment_test.dart
Changed test/r403_embedding_runtime_recovery_test.dart
Changed test/r41_microscope_ui_test.dart
Changed test/r41_upgrade_contract_test.dart
Changed test/r41_vector_observation_test.dart
Changed test/r42_upgrade_persistence_regression_test.dart
Changed test/r43_realworld_phone_regression_test.dart
Changed test/r44_embedding_repair_regression_test.dart
Changed test/r45_retrieval_quality_regression_test.dart
Changed test/r46_context_generation_lineage_test.dart
Changed test/r46_corpus_context_regression_test.dart
Changed test/r46_import_lineage_test.dart
Changed test/r46_lineage_store_test.dart
Changed test/r46_retrieval_runtime_test.dart
Changed test/r46_upgrade_golden_contract_test.dart
Changed test/r46_vector_health_test.dart
Changed test/r46_vector_index_test.dart
Changed test/r46_vector_migration_test.dart
Changed test/r46_vector_migration_wiring_test.dart
Changed test/r46bc_release_contract_test.dart
Changed test/r46bc_trace_report_test.dart
Changed test/r47_okf_shadow_lab_test.dart
Changed test/r48_phone_acceptance_regression_test.dart
Changed test/r49_vector_space_page_test.dart
Changed test/r4_chat_session_store_test.dart
Changed test/r4_gemma_chat_contract_test.dart
Changed test/r4_knowledge_engine_compat_test.dart
Changed test/r4_knowledge_retriever_test.dart
Changed test/r4_model_settings_ui_test.dart
Changed test/r4_upgrade_contract_test.dart
Changed test/r50_android_host_contract_test.dart
Changed test/r50_device_resource_sampler_test.dart
Changed test/r50_frame_timing_test.dart
Changed test/r50_golden_trace_handoff_test.dart
Changed test/r50_handset_acceptance_runner_test.dart
Changed test/r50_handset_acceptance_ui_test.dart
Changed test/r50_handset_report_redaction_test.dart
Changed test/r50_handset_vector_interaction_page_test.dart
Changed test/r50_release_contract_test.dart
Changed test/r50_release_readiness_adjudicator_test.dart
Changed test/r50_vector_truth_test.dart
Formatted 204 files (64 changed) in 0.60 seconds.
```

## Result

first_failing_stage: format
