const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    const pkg_okredis: std.build.Pkg = .{ .name = "okredis", .source = .{ .path = "vendor/okredis/src/okredis.zig" } };

    {
        const lib = b.addSharedLibrary("redis", "src/redis.zig", .unversioned);
        lib.addPackage(pkg_okredis);
        lib.use_stage1 = true;
        lib.linkLibC();
        lib.setBuildMode(mode);
        lib.install();
    }

    {
        const run_step = b.step("run", "Run the main()");
        run_step.dependOn(blk: {
            const exe = b.addExecutable("main", "src/main.zig");
            exe.addPackage(pkg_okredis);
            exe.use_stage1 = true;
            const run_cmd = exe.run();
            run_cmd.step.dependOn(b.getInstallStep());
            if (b.args) |args| run_cmd.addArgs(args);
            break :blk &run_cmd.step;
        });
    }

    {
        const test_step = b.step("test", "Run library tests");
        test_step.dependOn(blk: {
            const step = b.addTest("src/test.zig");
            step.addPackage(pkg_okredis);
            step.setBuildMode(mode);
            break :blk &step.step;
        });
    }
}
