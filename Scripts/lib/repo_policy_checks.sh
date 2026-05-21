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

  # Run prek hooks first.  prek owns hooks that have no standalone
  # script (notably swift-format and `no-foundation-in-library-products`)
  # and also re-invokes the script-based hooks below.  Putting it at
  # the top of the phase lets the gate fail fast on policy violations
  # that would otherwise only surface at `git commit` time.
  #
  # Scope is the branch's diff against `origin/main` rather than
  # `--all-files`.  Two reasons:
  #
  #   1. The pre-commit hook on the developer's machine is also scoped
  #      to staged files, so the gate matches its scope — no surprise
  #      reformats of files this branch didn't touch.
  #   2. `swift-format` rewrites files in-place; running it across the
  #      whole repo would silently reformat code unrelated to this
  #      branch, producing a noisy diff and obscuring the actual
  #      changes under review.
  #
  # If `prek` is not installed locally the step is skipped — the
  # commit-time hooks still catch the same issues, and CI installs
  # prek explicitly.  This keeps the gate runnable on machines that
  # have not finished onboarding.
  if command -v prek >/dev/null 2>&1; then
    run_repo_policy_check \
      "$mode" \
      "$repo_root" \
      "Run prek hooks (branch diff vs origin/main)" \
      "prek run --from-ref origin/main --to-ref HEAD" \
      prek run --from-ref origin/main --to-ref HEAD
  else
    echo "[check_repo_policy_phase] prek not on PATH — skipping prek run"
    echo "  install it from https://prek.j178.dev to catch policy"
    echo "  violations during the gate rather than at commit time."
  fi

  run_repo_policy_check \
    "$mode" \
    "$repo_root" \
    "Check public-surface policies" \
    "./Scripts/check_public_surface_policies.sh" \
    ./Scripts/check_public_surface_policies.sh

  run_repo_policy_check \
    "$mode" \
    "$repo_root" \
    "Check stable doc source paths" \
    "./Scripts/check_stable_doc_source_paths.sh" \
    ./Scripts/check_stable_doc_source_paths.sh

  run_repo_policy_check \
    "$mode" \
    "$repo_root" \
    "Check DocC coverage" \
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
    "Check WebHost package boundary" \
    "./Scripts/check_webhost_package_boundary.sh" \
    ./Scripts/check_webhost_package_boundary.sh

  run_repo_policy_check \
    "$mode" \
    "$repo_root" \
    "Check test synchronisation policies" \
    "./Scripts/check_test_sync_policies.sh" \
    ./Scripts/check_test_sync_policies.sh

  run_repo_policy_check \
    "$mode" \
    "$repo_root" \
    "Check public-API baseline" \
    "./Scripts/generate_public_api_inventory.sh --check" \
    ./Scripts/generate_public_api_inventory.sh --check
}
