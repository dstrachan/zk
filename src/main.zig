const std = @import("std");
const builtin = @import("builtin");
const Io = std.Io;
const Allocator = std.mem.Allocator;

const build_options = @import("build_options");

const zk = @import("root.zig");
const Ast = zk.Ast;
const Vm = zk.Vm;

var stdin_buffer: [4096]u8 align(std.heap.page_size_min) = undefined;
var stdout_buffer: [4096]u8 align(std.heap.page_size_min) = undefined;

const usage =
    \\Usage: zk [file] [options]
    \\
    \\Commands:
    \\
    \\Options:
    \\
    \\  -h, --help Print command-specific usage
    \\
;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;
    const arena = init.arena.allocator();

    const args = try init.minimal.args.toSlice(arena);

    const environ_map = init.environ_map;

    return mainArgs(io, gpa, arena, args, environ_map);
}

fn mainArgs(
    io: Io,
    gpa: Allocator,
    arena: Allocator,
    args: []const []const u8,
    envion_map: *std.process.Environ.Map,
) !void {
    _ = arena; // autofix
    _ = envion_map; // autofix
    if (args.len < 2) return cmdRepl(io, gpa, &.{});

    const cmd = args[1];
    const cmd_args = args[2..];
    if (std.mem.eql(u8, cmd, "help") or std.mem.eql(u8, cmd, "-h") or std.mem.eql(u8, cmd, "--help")) {
        try Io.File.stdout().writeStreamingAll(io, usage);
    } else return cmdFile(io, gpa, cmd, cmd_args);
}

const usage_file =
    \\Usage: zk <file> [options]
    \\
    \\  Run a k file.
    \\
    \\Options:
    \\
    \\  -h, --help            Print this help and exit
    \\  --color [auto|off|on] Enable or disable colored error messages
    \\
;

fn cmdFile(io: Io, gpa: Allocator, file_name: []const u8, args: []const []const u8) !void {
    var color: std.zig.Color = .auto;

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.startsWith(u8, arg, "-")) {
            if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
                try Io.File.stdout().writeStreamingAll(io, usage_file);
                return std.process.cleanExit(io);
            } else if (std.mem.eql(u8, arg, "--color")) {
                if (i + 1 >= args.len) {
                    std.process.fatal("expected [auto|off|on] after --color", .{});
                }
                i += 1;
                const next_arg = args[i];
                color = std.meta.stringToEnum(std.zig.Color, next_arg) orelse {
                    std.process.fatal("expected [auto|off|on] after --color, found '{s}'", .{next_arg});
                };
            } else {
                std.process.fatal("unrecognized parameter: '{s}'", .{arg});
            }
        } else {
            std.process.fatal("extra positional parameter: '{s}'", .{arg});
        }
    }

    const file = try Io.Dir.cwd().openFile(io, file_name, .{});
    defer file.close(io);
    var file_reader = file.reader(io, &stdin_buffer);
    const source = try std.zig.readSourceFileToEndAlloc(gpa, &file_reader);
    defer gpa.free(source);

    var tree: Ast = try .parse(gpa, source);
    defer tree.deinit(gpa);

    if (tree.errors.len > 0) {
        try zk.printAstErrorsToStderr(gpa, io, tree, file_name, color);
        std.process.exit(1);
    }

    var stdout_writer = Io.File.stdout().writer(io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    var vm: *Vm = try .init(io, gpa, stdout);
    defer vm.deinit();

    const value = try vm.evalTree(&tree);
    defer value.deref(gpa);
}

const usage_repl =
    \\Usage: zk [options]
    \\
    \\  Start an interactive REPL.
    \\
    \\Options:
    \\
    \\  -h, --help            Print this help and exit
    \\  --color [auto|off|on] Enable or disable colored error messages
    \\
;

const banner = std.fmt.comptimePrint("zk {s} {t} {t}-{t}\n\n", .{
    build_options.version_string,
    builtin.mode,
    builtin.cpu.arch,
    builtin.os.tag,
});

fn cmdRepl(io: Io, gpa: Allocator, args: []const []const u8) !void {
    var color: std.zig.Color = .auto;

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.startsWith(u8, arg, "-")) {
            if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
                try Io.File.stdout().writeStreamingAll(io, usage_repl);
                return std.process.cleanExit(io);
            } else if (std.mem.eql(u8, arg, "--color")) {
                if (i + 1 >= args.len) {
                    std.process.fatal("expected [auto|off|on] after --color", .{});
                }
                i += 1;
                const next_arg = args[i];
                color = std.meta.stringToEnum(std.zig.Color, next_arg) orelse {
                    std.process.fatal("expected [auto|off|on] after --color, found '{s}'", .{next_arg});
                };
            } else {
                std.process.fatal("unrecognized parameter: '{s}'", .{arg});
            }
        } else {
            std.process.fatal("extra positional parameter: '{s}'", .{arg});
        }
    }

    var stdin_reader = Io.File.stdin().reader(io, &stdin_buffer);
    const stdin = &stdin_reader.interface;
    var stdout_writer = Io.File.stdout().writer(io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    var stderr_buffer: [1024]u8 = undefined;
    var stderr_writer = Io.File.stderr().writer(io, &stderr_buffer);
    const stderr = &stderr_writer.interface;

    const vm: *Vm = try .init(io, gpa, stdout);
    defer vm.deinit();

    if (try Io.File.stdin().isTty(io)) {
        try stderr.writeAll(banner);

        while (true) {
            try stderr.writeAll("k)");
            try stderr.flush();

            const line = @constCast(std.mem.trimStart(u8, try stdin.takeDelimiterInclusive('\n'), " \t\r\n"));
            const trimmed = std.mem.trimEnd(u8, line, " \t\r\n");
            line[trimmed.len] = 0;
            const slice = line[0..trimmed.len :0];

            if (slice.len == 0) continue;

            if (std.mem.eql(u8, slice, "\\\\")) break;

            var tree: Ast = try .parse(gpa, slice);
            defer tree.deinit(gpa);
            if (tree.errors.len > 0) {
                try zk.printAstErrorsToStderr(gpa, io, tree, "<stdin>", color);
                continue;
            }

            const value = vm.evalTree(&tree) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                error.InvalidCharacter => return error.InvalidCharacter,
                else => {
                    try stderr.print("'{t}\n", .{err});
                    continue;
                },
            };
            defer value.deref(gpa);

            try stdout.print("{f}\n", .{value.alt(vm)});
            try stdout.flush();
        }
    } else {
        var buffer: Io.Writer.Allocating = .init(gpa);
        defer buffer.deinit();

        _ = try stdin.streamRemaining(&buffer.writer);

        try buffer.writer.writeByte(0);
        const input = buffer.written();
        const slice = input[0 .. input.len - 1 :0];

        var tree: Ast = try .parse(gpa, slice);
        defer tree.deinit(gpa);
        if (tree.errors.len > 0) {
            std.process.exit(1);
        }
    }

    return std.process.cleanExit(io);
}

test {
    std.testing.refAllDecls(@This());
}
