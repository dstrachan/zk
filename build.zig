const std = @import("std");

const semantic_version: std.SemanticVersion = .{ .major = 0, .minor = 1, .patch = 0 };

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const version = try getVersion(b);
    const options = b.addOptions();
    options.addOption(std.SemanticVersion, "version", try .parse(version));
    options.addOption([:0]const u8, "version_string", try b.allocator.dupeSentinel(u8, version, 0));

    const exe = b.addExecutable(.{
        .name = "zk",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    exe.root_module.addOptions("build_options", options);

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const test_filters = b.option(
        []const []const u8,
        "test-filter",
        "Skip tests that do not match any filter",
    ) orelse &.{};

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
        .filters = test_filters,
    });

    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_exe_tests.step);
}

fn getVersion(b: *std.Build) ![]const u8 {
    if (!std.process.can_spawn) {
        std.debug.print("error: version info cannot be retrieved from git.\n", .{});
        std.process.exit(1);
    }
    const version_string = b.fmt("{d}.{d}.{d}", .{ semantic_version.major, semantic_version.minor, semantic_version.patch });

    var code: u8 = undefined;
    const git_describe_untrimmed = b.runAllowFail(&[_][]const u8{
        "git",
        "-C", b.build_root.path orelse ".", // affects the --git-dir argument
        "--git-dir", ".git", // affected by the -C argument
        "describe", "--match",    "*.*.*", //
        "--tags",   "--abbrev=9",
    }, &code, .ignore) catch {
        return version_string;
    };
    const git_describe = std.mem.trim(u8, git_describe_untrimmed, " \n\r");

    switch (std.mem.countScalar(u8, git_describe, '-')) {
        0 => {
            // Tagged release version (e.g. 0.10.0).
            if (!std.mem.eql(u8, git_describe, version_string)) {
                std.debug.print("version '{s}' does not match Git tag '{s}'\n", .{ version_string, git_describe });
                std.process.exit(1);
            }
            return version_string;
        },
        2 => {
            // Untagged development build (e.g. 0.10.0-dev.2025+ecf0050a9).
            var it = std.mem.splitScalar(u8, git_describe, '-');
            const tagged_ancestor = it.first();
            const commit_height = it.next().?;
            const commit_id = it.next().?;

            const ancestor_ver = try std.SemanticVersion.parse(tagged_ancestor);
            if (semantic_version.order(ancestor_ver) != .gt) {
                std.debug.print("version '{f}' must be greater than tagged ancestor '{f}'\n", .{ semantic_version, ancestor_ver });
                std.process.exit(1);
            }

            // Check that the commit hash is prefixed with a 'g' (a Git convention).
            if (commit_id.len < 1 or commit_id[0] != 'g') {
                std.debug.print("Unexpected `git describe` output: {s}\n", .{git_describe});
                return version_string;
            }

            // The version is reformatted in accordance with the https://semver.org specification.
            return b.fmt("{s}-dev.{s}+{s}", .{ version_string, commit_height, commit_id[1..] });
        },
        else => {
            std.debug.print("Unexpected `git describe` output: {s}\n", .{git_describe});
            return version_string;
        },
    }
}
