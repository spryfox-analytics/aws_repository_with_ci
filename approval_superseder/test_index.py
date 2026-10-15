"""Unit tests of the approval superseder, without AWS: python3 -m unittest discover -s approval_superseder"""

import sys
import types
import unittest
from datetime import datetime, timedelta
from unittest import mock

# The Lambda runtime brings boto3; the tests replace it, so they need no AWS SDK.
sys.modules.setdefault("boto3", types.SimpleNamespace(client=lambda _name: mock.MagicMock()))

import index  # noqa: E402  pylint: disable=wrong-import-position

T0 = datetime(2026, 10, 15, 12, 0)

# The gates of Source → Dev → Int (plan, approve, apply) → Prod (plan, approve, apply).
INT_GATE = {"previous_stage": "Dev", "previous_action": "apply-dev", "approval_stage": "Int", "approval_action": "approve-int"}
PROD_GATE = {"previous_stage": "Int", "previous_action": "apply-int", "approval_stage": "Prod", "approval_action": "approve-prod"}
STAGES = {"Source": ["Source"], "Dev": ["apply-dev"], "Int": ["plan-int", "approve-int", "apply-int"], "Prod": ["plan-prod", "approve-prod", "apply-prod"]}

DEV_DONE = [("Source", "Source"), ("Dev", "apply-dev")]
INT_DONE = DEV_DONE + [("Int", "plan-int"), ("Int", "approve-int"), ("Int", "apply-int")]


class Pipeline:
    """Stub of the CodePipeline client.

    runs: {run id: (minutes after T0, status)}; at: {stage: (run id, action in progress or None)};
    done: {run id: [(stage, action)] that succeeded}.
    """

    def __init__(self, runs, at=None, done=None):
        self.runs = dict(runs)
        self.at = at or {}
        self.done = done or {}
        self.stopped = []

    def get_pipeline_state(self, name):  # pylint: disable=unused-argument
        states = []
        for stage_name, actions in STAGES.items():
            stage = {"stageName": stage_name, "actionStates": [{"actionName": a} for a in actions]}
            if stage_name in self.at:
                run_id, current = self.at[stage_name]
                stage["latestExecution"] = {"pipelineExecutionId": run_id, "status": "InProgress"}
                for action in stage["actionStates"]:
                    if action["actionName"] == current:
                        action["latestExecution"] = {"status": "InProgress"}
            states.append(stage)
        return {"stageStates": states}

    def list_pipeline_executions(self, pipelineName, maxResults):  # pylint: disable=invalid-name,unused-argument
        summaries = [
            {"pipelineExecutionId": run_id, "startTime": T0 + timedelta(minutes=offset), "status": status}
            for run_id, (offset, status) in self.runs.items()
        ]
        return {"pipelineExecutionSummaries": sorted(summaries, key=lambda s: s["startTime"], reverse=True)}

    def list_action_executions(self, pipelineName, filter):  # pylint: disable=invalid-name,unused-argument,redefined-builtin
        done = self.done.get(filter["pipelineExecutionId"], [])
        return {"actionExecutionDetails": [{"stageName": s, "actionName": a, "status": "Succeeded"} for s, a in done]}

    def stop_pipeline_execution(self, pipelineName, pipelineExecutionId, abandon, reason):  # pylint: disable=invalid-name,unused-argument
        assert abandon
        if self.runs[pipelineExecutionId][1] != "InProgress":
            raise PipelineExecutionNotStoppableException(pipelineExecutionId)
        self.stopped.append(pipelineExecutionId)
        self.runs[pipelineExecutionId] = (self.runs[pipelineExecutionId][0], "Stopped")


class PipelineExecutionNotStoppableException(Exception):
    """Named like the error CodePipeline raises for a run that is already stopped."""


def stage_succeeded(run_id, stage):
    return {"detail-type": index.STAGE_EVENT, "detail": {"execution-id": run_id, "stage": stage, "state": "SUCCEEDED"}}


def approval_started(run_id, gate):
    return {"detail-type": index.ACTION_EVENT, "detail": {"execution-id": run_id, "stage": gate["approval_stage"], "action": gate["approval_action"], "state": "STARTED"}}


