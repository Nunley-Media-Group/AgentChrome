// Cucumber step functions receive captured strings as owned `String` values;
// clippy's needless_pass_by_value lint does not apply here.
#![allow(clippy::needless_pass_by_value)]

use cucumber::{World, given, then, when};
use serde_yaml::Value;
use std::path::PathBuf;

#[derive(Debug, Default, World)]
struct WorkflowWorld {
    ci_workflow: Option<Value>,
    release_workflow: Option<Value>,
    matrix_entry: Option<Value>,
}

fn project_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
}

fn load_yaml(path: &std::path::Path) -> Value {
    let contents = std::fs::read_to_string(path)
        .unwrap_or_else(|e| panic!("Failed to read {}: {e}", path.display()));
    serde_yaml::from_str(&contents)
        .unwrap_or_else(|e| panic!("Failed to parse {}: {e}", path.display()))
}

// --- Given steps ---

#[given("the CI workflow file exists")]
fn ci_workflow_exists(world: &mut WorkflowWorld) {
    let path = project_root().join(".github/workflows/ci.yml");
    assert!(path.exists(), "CI workflow file does not exist");
    world.ci_workflow = Some(load_yaml(&path));
}

#[given("the release workflow file exists")]
fn release_workflow_exists(world: &mut WorkflowWorld) {
    let path = project_root().join(".github/workflows/release.yml");
    assert!(path.exists(), "Release workflow file does not exist");
    world.release_workflow = Some(load_yaml(&path));
}

#[given("the release workflow has a build matrix")]
fn release_has_build_matrix(world: &mut WorkflowWorld) {
    let path = project_root().join(".github/workflows/release.yml");
    assert!(path.exists(), "Release workflow file does not exist");
    world.release_workflow = Some(load_yaml(&path));

    let workflow = world.release_workflow.as_ref().unwrap();
    let matrix = &workflow["jobs"]["build-release"]["strategy"]["matrix"]["include"];
    assert!(
        matrix.is_sequence(),
        "Build matrix 'include' is not a sequence"
    );
}

// --- When steps ---

#[when("I inspect the trigger configuration")]
fn inspect_triggers(_world: &mut WorkflowWorld) {
    // Triggers are checked in the Then steps
}

#[when("I inspect the check job steps")]
fn inspect_check_steps(_world: &mut WorkflowWorld) {
    // Steps are checked in the Then steps
}

#[when(expr = "I inspect the matrix entry for {string}")]
fn inspect_matrix_entry(world: &mut WorkflowWorld, target: String) {
    let workflow = world
        .release_workflow
        .as_ref()
        .expect("Release workflow not loaded");
    let includes = workflow["jobs"]["build-release"]["strategy"]["matrix"]["include"]
        .as_sequence()
        .expect("Matrix include is not a sequence");

    let entry = includes
        .iter()
        .find(|e| e["target"].as_str() == Some(target.as_str()))
        .unwrap_or_else(|| panic!("No matrix entry found for target '{target}'"));

    world.matrix_entry = Some(entry.clone());
}

#[when("I inspect the create-release job")]
fn inspect_create_release(_world: &mut WorkflowWorld) {
    // Checked in Then steps
}

// --- Then steps: CI triggers ---

#[then(expr = "it triggers on push to {string} branch")]
fn triggers_on_push(world: &mut WorkflowWorld, branch: String) {
    let workflow = world
        .ci_workflow
        .as_ref()
        .or(world.release_workflow.as_ref())
        .expect("No workflow loaded");
    let push_branches = &workflow["on"]["push"]["branches"];
    let branches = push_branches
        .as_sequence()
        .expect("push.branches is not a sequence");
    assert!(
        branches.iter().any(|b| b.as_str() == Some(branch.as_str())),
        "Branch '{branch}' not found in push triggers: {branches:?}"
    );
}

#[then(expr = "it triggers on pull_request to {string} branch")]
fn triggers_on_pr(world: &mut WorkflowWorld, branch: String) {
    let workflow = world
        .ci_workflow
        .as_ref()
        .or(world.release_workflow.as_ref())
        .expect("No workflow loaded");
    let pr_branches = &workflow["on"]["pull_request"]["branches"];
    let branches = pr_branches
        .as_sequence()
        .expect("pull_request.branches is not a sequence");
    assert!(
        branches.iter().any(|b| b.as_str() == Some(branch.as_str())),
        "Branch '{branch}' not found in pull_request triggers: {branches:?}"
    );
}

#[then(expr = "it triggers on push of tags matching {string}")]
fn triggers_on_tags(world: &mut WorkflowWorld, pattern: String) {
    let workflow = world
        .release_workflow
        .as_ref()
        .expect("Release workflow not loaded");
    let tags = &workflow["on"]["push"]["tags"];
    let tags = tags.as_sequence().expect("push.tags is not a sequence");
    assert!(
        tags.iter().any(|t| t.as_str() == Some(pattern.as_str())),
        "Tag pattern '{pattern}' not found in push.tags: {tags:?}"
    );
}

