load(
    "add_tags",
    "ci_container_push",
    "container_image",
    "container_push",
    "py3_image",
)
load(
    "//src:docker.bzl",
    "py_layer",
)
load(
    "generate_artifact_metadata",
)

FLYTE_ADMIN_HOST = "<place_holder>"

FLYTE_DOMAINS = [
    "development",
    "production",
]

TEMPLATE = "//src:flytekit.config"

FLYTE_BASE = "<base-image>"

FLYTE_SPARK_BASE = "<spark-base-image>"

FLYTEKIT_CONFIG = "flytekit.config"

DOCKER_REGISTRY = "<docker-registry-endpoint>"

REPOSITORY_PREFIX = "<path for docker registry>"

# Target that checks if there are any unstaged commit and forces user to commit changes
CHECK_UNSTAGED_COMMITS_TARGET = "//src:check"

# Target to fetch git sha to be used as version
GIT_SHA_TARGET = "//src:git_sha"

PY_REGISTER_TARGET = "//src:py_register"

# command that checks whether exit code is 1 and then parses error message for already exists
_PYFLYTE_REGISTER_WF = """
EXPECTED="INFO: Successfully registered" && \
OUTPUT=$(docker run --rm -i --entrypoint {runfiles_dir}/src/workflow_rule/py_register {image_tag}) || true && \
if [[ $OUTPUT != *$EXPECTED* ]]; then echo ERROR: $OUTPUT && exit 1; else echo $EXPECTED | tee {output_path}; fi;
"""

def _get_kubernetes_service_account(wf_project, wf_domain):
    return "{}-{}".format(wf_project, wf_domain)

def _get_workflow_domain(ctx):
    pass

def _flyte_config_impl(ctx):
    prefix = ctx.label.name + "/"
    wf_domain = _get_workflow_domain(ctx)
    wf_project = ctx.attr.wf_project
    kubernetes_service_account = _get_kubernetes_service_account(wf_project, wf_domain)

    config = ctx.actions.declare_file(prefix + FLYTEKIT_CONFIG)
    ctx.actions.expand_template(
        template = ctx.file.template,
        output = config,
        substitutions = {
            "{wf_packages}": ",".join([ctx.attr.wf_packages] + ctx.attr.extra_wf_packages),
            "{wf_project}": wf_project,
            "{wf_domain}": wf_domain,
            "{kubernetes_service_account}": kubernetes_service_account,
        },
    )
    return DefaultInfo(files = depset([config]))

_flyte_config_rule = rule(
    attrs = {
        "wf_packages": attr.string(mandatory = True),
        "wf_project": attr.string(mandatory = True),
        "template": attr.label(
            mandatory = True,
            allow_single_file = True,
        ),
        "extra_wf_packages": attr.string_list(
            mandatory = False,
            default = [],
        ),
        "publish_branch": attr.string(mandatory = True),
    },
    implementation = _flyte_config_impl,
)

def _flyte_config(name, wf_project, wf_packages, extra_wf_packages, publish_branch):
    """Generates a flyte config file for the workflow.
    Args:
    name: name of the target
    wf_project: flyte project to use
    wf_domain: flyte domain to register to
    wf_packages: python path where the workflow is defined
    extra_wf_packages: other python paths that are included in the wf
    """

    _flyte_config_rule(
        name = name,
        wf_packages = wf_packages,
        wf_project = wf_project,
        template = TEMPLATE,
        publish_branch = publish_branch,
        extra_wf_packages = extra_wf_packages,
    )
    return name

def _check_unstaged_commits_impl(ctx):
    cmd = """HAS_CHANGES=$(cat {in_file} | grep HAS_CHANGES | awk -F "=" '{{print $2}}') && \
    if [ $HAS_CHANGES != 0 ]; then echo ERROR: Can not build workflow, Please commit your changes && exit 1; \
    else echo Good to go; fi;""".format(in_file = ctx.file.version.path)
    ctx.actions.run_shell(
        inputs = [ctx.file.version, ctx.info_file, ctx.version_file],
        outputs = [ctx.outputs.out],
        command = "{command} > {output_path}".format(
            command = cmd,
            output_path = ctx.outputs.out.path,
        ),
    )
    return [DefaultInfo(files = depset([ctx.outputs.out]))]

check_unstaged_commits = rule(
    attrs = {
        "version": attr.label(allow_single_file = True),
    },
    outputs = {"out": "%{name}.out"},
    implementation = _check_unstaged_commits_impl,
)

def _execute_on_build_impl(ctx):
    cmd = "{target_path} {args} > {ouput_path}".format(
        target_path = ctx.executable.target.path,
        args = " ".join(ctx.attr.args),
        ouput_path = ctx.outputs.out.path,
    )
    ctx.actions.run_shell(
        tools = [ctx.executable.target],
        outputs = [ctx.outputs.out],
        command = cmd,
    )
    return [DefaultInfo(files = depset([ctx.outputs.out]))]