def run_handler(pipeline, event):
    index.codepipeline = pipeline
    index.handler(event, None)
    return pipeline.stopped


class IntGate(unittest.TestCase):
    """The Int approval, gated by Dev. ProdGate repeats every case for the Prod approval, gated by Int."""

    gate = INT_GATE
    done = DEV_DONE  # what a run has done once it has finished the gate's previous stage
    before = DEV_DONE[:1]  # the same before it has finished it

    def setUp(self):
        index.GATES = [INT_GATE, PROD_GATE]
        stage = self.gate["approval_stage"].lower()
        self.plan, self.approve, self.apply = f"plan-{stage}", f"approve-{stage}", f"apply-{stage}"

    def two_runs(self, waiting, action, new_done=None):
        done = {"old": self.done, "new": self.done if new_done is None else new_done}
        return Pipeline({"old": (0, "InProgress"), "new": (5, "InProgress")}, {self.gate["approval_stage"]: (waiting, action)}, done)

    def finished(self, run_id):
        return stage_succeeded(run_id, self.gate["previous_stage"])

    def reached(self, run_id):
        return approval_started(run_id, self.gate)

    def test_newer_run_finishing_the_previous_stage_stops_the_run_waiting_at_the_approval(self):
        self.assertEqual(run_handler(self.two_runs("old", self.approve), self.finished("new")), ["old"])

    def test_run_reaching_the_approval_is_stopped_when_a_newer_run_has_finished_the_previous_stage(self):
        self.assertEqual(run_handler(self.two_runs("old", None), self.reached("old")), ["old"])

    def test_run_reaching_the_approval_stays_while_the_newer_run_has_not_finished_the_previous_stage(self):
        pipeline = self.two_runs("old", self.approve, new_done=self.before)
        self.assertEqual(run_handler(pipeline, self.reached("old")), [])
        self.assertEqual(run_handler(pipeline, {}), [])

    def test_run_that_is_planning_is_not_stopped(self):
        self.assertEqual(run_handler(self.two_runs("old", self.plan), self.finished("new")), [])

    def test_run_that_is_deploying_is_not_stopped(self):
        self.assertEqual(run_handler(self.two_runs("old", self.apply), self.finished("new")), [])

    def test_newest_run_waiting_at_the_approval_is_not_stopped(self):
        # An older run finishes the previous stage late, e.g. after a retry, while the newest waits.
        pipeline = self.two_runs("new", self.approve)
        self.assertEqual(run_handler(pipeline, self.finished("old")), [])
        self.assertEqual(run_handler(pipeline, self.reached("new")), [])
        self.assertEqual(run_handler(pipeline, {}), [])

    def test_single_run_at_the_approval_is_not_stopped(self):
        pipeline = Pipeline({"only": (0, "InProgress")}, {self.gate["approval_stage"]: ("only", self.approve)}, {"only": self.done})
        self.assertEqual(run_handler(pipeline, self.finished("only")), [])
        self.assertEqual(run_handler(pipeline, self.reached("only")), [])

    def test_superseded_stopped_and_failed_newer_runs_are_ignored(self):
        runs = {"old": (0, "InProgress"), "superseded": (5, "Superseded"), "stopped": (6, "Stopped"), "failed": (7, "Failed")}
        pipeline = Pipeline(runs, {self.gate["approval_stage"]: ("old", self.approve)}, {run: self.done for run in runs})
        self.assertEqual(run_handler(pipeline, self.reached("old")), [])
        self.assertEqual(run_handler(pipeline, {}), [])

    def test_success_of_an_action_of_the_same_name_in_another_stage_does_not_count(self):
        pipeline = self.two_runs("old", None, new_done=self.before + [("Other", self.gate["previous_action"])])
        self.assertEqual(run_handler(pipeline, self.reached("old")), [])

    def test_manual_invocation_decides_from_the_pipeline_state(self):
        self.assertEqual(run_handler(self.two_runs("old", self.approve), {}), ["old"])

    def test_no_run_at_the_approval(self):
        pipeline = Pipeline({"new": (5, "InProgress")}, {}, {"new": self.done})
        self.assertEqual(run_handler(pipeline, self.finished("new")), [])
        self.assertEqual(run_handler(pipeline, {}), [])


