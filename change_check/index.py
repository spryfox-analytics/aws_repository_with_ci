"""Rule of the stage conditions: lets a stage run only if the pipeline's directories changed.

The rule passes (the stage runs) when a file below the directory, or below one of the additional
directories, differs from the source of the pipeline's last successful execution, and fails (the
stage is skipped) when nothing there changed. Files are compared by name and CRC-32 from the ZIP's
central directory, so nothing is extracted.

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
    directories = relevant_directories(parameters)
    prefixes = [f"{directory}/" for directory in directories] or [""]
    where = ", ".join(prefixes) if directories else "the repository"

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

    current = files(bucket, key, prefixes)
    if not current:
        return True, f"Running the stage, the source holds no files in {where}; are the directories right?"
    empty = [prefix for prefix in prefixes if not any(name.startswith(prefix) for name in current)]
    note = f" The source holds no files in {', '.join(empty)}; is the directory right?" if empty else ""
    before = files(previous_bucket, previous_key, prefixes)
    changed = changed_files(current, before)
    if changed:
        listed = ", ".join(changed[:10]) + (f" and {len(changed) - 10} more" if len(changed) > 10 else "")
        return True, f"Running the stage, {len(changed)} files in {where} changed since execution {previous_id}: {listed}{note}"
    return False, f"Skipping the stage, nothing in {where} changed since execution {previous_id}.{note}"


def relevant_directories(parameters):
    """The directory and the additional directories, in order and without duplicates.

    An empty list stands for the whole repository. Without a directory every file counts anyway,
    so additional directories add nothing and are ignored.
    """
    directory = parameters.get("directory") or ""
    if not directory:
        return []
    directories = [directory] + list(parameters.get("additional_directories") or [])
    return list(dict.fromkeys(d.strip("/") for d in directories if d and d.strip("/")))


def changed_files(current, before):
    """Names of the files that were added, removed or changed between two file listings."""
    return sorted(name for name in current.keys() | before.keys() if current.get(name) != before.get(name))


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


def files(bucket, key, prefixes):
    """CRC-32 of every file below one of the prefixes in the ZIP at s3://bucket/key."""
    body = s3.get_object(Bucket=bucket, Key=key)["Body"].read()
    return listing(body, prefixes)


def listing(body, prefixes):
    """CRC-32 of every file below one of the prefixes in the ZIP archive body."""
    with zipfile.ZipFile(io.BytesIO(body)) as archive:
        return {
            info.filename: info.CRC
            for info in archive.infolist()
            if not info.is_dir() and info.filename.startswith(tuple(prefixes))
        }
