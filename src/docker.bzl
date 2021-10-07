# This file is a patched version of code from
#   - https://github.com/bazelbuild/rules_docker/blob/280b6e6cfbaaaedad169bd846abe9903c59b35e3/lang/image.bzl
#   - https://github.com/bazelbuild/rules_docker/blob/280b6e6cfbaaaedad169bd846abe9903c59b35e3/python/image.bzl
# Code in the open source uses FilterAspectInfo only along `deps` attributes. Logic in this patch
# makes it working for all attributes.

# TODO Implement this change in https://github.com/bazelbuild/rules_docker, and remove this file with the patch.

load(
    "@io_bazel_rules_docker//container:providers.bzl",
    "FilterAspectInfo",
    "FilterLayerInfo",
)

def _get_targets(arr):
    return [e for e in arr if type(e) in ["Target"]]

def _filter_aspect_impl(target, ctx):
    if FilterLayerInfo in target:
        # If the aspect propagated along the "deps" attr to another filter layer,
        # then take the filtered depset instead of descending further.
        return [FilterAspectInfo(depset = target[FilterLayerInfo].filtered_depset)]

    # Collect transitive deps from all children.
    children = _get_targets([getattr(ctx.rule.attr, attr) for attr in dir(ctx.rule.attr)])
    for attr in dir(ctx.rule.attr):
        val = getattr(ctx.rule.attr, attr)
        if type(val) == "list":
            children.extend(_get_targets(val))
    target_deps = depset(transitive = [dep[FilterAspectInfo].depset for dep in children if FilterAspectInfo in dep])
    myself = struct(target = target, target_deps = target_deps)
    return [
        FilterAspectInfo(
            depset = depset(direct = [myself], transitive = [target_deps]),
        ),
    ]

_filter_aspect = aspect(
    attr_aspects = ["*"],
    implementation = _filter_aspect_impl,
)

def _filter_layer_rule_impl(ctx):
    transitive_deps = ctx.attr.dep[FilterAspectInfo].depset
    runfiles = ctx.runfiles()
    filtered_depsets = []
    for dep in transitive_deps.to_list():
        if str(dep.target.label).startswith(ctx.attr.filter) and str(dep.target.label) != str(ctx.attr.dep.label):
            runfiles = runfiles.merge(dep.target[DefaultInfo].default_runfiles)
            filtered_depsets.append(dep.target_deps)

    return [
        FilterLayerInfo(
            runfiles = runfiles,
            filtered_depset = depset(transitive = filtered_depsets),
        ),
    ] + ([ctx.attr.dep[PyInfo]] if PyInfo in ctx.attr.dep else [])

filter_layer = rule(
    attrs = {
        "dep": attr.label(
            aspects = [_filter_aspect],
            mandatory = True,
        ),
        # Include in this layer only transitive dependencies whose label starts with "filter".
        # For example, set filter="@" to include only external dependencies.
        "filter": attr.string(default = ""),
    },
    implementation = _filter_layer_rule_impl,
)

def py_layer(name, deps, filter = "", **kwargs):
    binary_name = name + ".layer-binary"
    native.py_library(name = binary_name, deps = deps, **kwargs)
    filter_layer(name = name, dep = binary_name, filter = filter, tags = kwargs.get("tags", []))