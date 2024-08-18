const std = @import("std");

const targets: []const std.Target.Query = &.{
    .{ .cpu_arch = .x86_64, .os_tag = .windows },
    .{ .cpu_arch = .aarch64, .os_tag = .macos },
    .{ .cpu_arch = .aarch64, .os_tag = .linux },
    .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .musl },
    .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .gnu },
};

pub fn build(b: *std.Build) !void {
    for (targets) |t| {
        const target = b.resolveTargetQuery(t);
        const ltask = b.addSharedLibrary(.{
            .name = "ltask",
            .target = target,
            .optimize = .ReleaseSafe,
        });

        ltask.linkLibC();
        ltask.linker_allow_shlib_undefined = true;

        var flags_arr = std.ArrayList([]const u8).init(b.allocator);
        defer flags_arr.deinit();

        var c_source_files = std.ArrayList([]const u8).init(b.allocator);
        defer c_source_files.deinit();

        switch (target.result.os.tag) {
            .windows => {
                ltask.linkSystemLibrary("winmm");
                ltask.linkSystemLibrary("ws2_32");
            },
            .linux => {
                ltask.linkSystemLibrary("pthread");

                try flags_arr.append("-fPIC");
            },
            .macos => {
                try flags_arr.append("-fPIC");
                try flags_arr.append("-dynamiclib");
                try flags_arr.append("-undefined dynamic_lookup");
            },
            else => {
                @panic("Unsupported OS");
            },
        }

        const lua_src = b.dependency("lua", .{});
        ltask.addIncludePath(lua_src.path("src"));

        const ltask_src_path = "ltask/src";
        ltask.addIncludePath(b.path(ltask_src_path));
        var dir = try std.fs.cwd().openDir(ltask_src_path, .{ .iterate = true });
        defer dir.close();

        var dir_it = dir.iterate();
        while (try dir_it.next()) |entry| {
            if (entry.kind != .file) {
                continue;
            }
            const file_name = entry.name;
            if (std.mem.endsWith(u8, file_name, ".c")) {
                try c_source_files.append(b.pathJoin(&.{file_name}));
            }
        }
        ltask.addCSourceFiles(.{
            .root = b.path(ltask_src_path),
            .files = c_source_files.items,
            .flags = flags_arr.items,
        });

        const target_output = b.addInstallArtifact(ltask, .{
            .dest_dir = .{
                .override = .{
                    .custom = try t.zigTriple(b.allocator),
                },
            },
        });

        switch (target.result.os.tag) {
            .windows => {
                target_output.dest_sub_path = "ltask.dll";
            },
            .linux => {
                target_output.dest_sub_path = "ltask.so";
            },
            .macos => {
                target_output.dest_sub_path = "ltask.so";
            },
            else => {},
        }

        b.getInstallStep().dependOn(&target_output.step);
    }
}
