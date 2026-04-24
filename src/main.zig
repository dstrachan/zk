const std = @import("std");
const Io = std.Io;

const build_options = @import("build_options");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;
    _ = gpa; // autofix
    const arena = init.arena.allocator();
    _ = arena; // autofix

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_file_writer: Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const stdout_writer = &stdout_file_writer.interface;

    try stdout_writer.print("version: {f}\n", .{build_options.version});
    try stdout_writer.flush();
}
