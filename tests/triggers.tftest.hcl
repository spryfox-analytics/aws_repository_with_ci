mock_provider "aws" {
  source = "./tests/mocks"
}

variables {
  name = "my-service"
  source_repository = {
    connection_arn = "arn:aws:codeconnections:eu-west-1:111111111111:connection/00000000-0000-0000-0000-000000000000"
    repository_id  = "my-group/monorepo"
  }
}

run "no_file_path_filter_by_default" {
  command = apply

  assert {
    condition     = length(aws_codepipeline.this.trigger[0].git_configuration[0].push[0].file_paths) == 0
    error_message = "Without file_paths every push to the branch must start the pipeline."
  }
}

run "file_paths_filter_pushes_and_pull_requests" {
  command = apply
  variables {
    triggers = {
      pull_request_branches = ["main"]
      file_paths            = ["my-service/**"]
      file_paths_excluded   = ["**/*.md"]
    }
  }

  assert {
    condition     = aws_codepipeline.this.trigger[0].git_configuration[0].push[0].file_paths[0].includes == tolist(["my-service/**"])
    error_message = "Pushes must be filtered by file_paths."
  }
  assert {
    condition     = aws_codepipeline.this.trigger[0].git_configuration[0].push[0].file_paths[0].excludes == tolist(["**/*.md"])
    error_message = "Pushes must leave out file_paths_excluded."
  }
  assert {
    condition     = aws_codepipeline.this.trigger[0].git_configuration[0].pull_request[0].file_paths[0].includes == tolist(["my-service/**"])
    error_message = "Pull requests must be filtered by file_paths."
  }
  assert {
    condition     = aws_codepipeline.this.trigger[0].git_configuration[0].push[0].branches[0].includes == tolist(["main"])
    error_message = "The branch filter must stay in place next to the file paths."
  }
}

run "excludes_alone_leave_includes_out" {
  command = apply
  variables {
    triggers = {
      file_paths_excluded = ["docs/**"]
    }
  }

  assert {
    condition     = aws_codepipeline.this.trigger[0].git_configuration[0].push[0].file_paths[0].includes == null
    error_message = "An empty include list must be left out, CodePipeline rejects it."
  }
}

run "directory_scopes_triggers_buildspecs_and_builds" {
  command = apply
  variables {
    source_repository = {
      connection_arn = "arn:aws:codeconnections:eu-west-1:111111111111:connection/00000000-0000-0000-0000-000000000000"
      repository_id  = "my-group/monorepo"
      directory      = "services/my-service"
    }
    actions = [
      { name = "build" },
      { name = "inline", buildspec = "version: 0.2\nphases: {}\n" },
    ]
  }

  assert {
    condition     = aws_codepipeline.this.trigger[0].git_configuration[0].push[0].file_paths[0].includes == tolist(["services/my-service/**"])
    error_message = "A directory must limit the trigger to its files."
  }
  assert {
    condition     = aws_codebuild_project.this["build"].source[0].buildspec == "services/my-service/buildspec.yml"
    error_message = "Buildspec files must be looked up in the directory."
  }
  assert {
    condition     = aws_codebuild_project.this["inline"].source[0].buildspec == "version: 0.2\nphases: {}\n"
    error_message = "An inline buildspec must stay as it is."
  }
  assert {
    condition     = contains([for v in aws_codebuild_project.this["build"].environment[0].environment_variable : "${v.name}=${v.value}"], "SOURCE_DIRECTORY=services/my-service")
    error_message = "Builds must get the directory as SOURCE_DIRECTORY."
  }
}

run "file_paths_override_the_directory" {
  command = apply
  variables {
    source_repository = {
      connection_arn = "arn:aws:codeconnections:eu-west-1:111111111111:connection/00000000-0000-0000-0000-000000000000"
      repository_id  = "my-group/monorepo"
      directory      = "my-service"
    }
    triggers = {
      file_paths = ["my-service/**", "shared/**"]
    }
  }

  assert {
    condition     = aws_codepipeline.this.trigger[0].git_configuration[0].push[0].file_paths[0].includes == tolist(["my-service/**", "shared/**"])
    error_message = "Explicit file_paths must replace the directory default."
  }
}