execute_on_build = rule(
    attrs = {
        "target": attr.label(
            mandatory = True,
            allow_files = True,
            executable = True,
            cfg = "target",
        ),
        "args": attr.string_list(
            mandatory = False,
            default = [],
        ),
    },
    outputs = {"out": "%{name}.out"},
    implementation = _execute_on_build_impl,
)

def _register_flyte_workflow_impl(ctx):
    wf_domain = _get_workflow_domain(ctx)

    # Get the correct runfiles directory
    runfiles_dir = "/".format(
        ctx.attr.binary_image.label.package,
        ctx.attr.binary_image.label.name,
    )

    cmd = _PYFLYTE_REGISTER_WF.format(
        image_tag = "bazel/{}:{}".format(ctx.attr.image.label.package, ctx.attr.image.label.name),
        wf_domain = wf_domain,
        wf_project = ctx.attr.wf_project,
        config = "/app/" + FLYTEKIT_CONFIG,
        output_path = ctx.outputs.out.path,
        runfiles_dir = runfiles_dir,
    )

    ctx.actions.run_shell(
        inputs = [ctx.info_file, ctx.version_file] + ctx.files.deps,
        outputs = [ctx.outputs.out],
        command = cmd,
    )
    return [DefaultInfo(files = depset([ctx.outputs.out]))]

_register_flyte_workflow_rule = rule(
    attrs = {
        "image": attr.label(
            mandatory = True,
            allow_single_file = True,
        ),
        "wf_project": attr.string(
            mandatory = True,
        ),
        "binary_image": attr.label(
            mandatory = True,
        ),
        "deps": attr.label_list(),
        "publish_branch": attr.string(mandatory = True),
    },
    outputs = {"out": "%{name}.out"},
    implementation = _register_flyte_workflow_impl,
)

def register_flyte_workflow(name, image, wf_project, binary_image, publish_branch, deps = None, **kwargs):
    """Registers a workflow with flyte.
    Args:
    name: name of the target
    image: the label of the image to run the registration from
    wf_project: flyte project to use
    wf_domain: flyte domain to register to
    deps: list of dependencies
    **kwargs: common attributes for bazel targets (e.g. tags, visiblity), to be forwarded to all of the macro's targets
    """
    _register_flyte_workflow_rule(
        name = name,
        image = image,
        wf_project = wf_project,
        binary_image = binary_image,
        deps = deps,
        publish_branch = publish_branch,
        **kwargs
    )

def launch_workflow(name, wf_name, wf_main, wf_project, wf_domain, wf_packages, srcs, wf_user = None, **kwargs):
    """Launches current version of the workflow.
    Args:
    name: name of the target
    wf_name: name of the workflow class. e.g RecordsCount
    wf_main: name of the python file where the workflow is defined. e.g. workflow.py
    wf_project: flyte project to use
    wf_domain: flyte domain to register to
    wf_packages: python path to your workflow
    wf_user: user launching this workflow
    **kwargs: common attributes for bazel targets (e.g. tags, visiblity), to be forwarded to all of the macro's targets
    """
    # We'll need to address how to get the current gitsha for VERSION
    native.genrule(
        name = name + "_gen",
        outs = [name],
        # This is included to be used as a dependency. Genrule does not have deps field.
        srcs = srcs,
        # Release build is defined when embed_version is set to true.
        cmd = """echo '
    #!/bin/bash
    FLYTE_FOUNDATION_IMAGE={FLYTE_FOUNDATION_IMAGE}
    WF_DOMAIN={wf_domain}
    WF_PROJECT={wf_project}
    WF_NAME={wf_packages}.{wf_main}.{wf_name}
    echo $$WF_NAME
    VERSION='"$$(cat bazel-out/*-status.txt | grep STABLE_GIT_COMMIT | awk \'{{print $$2}}\')"'
    FLYTEADMIN_HOST=<replace me>
    docker run --rm -i --entrypoint /bin/bash $$FLYTE_FOUNDATION_IMAGE -c "flyte-cli \
    -p $$WF_PROJECT -d $$WF_DOMAIN -h $$FLYTEADMIN_HOST execute-launch-plan -u lp:$$WF_PROJECT:$$WF_DOMAIN:$$WF_NAME:$$VERSION \
    -r {wf_user} -- $$*"
    echo "Execution URL: https://<replace_me>/console/projects/{wf_project}/domains/{wf_domain}/workflows/{wf_packages}.{wf_main}.{wf_name}"
            ' > $(location {name})""".format(
            FLYTE_FOUNDATION_IMAGE = FLYTE_FOUNDATION_IMAGE,
            wf_domain = wf_domain,
            wf_project = wf_project,
            wf_packages = wf_packages,
            wf_main = wf_main,
            wf_name = wf_name,
            wf_user = wf_user,
            name = name,
        ),
        stamp = 1,
        executable = 1,
        **kwargs
    )

