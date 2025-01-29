const std = @import("std");
const Website = @import("src/website.zig").Website;
const docs = @import("src/docs.zig");

pub const exclude_extensions: []const []const u8 = &.{
    ".DS_Store",
};

pub fn build(b: *std.Build) !void {
    const url_prefix: []const u8 = b.option(
        []const u8,
        "url_prefix",
        "Prefix links with this string",
    ) orelse "";

    const git_commit = b.option(
        []const u8,
        "git-commit",
        "The git commit revision of the source code.",
    ) orelse std.mem.trimRight(u8, b.run(&.{ "git", "rev-parse", "--verify", "HEAD" }), "\n");

    const pandoc_bin = get_pandoc_bin(b) orelse return;

    const content = b.addWriteFiles();
    _ = content.addCopyDirectory(b.path("assets"), ".", .{
        .exclude_extensions = exclude_extensions,
    });

    const website = Website.init(b, url_prefix, pandoc_bin);
    try docs.build(b, content, website);

    const service_worker_writer = b.addRunArtifact(b.addExecutable(.{
        .name = "service_worker_writer",
        .root_source_file = b.path("src/service_worker_writer.zig"),
        .target = b.graph.host,
    }));
    service_worker_writer.addArgs(&.{ url_prefix, git_commit });
    service_worker_writer.addDirectoryArg(content.getDirectory());

    const service_worker = service_worker_writer.captureStdOut();

    const file_checker = b.addRunArtifact(b.addExecutable(.{
        .name = "file_checker",
        .root_source_file = b.path("src/file_checker.zig"),
        .target = b.graph.host,
    }));
    file_checker.addArg("zig-out");

    file_checker.step.dependOn(&b.addInstallDirectory(.{
        .source_dir = content.getDirectory(),
        .install_dir = .prefix,
        .install_subdir = ".",
    }).step);
    file_checker.step.dependOn(&b.addInstallFile(service_worker, "service-worker.js").step);

    b.getInstallStep().dependOn(&file_checker.step);
}

fn get_pandoc_bin(b: *std.Build) ?std.Build.LazyPath {
    const host = b.graph.host.result;
    const name = switch (host.os.tag) {
        .linux => switch (host.cpu.arch) {
            .x86_64 => "pandoc_linux_amd64",
            else => @panic("unsupported cpu arch"),
        },
        .macos => switch (host.cpu.arch) {
            .aarch64 => "pandoc_macos_arm64",
            else => @panic("unsupported cpu arch"),
        },
        else => @panic("unsupported os"),
    };
    if (b.lazyDependency(name, .{})) |dep| {
        return dep.path("bin/pandoc");
    } else {
        return null;
    }
}
