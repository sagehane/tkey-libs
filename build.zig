const std = @import("std");

const Step = std.Build.Step;
const riscv = std.Target.riscv;

comptime {
    const current = @import("builtin").zig_version;
    const minimum = std.SemanticVersion.parse("0.11.0-dev.3000+d71a43ec2") catch unreachable;

    if (current.order(minimum) == .lt) {
        @compileError(std.fmt.comptimePrint("Your Zig version v{} does not meet the minimum build requirement of v{}", .{ current, minimum }));
    }
}

inline fn srcDir() []const u8 {
    return comptime std.fs.path.dirname(@src().file) orelse ".";
}

const tillitis_features = riscv.featureSet(&.{ .c, .zmmul });

/// https://github.com/tillitis/tillitis-key1/blob/TK1-23.03.1/doc/system_description/software.md#cpu
/// https://github.com/tillitis/tillitis-key1/blob/TK1-23.03.1/hw/application_fpga/Makefile
pub const tillitis_target = std.zig.CrossTarget{
    .cpu_arch = .riscv32,
    .cpu_model = .{ .explicit = &riscv.cpu.generic_rv32 },
    .cpu_features_add = tillitis_features,
    .os_tag = .freestanding,
    // mabi seems to be set to `ilp32` but idk what the Zig/LLVM equivalent is
    //.abi = .gnuilp32,
};

pub const cflags = [_][]const u8{
    "-Wall",
    "-Werror",
    "-Wextra",
    "-mabi=ilp32",
};

pub fn linkArtifact(artfiact: *Step.Compile) void {
    // Setting this doesn't seem to affect the resulting binary?
    // https://releases.llvm.org/16.0.0/tools/clang/docs/ClangCommandLineReference.html#cmdoption-clang-mcmodel
    artfiact.code_model = .medium;

    artfiact.addAssemblyFile(srcDir() ++ "/libcrt0/crt0.S");
    artfiact.setLinkerScriptPath(.{ .path = srcDir() ++ "/app.lds" });
}

pub fn getObjcopyBin(b: *std.Build, app: *Step.Compile, name: []const u8) *Step.InstallFile {
    const objcopy = app.addObjCopy(.{ .basename = name });
    return b.addInstallBinFile(objcopy.getOutputSource(), name);
}

/// Requires `tkey-runapp` to be in `$PATH`
/// https://github.com/tillitis/tillitis-key1-apps/tree/main/cmd/tkey-runapp
pub fn addTkeyRunappCmd(b: *std.Build, bin: *Step.InstallFile) *Step.Run {
    const run_cmd = b.addSystemCommand(&.{"tkey-runapp"});
    run_cmd.addFileSourceArg(bin.source);

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    return run_cmd;
}

pub fn build(b: *std.Build) void {
    // Smaller binaries load much faster to the TKey
    const optimize = b.standardOptimizeOption(
        .{ .preferred_optimize_mode = .ReleaseSmall },
    );

    const libcommon = b.addStaticLibrary(.{
        .name = "libcommon",
        .target = tillitis_target,
        .optimize = optimize,
    });

    libcommon.addCSourceFiles(&.{
        "libcommon/lib.c",
        "libcommon/proto.c",
    }, &(cflags ++ .{"-Wno-sign-compare"}));

    libcommon.addIncludePath("include");
    b.installArtifact(libcommon);

    const libcrt0 = b.addStaticLibrary(.{
        .name = "libcrt0",
        .root_source_file = .{ .path = "libcrt0/crt0.S" },
        .target = tillitis_target,
        .optimize = optimize,
    });

    b.installArtifact(libcrt0);

    const monocypher = b.addStaticLibrary(.{
        .name = "monocypher",
        .target = tillitis_target,
        .optimize = optimize,
    });

    monocypher.addCSourceFiles(&.{
        "monocypher/monocypher-ed25519.c",
        "monocypher/monocypher.c",
    }, &cflags);

    monocypher.addIncludePath("include");
    b.installArtifact(monocypher);

    const blue = b.addExecutable(.{
        .name = "blue.elf",
        .target = tillitis_target,
        .optimize = optimize,
    });

    blue.addCSourceFile("example-app/blue.c", &(cflags ++ .{"-Wno-sign-compare"}));
    blue.addIncludePath("include");
    linkArtifact(blue);

    const blue_bin = getObjcopyBin(b, blue, "blue.bin");
    b.getInstallStep().dependOn(&blue_bin.step);

    const run_cmd = addTkeyRunappCmd(b, blue_bin);
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Requires `tkey-runapp` to be in `$PATH`");
    run_step.dependOn(&run_cmd.step);
}