#[then("it supports workflow_dispatch")]
fn supports_workflow_dispatch(world: &mut WorkflowWorld) {
    let workflow = world
        .release_workflow
        .as_ref()
        .expect("Release workflow not loaded");
    assert!(
        !workflow["on"]["workflow_dispatch"].is_null(),
        "workflow_dispatch trigger not found"
    );
}

// --- Then steps: CI job steps ---

#[then(expr = "it runs {string}")]
fn runs_command(world: &mut WorkflowWorld, command: String) {
    let workflow = world.ci_workflow.as_ref().expect("CI workflow not loaded");
    let steps = workflow["jobs"]["check"]["steps"]
        .as_sequence()
        .expect("check.steps is not a sequence");
    let found = steps
        .iter()
        .any(|step| step["run"].as_str().is_some_and(|r| r.contains(&command)));
    assert!(found, "Command '{command}' not found in check job steps");
}

// --- Then steps: matrix ---

#[then(expr = "the runner is {string}")]
fn runner_is(world: &mut WorkflowWorld, expected_runner: String) {
    let entry = world
        .matrix_entry
        .as_ref()
        .expect("No matrix entry selected");
    let runner = entry["runner"]
        .as_str()
        .expect("Matrix entry has no 'runner' field");
    assert_eq!(runner, expected_runner, "Runner mismatch");
}

#[then(expr = "the archive format is {string}")]
fn archive_format_is(world: &mut WorkflowWorld, expected_format: String) {
    let entry = world
        .matrix_entry
        .as_ref()
        .expect("No matrix entry selected");
    let archive = entry["archive"]
        .as_str()
        .expect("Matrix entry has no 'archive' field");
    assert_eq!(archive, expected_format, "Archive format mismatch");
}

#[then("fail-fast is disabled")]
fn fail_fast_disabled(world: &mut WorkflowWorld) {
    let workflow = world
        .release_workflow
        .as_ref()
        .expect("Release workflow not loaded");
    let fail_fast = &workflow["jobs"]["build-release"]["strategy"]["fail-fast"];
    assert_eq!(
        fail_fast.as_bool(),
        Some(false),
        "fail-fast should be false, got: {fail_fast:?}"
    );
}

// --- Then steps: release jobs ---

#[then("it creates a draft GitHub Release")]
fn creates_draft_release(world: &mut WorkflowWorld) {
    let workflow = world
        .release_workflow
        .as_ref()
        .expect("Release workflow not loaded");
    let steps = workflow["jobs"]["create-release"]["steps"]
        .as_sequence()
        .expect("create-release.steps is not a sequence");
    let found = steps.iter().any(|step| {
        step["run"]
            .as_str()
            .is_some_and(|r| r.contains("gh release create") && r.contains("--draft"))
    });
    assert!(found, "No step found that creates a draft release");
}

#[then("it has a cleanup-release job that runs on failure")]
fn has_cleanup_job(world: &mut WorkflowWorld) {
    let workflow = world
        .release_workflow
        .as_ref()
        .expect("Release workflow not loaded");
    let cleanup = &workflow["jobs"]["cleanup-release"];
    assert!(!cleanup.is_null(), "cleanup-release job not found");
    let condition = cleanup["if"]
        .as_str()
        .expect("cleanup-release has no 'if' condition");
    assert!(
        condition.contains("failure()"),
        "cleanup-release should run on failure(), got: {condition}"
    );
}

// --- Then steps: security ---

#[then(expr = "the workflow permissions include {string} as {string}")]
fn permissions_include(world: &mut WorkflowWorld, key: String, value: String) {
    let workflow = world
        .release_workflow
        .as_ref()
        .expect("Release workflow not loaded");
    let perm = workflow["permissions"][&key]
        .as_str()
        .unwrap_or_else(|| panic!("permissions.{key} not found"));
    assert_eq!(perm, value, "permissions.{key} mismatch");
}

#[then("all action references use commit SHA pins")]
fn actions_use_sha_pins(world: &mut WorkflowWorld) {
    let workflow = world.ci_workflow.as_ref().expect("CI workflow not loaded");
    let steps = workflow["jobs"]["check"]["steps"]
        .as_sequence()
        .expect("check.steps is not a sequence");

    for step in steps {
        if let Some(uses) = step["uses"].as_str() {
            let after_at = uses
                .split('@')
                .nth(1)
                .unwrap_or_else(|| panic!("Action '{uses}' has no @ version"));
            assert!(
                after_at.len() >= 40 && after_at.chars().all(|c| c.is_ascii_hexdigit()),
                "Action '{uses}' is not pinned by commit SHA (found '{after_at}')"
            );
        }
    }
}

fn main() {
    let runner = WorkflowWorld::run("tests/features");
    futures::executor::block_on(runner);
}
