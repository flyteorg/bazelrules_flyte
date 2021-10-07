## Flyte Bazel Rules

#### Example of how to use the workflow

```
    workflow(
        name = <my_bazel_rule_name>,
        srcs = [<my_workflow_py_binary_target>],
        main = <my_worklow_python_file>,
        wf_name = <name_of_my_workflow_function_name>,
        wf_packages = <python_path_to_my_workflow>,
        wf_project = <my_worflow_project_name>,
    )
```