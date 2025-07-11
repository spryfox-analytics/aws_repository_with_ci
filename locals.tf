locals {
  repository_pat_parts = split("/", var.gitlab_repository_path)
  trimmed_repository_path    = element(local.repository_pat_parts, length(local.repository_pat_parts) - 1)
  normalized_repository_path = replace(
    replace(
      replace(local.trimmed_repository_path, "/", " "),
      "-", " "),
    "_", " ")
  titleized_repository_path = title(local.normalized_repository_path)
  camel_cased_repository_path = replace(local.titleized_repository_path, " ", "")
  dashed_repository_path = replace(local.normalized_repository_path, " ", "-")
}
