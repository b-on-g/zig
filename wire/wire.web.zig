extern "bog_zig_wire" fn schedule() void;

extern "bog_zig_wire" fn print(ptr: [*]const u8, len: usize) void;

export fn bog_zig_wire_sync() void {
	sync();
}

export fn bog_zig_wire_alloc(len: usize) [*]u8 {
	const bytes = tmp().alloc(u8, len) catch oom();
	return bytes.ptr;
}

pub fn text(ptr: [*]const u8, len: usize) []const u8 {
	return ptr[0..len];
}

pub fn log(comptime format: []const u8, args: anytype) void {
	const line = fmt(format, args);
	print(line.ptr, line.len);
}
