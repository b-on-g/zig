const std = @import("std");

const Task = struct {
	ctx: *anyopaque,
	run: *const fn (*anyopaque) void,
};

var tasks: std.Deque(Task) = .empty;

fn schedule() void {}

fn Later(comptime Ctx: type, comptime body: anytype) type {
	return struct {
		fn run(ptr: *anyopaque) void {
			const ctx = cast(Ctx, ptr);
			defer gpa.destroy(ctx);
			body(ctx.*);
		}
	};
}

pub fn after(ctx: anytype, comptime body: anytype) void {
	const Ctx = @TypeOf(ctx);
	const box = gpa.create(Ctx) catch oom();
	box.* = ctx;
	tasks.pushBack(gpa, .{ .ctx = @ptrCast(box), .run = Later(Ctx, body).run }) catch oom();
}

pub fn run(ctx: anytype, comptime body: anytype) void {
	body(ctx);
	if (rt.scheduled) sync();

	while (tasks.popFront()) |task| {
		task.run(task.ctx);
		if (rt.scheduled) sync();
	}
}

pub fn log(comptime format: []const u8, args: anytype) void {
	const io = std.Io.Threaded.global_single_threaded.io();
	std.Io.File.stdout().writeStreamingAll(io, fmt(format ++ "\n", args)) catch {};
}
