package(default_visibility = ["//visibility:public"])

load(":flyte.bzl", "check_unstaged_commits", "genrule_py_main")
load("//pyreqs:requirements_py3.bzl", requirement3 = "requirement")

exports_files([
    "flytekit.config",
    "relay.py.tpl",
])

py_binary(
    name = "py_register",
    srcs = [
        "register.py",
    ],
    main = "register.py",
    deps = [
        ":flyte-cli",
        ":pyflyte",
        ":pyflyte-execute",
        ":pyflyte-map-execute",
        # We'll need a runfiles utility
        # "//:find_runfiles",
    ],
)

genrule_py_main(
    name = "pyflyte_src",
    main = "main",
    package = "flytekit.clis.sdk_in_container.pyflyte",
    template = "relay.py.tpl",
)

py_binary(
    name = "pyflyte",
    srcs = [":pyflyte_src"],
    main = "pyflyte_src.py",
    deps = [requirement3("flytekit")],
)

genrule_py_main(
    name = "flyte-cli_src",
    main = "_flyte_cli",
    package = "flytekit.clis.flyte_cli.main",
    template = "relay.py.tpl",
)

py_binary(
    name = "flyte-cli",
    srcs = [":flyte-cli_src"],
    main = "flyte-cli_src.py",
    deps = [requirement3("flytekit")],
)

genrule_py_main(
    name = "pyflyte-execute_src",
    main = "execute_task_cmd",
    package = "flytekit.bin.entrypoint",
    template = "relay.py.tpl",
)

py_binary(
    name = "pyflyte-execute",
    srcs = [":pyflyte-execute_src"],
    main = "pyflyte-execute_src.py",
    deps = [requirement3("flytekit")],
)

genrule_py_main(
    name = "pyflyte-map-execute_src",
    main = "map_execute_task_cmd",
    package = "flytekit.bin.entrypoint",
    template = "relay.py.tpl",
)

py_binary(
    name = "pyflyte-map-execute",
    srcs = [":pyflyte-map-execute_src"],
    main = "pyflyte-map-execute_src.py",
    deps = [requirement3("flytekit")],
)

# This provides us information about the current git sha and
# whether there are any unstaged commits.
genrule(
    name = "git_sha",
    outs = ["workspace.out"],
    cmd = """echo '
#!/bin/bash
VERSION='"$$(cat bazel-out/*-status.txt | grep STABLE_GIT_COMMIT | awk \'{print $$2}\')"'
HAS_CHANGES='"$$(cat bazel-out/*-status.txt | grep STABLE_GIT_NUM_FILES_CHANGED | awk \'{print $$2}\')"'
        ' > $(location workspace.out)""",
    stamp = 1,
)

check_unstaged_commits(
    name = "check",
    tags = ["manual"],
    version = ":git_sha",
)