class ProdGate(IntGate):
    gate = PROD_GATE
    done = INT_DONE
    before = DEV_DONE  # a newer run that has only finished dev does not supersede the prod approval


class SeveralGates(unittest.TestCase):
    def setUp(self):
        index.GATES = [INT_GATE, PROD_GATE]

    def test_finishing_dev_supersedes_the_int_approval_only(self):
        # a waits at prod, b at int, c has just finished dev: only b makes way.
        runs = {"a": (0, "InProgress"), "b": (5, "InProgress"), "c": (10, "InProgress")}
        at = {"Int": ("b", "approve-int"), "Prod": ("a", "approve-prod")}
        done = {"a": INT_DONE, "b": DEV_DONE, "c": DEV_DONE}
        self.assertEqual(run_handler(Pipeline(runs, at, done), stage_succeeded("c", "Dev")), ["b"])
        self.assertEqual(run_handler(Pipeline(runs, at, done), {}), ["b"])

    def test_finishing_int_supersedes_the_prod_approval(self):
        runs = {"a": (0, "InProgress"), "b": (5, "InProgress")}
        pipeline = Pipeline(runs, {"Prod": ("a", "approve-prod")}, {"a": INT_DONE, "b": INT_DONE})
        self.assertEqual(run_handler(pipeline, stage_succeeded("b", "Int")), ["a"])

    def test_events_without_a_gate_change_nothing(self):
        runs = {"a": (0, "InProgress"), "b": (5, "InProgress")}
        pipeline = Pipeline(runs, {"Prod": ("a", "approve-prod")}, {"a": INT_DONE, "b": INT_DONE})
        self.assertEqual(run_handler(pipeline, stage_succeeded("b", "Prod")), [])
        other_action = {"detail-type": index.ACTION_EVENT, "detail": {"execution-id": "a", "stage": "Prod", "action": "plan-prod"}}
        self.assertEqual(run_handler(pipeline, other_action), [])

    def test_approval_in_the_first_deploy_stage_is_gated_by_source(self):
        index.GATES = [{"previous_stage": "Source", "previous_action": "Source", "approval_stage": "Int", "approval_action": "approve-int"}]
        runs = {"a": (0, "InProgress"), "b": (5, "InProgress")}
        pipeline = Pipeline(runs, {"Int": ("a", "approve-int")}, {"a": [("Source", "Source")], "b": [("Source", "Source")]})
        self.assertEqual(run_handler(pipeline, stage_succeeded("b", "Source")), ["a"])

    def test_both_events_of_a_race_stop_the_run_once(self):
        # b reaches the approval while c finishes dev; both invocations decide to stop b.
        runs = {"b": (5, "InProgress"), "c": (10, "InProgress")}
        pipeline = Pipeline(runs, {"Int": ("b", "approve-int")}, {"b": DEV_DONE, "c": DEV_DONE})
        self.assertEqual(run_handler(pipeline, approval_started("b", INT_GATE)), ["b"])
        pipeline.at = {"Int": ("b", "approve-int")}  # the state still shows b waiting for a moment
        self.assertEqual(run_handler(pipeline, stage_succeeded("c", "Dev")), ["b"])

    def test_other_errors_are_raised(self):
        pipeline = Pipeline({"a": (0, "InProgress"), "b": (5, "InProgress")}, {"Int": ("a", "approve-int")}, {"a": DEV_DONE, "b": DEV_DONE})

        def fail(**_kwargs):
            raise RuntimeError("AccessDenied")

        pipeline.stop_pipeline_execution = fail
        with self.assertRaises(RuntimeError):
            run_handler(pipeline, {})

    def test_without_gates_nothing_happens(self):
        index.GATES = []
        pipeline = Pipeline({"a": (0, "InProgress")})
        self.assertEqual(run_handler(pipeline, {}), [])


if __name__ == "__main__":
    unittest.main()
