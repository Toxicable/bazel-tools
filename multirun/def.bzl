load("@bazel_skylib//lib:shell.bzl", "shell")

_CONTENT_PREFIX = """#!/usr/bin/env bash

# --- begin runfiles.bash initialization v2 ---
# Copy-pasted from the Bazel Bash runfiles library v2.
set -uo pipefail; f=bazel_tools/tools/bash/runfiles/runfiles.bash
source "${RUNFILES_DIR:-/dev/null}/$f" 2>/dev/null || \\
 source "$(grep -sm1 "^$f " "${RUNFILES_MANIFEST_FILE:-/dev/null}" | cut -f2- -d' ')" 2>/dev/null || \\
 source "$0.runfiles/$f" 2>/dev/null || \\
 source "$(grep -sm1 "^$f " "$0.runfiles_manifest" | cut -f2- -d' ')" 2>/dev/null || \\
 source "$(grep -sm1 "^$f " "$0.exe.runfiles_manifest" | cut -f2- -d' ')" 2>/dev/null || \\
 { echo>&2 "ERROR: cannot find $f"; exit 1; }; f=; set -e
# --- end runfiles.bash initialization v2 ---

# Export RUNFILES_* envvars (and a couple more) for subprocesses.
runfiles_export_envvars

"""

def _multirun_impl(ctx):
    instructions_file = ctx.actions.declare_file(ctx.label.name + ".json")
    runfiles = ctx.runfiles(files = [instructions_file])
    runfiles = runfiles.merge(ctx.attr._bash_runfiles[DefaultInfo].default_runfiles)
    runnerInfo = ctx.attr._runner[DefaultInfo]
    runfiles = runfiles.merge(runnerInfo.default_runfiles)

    commands = []
    tagged_commands = []
    for command in ctx.attr.commands:
        tagged_commands.append(struct(tag = str(command.label), command = command))

    for command, label in ctx.attr.tagged_commands.items():
        tagged_commands.append(struct(tag = label, command = command))

    for tag_command in tagged_commands:
        command = tag_command.command
        tag = tag_command.tag

        defaultInfo = command[DefaultInfo]
        if defaultInfo.files_to_run == None:
            fail("%s is not executable" % command.label, attr = "commands")
        exe = defaultInfo.files_to_run.executable
        if exe == None:
            fail("%s does not have an executable file" % command.label, attr = "commands")

        default_runfiles = defaultInfo.default_runfiles
        if default_runfiles != None:
            runfiles = runfiles.merge(default_runfiles)
        commands.append(struct(
            tag = tag,
            path = exe.short_path,
        ))
    instructions = struct(
        commands = commands,
        parallel = ctx.attr.parallel,
    )
    ctx.actions.write(
        output = instructions_file,
        content = instructions.to_json(),
    )

    script = 'exec ./%s -f %s "$@"\n' % (shell.quote(runnerInfo.files_to_run.executable.short_path), shell.quote(instructions_file.short_path))
    out_file = ctx.actions.declare_file(ctx.label.name + ".bash")
    ctx.actions.write(
        output = out_file,
        content = _CONTENT_PREFIX + script,
        is_executable = True,
    )
    return [DefaultInfo(
        files = depset([out_file]),
        runfiles = runfiles,
        executable = out_file,
    )]

_multirun = rule(
    implementation = _multirun_impl,
    attrs = {
        "commands": attr.label_list(
            allow_empty = True,  # this is explicitly allowed - generated invocations may need to run 0 targets
            mandatory = False,
            allow_files = True,
            doc = "Targets to run",
            cfg = "target",
        ),
        "tagged_commands": attr.label_keyed_string_dict(
            allow_empty = True,  # this is explicitly allowed - generated invocations may need to run 0 targets
            mandatory = False,
            allow_files = True,
            doc = "Labeled targets to run",
            cfg = "target",
        ),
        "parallel": attr.bool(default = False, doc = "If true, targets will be run in parallel, not in the specified order"),
        "_bash_runfiles": attr.label(
            default = Label("@bazel_tools//tools/bash/runfiles"),
        ),
        "_runner": attr.label(
            default = Label("@com_github_atlassian_bazel_tools//multirun"),
            cfg = "host",
            executable = True,
        ),
    },
    executable = True,
)

def multirun(**kwargs):
    tags = kwargs.get("tags", [])
    if "manual" not in tags:
        tags.append("manual")
        kwargs["tags"] = tags
    _multirun(
        **kwargs
    )

def _command_impl(ctx):
    runfiles = ctx.runfiles().merge(ctx.attr._bash_runfiles[DefaultInfo].default_runfiles)

    defaultInfo = ctx.attr.command[DefaultInfo]

    default_runfiles = defaultInfo.default_runfiles
    if default_runfiles != None:
        runfiles = runfiles.merge(default_runfiles)

    str_env = [
        "%s=%s" % (k, shell.quote(v))
        for k, v in ctx.attr.environment.items()
    ]
    str_unqouted_env = [
        "%s=%s" % (k, v)
        for k, v in ctx.attr.raw_environment.items()
    ]
    str_args = [
        "%s" % shell.quote(v)
        for v in ctx.attr.arguments
    ]
    command_elements = ["exec env"] + \
                       str_env + \
                       str_unqouted_env + \
                       ["./%s" % shell.quote(defaultInfo.files_to_run.executable.short_path)] + \
                       str_args + \
                       ['"$@"\n']

    out_file = ctx.actions.declare_file(ctx.label.name + ".bash")
    ctx.actions.write(
        output = out_file,
        content = _CONTENT_PREFIX + " ".join(command_elements),
        is_executable = True,
    )
    return [DefaultInfo(
        files = depset([out_file]),
        runfiles = runfiles,
        executable = out_file,
    )]

_command = rule(
    implementation = _command_impl,
    attrs = {
        "arguments": attr.string_list(
            doc = "List of command line arguments",
        ),
        "environment": attr.string_dict(
            doc = "Dictionary of environment variables",
        ),
        "raw_environment": attr.string_dict(
            doc = "Dictionary of unqouted environment variables",
        ),
        "command": attr.label(
            mandatory = True,
            allow_files = True,
            executable = True,
            doc = "Target to run",
            cfg = "target",
        ),
        "_bash_runfiles": attr.label(
            default = Label("@bazel_tools//tools/bash/runfiles"),
        ),
    },
    executable = True,
)

def command(**kwargs):
    tags = kwargs.get("tags", [])
    if "manual" not in tags:
        tags.append("manual")
        kwargs["tags"] = tags
    _command(
        **kwargs
    )
