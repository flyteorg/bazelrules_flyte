"""
Python script to register a workflow.
This script will first check if the workflow has previously been registered and exit gracefully if so.
If not it will attempt to register the workflow with FlyteAdmin.
"""
import os
import subprocess
import sys
from src.common.util import find_runfiles

try:
    WF_PROJECT = os.environ["WF_PROJECT_NAME"]
    WF_DOMAIN = os.environ["WF_DOMAIN"]
    WF_PACKAGES = os.environ["WF_PACKAGES"]
    WF_MAIN = os.environ["WF_MAIN"]
    WF_NAME = os.environ["WF_NAME"]
    VERSION = os.environ["VERSION"]
    KUBERNETES_SERVICE_ACCOUNT = os.environ["KUBERNETES_SERVICE_ACCOUNT"]
except KeyError as e:
    raise RuntimeError("Environment variable {} not specified".format(e))
TEMP_PB_PATH = "/tmp/_pb_output"
LAUNCH_PLAN_NAME = ".".join([WF_PACKAGES, WF_MAIN, WF_NAME])
CONFIG_PATH = "/app/flytekit.config"
FLYTE_ADMIN_HOST = "<replace_me>"

SERIALIZE_AND_REGISTER_WORKFLOW_CMD = "mkdir {} || true && {} -c {} serialize workflows -f /tmp/_pb_output \
    && {} register-files -h {} -p {} -d {} -v {} --kubernetes-service-account {} {}/*".format(
    TEMP_PB_PATH,
    find_runfiles.rlocation('src/backend/workflow_engine/wfe_bazel_rules/pyflyte'),
    CONFIG_PATH,
    find_runfiles.rlocation('src/backend/workflow_engine/wfe_bazel_rules/flyte-cli'),
    FLYTE_ADMIN_HOST,
    WF_PROJECT,
    WF_DOMAIN,
    VERSION,
    KUBERNETES_SERVICE_ACCOUNT,
    TEMP_PB_PATH)


FETCH_LAUNCH_PLAN_VERSION_CMD = "{} -p {} -d {} -h {} list-launch-plan-versions -n {} -l 1000".format(
    find_runfiles.rlocation('src/flyte-cli'),
    WF_PROJECT,
    WF_DOMAIN,
    FLYTE_ADMIN_HOST,
    LAUNCH_PLAN_NAME)


def run_command(cmd):
    try:
        print("Running: {}".format(cmd))
        out = subprocess.check_output(cmd, shell=True).decode('utf-8')
    except subprocess.CalledProcessError as e:
        print("FLYTE BAZEL RULE ERROR: {}, error message: {}".format(e.returncode, e.output))
        sys.exit(1)

    return out


if __name__ == "__main__":
    res = run_command(FETCH_LAUNCH_PLAN_VERSION_CMD)
    if VERSION not in res:
        run_command(SERIALIZE_AND_REGISTER_WORKFLOW_CMD)

    print("INFO: Successfully registered")
    sys.exit()