def _get_runfiles_dir(wf_packages, image_name):
    return "/app/" + wf_packages.replace(".", "/") + "/" + image_name + ".binary.runfiles"

def _get_flyte_base_image(base = None, spark = False):
    if base:
        return base
    return FLYTE_SPARK_BASE if spark else FLYTE_BASE

def workflow_layered_image(name, wf_py_binary, base, main, **kwargs):
    """Creates a docker image target breaking it into layers. It puts external dependencies 
    and data artifacts to lower layers and tries to keep all the avsoftware code in a top layer.
    It helps to have top layer small (up to 100MB) and rebuild/gzip/publish only it, while 
    lower layers stay mostly static and don't affect build times.
    """

    layers = [
        # fill in layers although this may not be needed and better to fix the container rule to layer appropriately
    ]

    for layer_name, layer_filter in layers:
        py_layer(
            name = name + "_layer_" + layer_name,
            filter = layer_filter,
            deps = [wf_py_binary],
            tags = ["artifact", "no-remote-cache"],
        )

    py3_image(
        name = name,
        srcs = [wf_py_binary],
        base = base,
        # PY_REGISTER_TARGET will add python environment and flyte deps, ~250MB
        layers = [name + "_layer_" + layer_name for layer_name, _ in layers] + [PY_REGISTER_TARGET],
        # The last layer will contain remaining dependencies of `wf_py_binary`, basically just "our" code from avsoftware.
        main = main,
        deps = [],
        **kwargs
    )

