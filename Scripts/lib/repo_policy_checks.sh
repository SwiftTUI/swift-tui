# Shared policy-check phase for the local repo gate and the CI policy job.

run_repo_policy_check() {
  mode=$1
  repo_root=$2
  title=$3
  rerun_command=$4
  shift 4

  case "$mode" in
  direct)
    echo "[check_repo_policy_phase] $title"
    (
      cd "$repo_root"
      "$@"
    )
    ;;
  test-all)
    run_step "$title" "$repo_root" "$rerun_command" "$@"
    ;;
  *)
    >&2 echo "Unknown repo policy phase mode: $mode"
    return 2
    ;;
  esac
}

run_repo_policy_phase() {
  repo_root=$1
  mode=$2

  run_repo_policy_check \
    "$mode" \
    "$repo_root" \
    "Check public-surface policies" \
    "./Scripts/check_public_surface_policies.sh" \
    ./Scripts/check_public_surface_policies.sh

  run_repo_policy_check \
    "$mode" \
    "$repo_root" \
    "Check public documentation ratchet" \
    "./Scripts/check_public_documentation_ratchet.sh" \
    ./Scripts/check_public_documentation_ratchet.sh

  run_repo_policy_check \
    "$mode" \
    "$repo_root" \
    "Check stable doc source paths" \
    "./Scripts/check_stable_doc_source_paths.sh" \
    ./Scripts/check_stable_doc_source_paths.sh

  run_repo_policy_check \
    "$mode" \
    "$repo_root" \
    "Check DocC coverage policy" \
    "./Scripts/check_docc_coverage.sh" \
    ./Scripts/check_docc_coverage.sh

  run_repo_policy_check \
    "$mode" \
    "$repo_root" \
    "Check root test-target coverage" \
    "./Scripts/check_root_test_target_coverage.sh" \
    ./Scripts/check_root_test_target_coverage.sh

  run_repo_policy_check \
    "$mode" \
    "$repo_root" \
    "Check rendered text fixture matrix" \
    "./Scripts/check_rendered_text_fixture_matrix.sh" \
    ./Scripts/check_rendered_text_fixture_matrix.sh

  run_repo_policy_check \
    "$mode" \
    "$repo_root" \
    "Check concurrency-safety policies" \
    "./Scripts/check_concurrency_safety_policies.sh" \
    ./Scripts/check_concurrency_safety_policies.sh

  run_repo_policy_check \
    "$mode" \
    "$repo_root" \
    "Check accessibility guardrails" \
    "./Scripts/check_accessibility_guardrails.sh" \
    ./Scripts/check_accessibility_guardrails.sh

  run_repo_policy_check \
    "$mode" \
    "$repo_root" \
    "Check WebHost package boundary" \
    "./Scripts/check_webhost_package_boundary.sh" \
    ./Scripts/check_webhost_package_boundary.sh

  run_repo_policy_check \
    "$mode" \
    "$repo_root" \
    "Check public-API baseline" \
    "./Scripts/generate_public_api_inventory.sh --check" \
    ./Scripts/generate_public_api_inventory.sh --check
}
