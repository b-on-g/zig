const std = @import("std");
const wire = @import("bog_zig_wire");

const Session = struct {
	root: wire.Root(Sheet),
	view: wire.Auto,
};

var buffer: [4096]u8 = undefined;
var stdin_reader: ?std.Io.File.Reader = null;

fn line_next() ?[]const u8 {
	if (stdin_reader == null) stdin_reader = std.Io.File.stdin().reader(std.Io.Threaded.global_single_threaded.io(), &buffer);
	return stdin_reader.?.interface.takeDelimiter('\n') catch null;
}

fn step(session: Session) void {
	const line = line_next() orelse {
		session.view.deinit();
		session.root.deinit();
		wire.sync();
		wire.log("nodes alive: {d}", .{wire.alive()});
		return;
	};

	const message = exec(session.root.get(), line);
	if (message.len > 0) wire.log("! {s}", .{message});

	wire.after(session, step);
}

pub fn main() void {
	wire.run({}, struct {
		fn start(_: void) void {
			const root = wire.Root(Sheet).make(.{});
			const view = wire.Auto.make(root.get(), render);
			wire.after(Session{ .root = root, .view = view }, step);
		}
	}.start);
}