def workflow(
        name,
        main,
        wf_py_binary,
        wf_name,
        wf_packages,
        wf_project,
        publish_branch = "master",
        extra_wf_packages = [],
        py_image = None,
        docker_image_max_size = "3.0G",
        spark = False,
        base = None,
        data = None,
        env = {},
        **kwargs):
    """WFE macro to Build, Register, and Launch a Workflow
    Args:
        name: name of the target
        main: name of the python file where the workflow is defined. e.g. workflow.py
        wf_py_binary: py_binary target of your workflow definition. e.g. :my_workflow
        wf_name: name of the workflow class. e.g RecordsCount
        wf_project: flyte project to use
        wf_domain: flyte domain to register to
        wf_packages: python path to your workflow
        publish_branch: specify which branch to allow registering to prod and publishing to Library registry
        extra_wf_packages: extra python paths to packages to include in workflow
        py_image: Optional custom avs_py3_image to use as the base of the image (should be based off of
            the appropriate Flyte base image)
        docker_image_max_size: Max size of the docker image built
        spark: Whether or not workflow uses spark tasks.
        base: User specified base image
        data: Additional data files to be included in docker image
        wf_user: user launching this workflow
        env: additional environment variables to be added to the final workflow image.
        **kwargs: common attributes for bazel targets (e.g. tags, visibility), to be forwarded to all of the macro's targets
    """

    # We explicitly throw an error here if users provide bad attributes that this macro does not support
    # https://docs.bazel.build/versions/master/be/common-definitions.html#common-attributes
    if "deps" in kwargs:
        fail("avs_workflow does not accept a `deps` attribute as **kwargs")
    if "data" in kwargs:
        fail("avs_workflow does not accept a `data` attribute as **kwargs")

    # Add manual to tags to not build during CI
    kwargs["tags"] = kwargs["tags"] if "manual" in kwargs.get("tags", []) else kwargs.get("tags", []) + ["manual"]

    check_if_release_and_publish_branch = "check_if_publish_branch_%s" % name
    native.config_setting(
        name = check_if_release_and_publish_branch,
        values = {"define": "BRANCH=%s" % publish_branch},
    )

    # If a custom py_image is not passed in, then we construct one from the given wf_py_binary
    if not py_image:
        avs_workflow_layered_image(
            name = "py_" + name,
            wf_py_binary = wf_py_binary,
            base = _get_flyte_base_image(base, spark),
            main = main,
            **kwargs
        )
    binary_image = "py_" + name if not py_image else py_image.replace(":", "")

    runfiles_dir = _get_runfiles_dir(wf_packages, binary_image)
    wf_main = main.replace(".py", "")

    # Append flyte config to workflow
    config = _avs_flyte_config("config" + name, wf_project, wf_packages, extra_wf_packages, publish_branch)
    data = data if data else []
    data.append(":" + config)

    # set entrypoint for workflow image depending on whether workflow uses spark or not
    entrypoint = "replace me with entrypoint"
    image_path = REPOSITORY_PREFIX + "/" + wf_project + "/" + name.lower()
    image = name + "_image"
    env_vars = {
        "DOCKER_RUNFILES_PATH": runfiles_dir,
        "RUNFILES_DIR": runfiles_dir,
        "WF_PROJECT_NAME": wf_project,
        "WF_MAIN": wf_main,
        "WF_NAME": wf_name,
        "WF_PACKAGES": wf_packages,
        "BUILD_TIME_UTC": "{BUILD_TIME_UTC}",
        "STABLE_GIT_COMMIT": "{STABLE_GIT_COMMIT}",
        "VERSION": "{STABLE_GIT_COMMIT}",
        "DOCKER_IMAGE": image_path,
        "LANG": "C.UTF-8",
        "LC_ALL": "C.UTF-8",
        "PORT": "80",
        "USE_AUTH": "false",
        "PYSPARK_PYTHON": runfiles_dir + "/python3_8/usr/bin/python3.8",
        "SPARK_VERSION": "3.0.1",
        "FLYTE_PROJECT_NAME": "avexampleworkflows",
        "IMAGE_VERSION": "foo",
    }

    # Starlark won't allow us to do this inline at the select in avs_container_image
    # or else it will appear as none so we do this beforehand and pick which set of env
    # variables to use based off the environment
    env_vars.update(env)
    prod_env = {
        "FLYTE_INTERNAL_IMAGE": LIBRARY_DOCKER_REGISTRY + "/" + image_path + ":{STABLE_GIT_COMMIT}",
        "WF_DOMAIN": "prod",
        "KUBERNETES_SERVICE_ACCOUNT": _get_kubernetes_service_account(wf_project, "prod"),
    }
    prod_env.update(env_vars)

    dev_env = {
        "FLYTE_INTERNAL_IMAGE": EPHEMERAL_DOCKER_REGISTRY + "/" + image_path + ":{STABLE_GIT_COMMIT}",
        "WF_DOMAIN": "dev",
        "KUBERNETES_SERVICE_ACCOUNT": _get_kubernetes_service_account(wf_project, "dev"),
    }
    dev_env.update(env_vars)

    container_image(
        name = image,
        base = binary_image,
        directory = "/app/",
        entrypoint = [entrypoint],
        workdir = "/opt/spark/work-dir",
        cmd = None,
        env = select({
            check_if_release_and_publish_branch: prod_env,
            "//conditions:default": dev_env,
        }),
        files = data,
        stamp = True,
        symlinks = {
            "/usr/local/bin/pyflyte-execute": runfiles_dir + "/src/workflow_rule/pyflyte-execute",
            "/usr/local/bin/pyflyte-map-execute": runfiles_dir + "/src/workflow_rule/pyflyte-map-execute",
        },
        **kwargs
    )

    container_push(
        name = "push_" + name,
        format = "Docker",
        image = ":" + image,
        registry = DOCKER_REGISTRY,
        repository = image_path,
        tag = "{STABLE_GIT_COMMIT}",
        **kwargs
    )

    # Forces the actual container to be published to the registry when running 
    # bazel build
    execute_on_build(
        name = "push_on_build_" + name,
        target = ":push_" + name,
        **kwargs
    )

    execute_on_build(
        name = "load_" + name,
        target = ":" + name + "_image",
        args = ["--norun"],
        **kwargs
    )

    register_flyte_workflow(
        name = "register_" + name,
        image = ":" + image,
        wf_project = wf_project,
        binary_image = binary_image,
        publish_branch = publish_branch,
        deps = [
            GIT_SHA_TARGET,
            CHECK_UNSTAGED_COMMITS_TARGET,
            ":push_on_build_" + name,
            ":load_" + name,
        ],
        **kwargs
    )

    launch_workflow(
        name = name,
        wf_name = wf_name,
        wf_main = wf_main,
        wf_domain = "dev",
        wf_project = wf_project,
        wf_packages = wf_packages,
        srcs = ["register_" + name],
        **kwargs
    )

def _genrule_py_main_impl(ctx):
    out = ctx.actions.declare_file(ctx.label.name + ".py")
    ctx.actions.expand_template(
        output = out,
        template = ctx.file.template,
        substitutions = {
            "{PACKAGE}": ctx.attr.package,
            "{MAIN}": ctx.attr.main,
        },
    )
    return [DefaultInfo(files = depset([out]))]

genrule_py_main = rule(
    attrs = {
        "package": attr.string(mandatory = True),
        "main": attr.string(mandatory = True),
        "template": attr.label(
            allow_single_file = [".py.tpl"],
            mandatory = True,
        ),
    },
    implementation = _genrule_py_main_impl,
)