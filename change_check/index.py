"""Rule of the stage conditions: lets a stage run only if the pipeline's directory changed.

The rule passes (the stage runs) when a file below the directory differs from the source of the
pipeline's last successful execution, and fails (the stage is skipped) when nothing there changed.
Files are compared by name and CRC-32 from the ZIP's central directory, so nothing is extracted.

Building needlessly is cheaper than missing a change, so the rule passes whenever it cannot tell:
on the first execution, for executions started by hand, and on any error.
"""

import io
import json
import zipfile

import boto3

codepipeline = boto3.client("codepipeline")
s3 = boto3.client("s3")


def handler(event, _context):
    job = event["CodePipeline.job"]
    try:
        parameters = json.loads(job["data"]["actionConfiguration"]["configuration"]["UserParameters"])
        location = job["data"]["inputArtifacts"][0]["location"]["s3Location"]
        run, reason = should_run(parameters, location["bucketName"], location["objectKey"])
    except Exception as error:  # pylint: disable=broad-exception-caught
        run, reason = True, f"Running the stage, the change check failed: {error!r}"
    print(reason)
    if run:
        codepipeline.put_job_success_result(jobId=job["id"])
    else:
        codepipeline.put_job_failure_result(
            jobId=job["id"], failureDetails={"type": "JobFailed", "message": reason[:5000]}
        )


def should_run(parameters, bucket, key):
    pipeline = parameters["pipeline"]
    directory = parameters.get("directory") or ""
    prefix = f"{directory}/" if directory else ""
    where = f"{prefix or 'the repository'}"

    execution_id = parameters.get("execution", "")
    if execution_id and not execution_id.startswith("#{"):
        execution = codepipeline.get_pipeline_execution(pipelineName=pipeline, pipelineExecutionId=execution_id)
        trigger = execution["pipelineExecution"].get("trigger", {}).get("triggerType")
        if trigger == "StartPipelineExecution":
            return True, f"Running the stage, execution {execution_id} was started by hand."

    previous = last_successful_source(pipeline, exclude=execution_id)
    if previous is None:
        return True, f"Running the stage, {pipeline} has no successful execution to compare with."
    previous_id, previous_bucket, previous_key = previous

    current = files(bucket, key, prefix)
    if not current:
        return True, f"Running the stage, the source holds no files in {where}; is the directory right?"
    before = files(previous_bucket, previous_key, prefix)
    changed = sorted(name for name in current.keys() | before.keys() if current.get(name) != before.get(name))
    if changed:
        listed = ", ".join(changed[:10]) + (f" and {len(changed) - 10} more" if len(changed) > 10 else "")
        return True, f"Running the stage, {len(changed)} files in {where} changed since execution {previous_id}: {listed}"
    return False, f"Skipping the stage, nothing in {where} changed since execution {previous_id}."


def last_successful_source(pipeline, exclude):
    """Source artifact of the newest succeeded execution, as (execution id, bucket, key)."""
    for page in codepipeline.get_paginator("list_pipeline_executions").paginate(pipelineName=pipeline):
        for execution in page["pipelineExecutionSummaries"]:
            if execution["status"] != "Succeeded" or execution["pipelineExecutionId"] == exclude:
                continue
            execution_id = execution["pipelineExecutionId"]
            actions = codepipeline.get_paginator("list_action_executions").paginate(
                pipelineName=pipeline, filter={"pipelineExecutionId": execution_id}
            )
            for actions_page in actions:
                for action in actions_page["actionExecutionDetails"]:
                    artifacts = action.get("output", {}).get("outputArtifacts", [])
                    if action["stageName"] == "Source" and artifacts:
                        location = artifacts[0]["s3location"]
                        return execution_id, location["bucket"], location["key"]
            return None
    return None


def files(bucket, key, prefix):
    """CRC-32 of every file below prefix in the ZIP at s3://bucket/key."""
    body = s3.get_object(Bucket=bucket, Key=key)["Body"].read()
    with zipfile.ZipFile(io.BytesIO(body)) as archive:
        return {
            info.filename: info.CRC
            for info in archive.infolist()
            if info.filename.startswith(prefix) and not info.is_dir()
        }
