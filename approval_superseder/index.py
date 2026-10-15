"""Keeps at most one run of the pipeline waiting at each manual approval: the newest one.

CodePipeline supersedes runs that wait in front of a stage, but not a run that already waits inside
a stage at a manual approval. Approving that run would deploy an outdated plan. Every approval
action of the deploy stages is a gate whose trigger is the stage in front of the approval's stage
(the previous stage), e.g. Dev for an approval in Int and Int for one in Prod.

This function runs when a run finishes a previous stage and when a run reaches an approval. If a
run waits at an approval while a newer run has finished that gate's previous stage, it stops the
waiting run, so the newer one moves into the approval stage and plans afresh. A run that is still
planning or already deploying is left alone; the newer run then waits in front of the stage until
the approval is reached again. Runs that CodePipeline has superseded, stopped or finished are
ignored, and the newest run is never stopped.

The run ids come from the event where possible: an event arrives a few seconds before the pipeline
state shows it, so the state would still show the approval as not started.

GATES holds the gates as JSON: [{"previous_stage", "previous_action", "approval_stage",
"approval_action"}], previous_action being the last action of the previous stage.
"""

import json
import os

import boto3

codepipeline = boto3.client("codepipeline")

PIPELINE = os.environ.get("PIPELINE_NAME", "")
GATES = json.loads(os.environ.get("GATES", "[]"))

STAGE_EVENT = "CodePipeline Stage Execution State Change"
ACTION_EVENT = "CodePipeline Action Execution State Change"


def waiting_at_approval(gate):
    """Returns the id of the run that waits at the gate's approval, or None."""
    for stage in codepipeline.get_pipeline_state(name=PIPELINE)["stageStates"]:
        if stage["stageName"] != gate["approval_stage"]:
            continue
        if stage.get("latestExecution", {}).get("status") != "InProgress":
            return None
        for action in stage.get("actionStates", []):
            if action["actionName"] == gate["approval_action"] and action.get("latestExecution", {}).get("status") == "InProgress":
                return stage["latestExecution"]["pipelineExecutionId"]
    return None


def runs():
    return codepipeline.list_pipeline_executions(pipelineName=PIPELINE, maxResults=25)["pipelineExecutionSummaries"]


def newer_run_past_previous_stage(gate, waiting_id):
    """Returns the id of a run started after the waiting one that has finished the gate's previous stage, or None."""
    summaries = runs()
    started = {run["pipelineExecutionId"]: run["startTime"] for run in summaries}
    if waiting_id not in started:
        return None
    for run in summaries:
        if run["status"] != "InProgress" or run["pipelineExecutionId"] == waiting_id or run["startTime"] <= started[waiting_id]:
            continue
        actions = codepipeline.list_action_executions(
            pipelineName=PIPELINE, filter={"pipelineExecutionId": run["pipelineExecutionId"]}
        )["actionExecutionDetails"]
        if any(
            a["stageName"] == gate["previous_stage"] and a["actionName"] == gate["previous_action"] and a["status"] == "Succeeded"
            for a in actions
        ):
            return run["pipelineExecutionId"]
    return None


def started_before(older_id, newer_id):
    started = {run["pipelineExecutionId"]: run["startTime"] for run in runs()}
    return older_id in started and newer_id in started and started[older_id] < started[newer_id]


def stop(gate, waiting_id, newer_id):
    print(
        f"Stopping run {waiting_id} at {gate['approval_action']}: run {newer_id} has finished"
        f" {gate['previous_stage']} and plans {gate['approval_stage']} afresh."
    )
    try:
        codepipeline.stop_pipeline_execution(
            pipelineName=PIPELINE,
            pipelineExecutionId=waiting_id,
            abandon=True,
            reason=f"Superseded by the newer run {newer_id}, which plans {gate['approval_stage']} afresh.",
        )
    except Exception as error:  # pylint: disable=broad-exception-caught
        # The events of both runs can arrive within seconds; the other invocation stopped it first.
        if type(error).__name__ != "PipelineExecutionNotStoppableException":
            raise
        print(f"Run {waiting_id} has already been stopped.")


def reached_approval(gate, run_id):
    """This run has just reached the approval. Is there a newer run that has finished the previous stage?"""
    newer_id = newer_run_past_previous_stage(gate, run_id)
    if newer_id is None:
        print(f"Run {run_id} reached {gate['approval_action']} and is the newest past {gate['previous_stage']}; it stays.")
        return
    stop(gate, run_id, newer_id)


def finished_previous_stage(gate, run_id):
    """This run has just finished the previous stage. Does an older run wait at the approval?"""
    waiting_id = waiting_at_approval(gate)
    if waiting_id is None or waiting_id == run_id or not started_before(waiting_id, run_id):
        print(f"Run {run_id} finished {gate['previous_stage']}; no older run waits at {gate['approval_action']}.")
        return
    stop(gate, waiting_id, run_id)


def check_state(gate):
    """Invoked by hand: decides from the pipeline state alone."""
    waiting_id = waiting_at_approval(gate)
    if waiting_id is None:
        print(f"No run waits at {gate['approval_action']}; nothing to do.")
        return
    newer_id = newer_run_past_previous_stage(gate, waiting_id)
    if newer_id is None:
        print(f"Run {waiting_id} waits at {gate['approval_action']} and is the newest past {gate['previous_stage']}; it stays.")
        return
    stop(gate, waiting_id, newer_id)


def handler(event, _context):
    detail = event.get("detail", {})
    run_id = detail.get("execution-id")

    if event.get("detail-type") == ACTION_EVENT and run_id:
        for gate in GATES:
            if gate["approval_stage"] == detail.get("stage") and gate["approval_action"] == detail.get("action"):
                reached_approval(gate, run_id)
        return

    if event.get("detail-type") == STAGE_EVENT and run_id:
        for gate in GATES:
            if gate["previous_stage"] == detail.get("stage"):
                finished_previous_stage(gate, run_id)
        return

    for gate in GATES:
        check_state(gate)
