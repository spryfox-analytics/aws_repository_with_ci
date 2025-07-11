locals {
  camel_cased_repository_path = replace(
    title(
      regexreplace(
        var.gitlab_repository_path,
        "[/\\-_]+",    # match one or more of slash, backslash, dash or underscore
        " "            # replace them all with a single space
      )
    ),
    " ",             # now remove the spaces
    ""
  )
  dashed_repository_path = replace(
      regexreplace(
        var.gitlab_repository_path,
        "[/\\-_]+",    # match one or more of slash, backslash, dash or underscore
        "-"            # replace them all with a single space
      ),
    " ",             # now remove the spaces
    ""
  )
}
