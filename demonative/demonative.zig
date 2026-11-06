const std = @import("std");
const wire = @import("bog_zig_wire");
const formula = @import("bog_zig_demonative_formula");
const Sheet = @import("bog_zig_demonative_sheet").Sheet;

pub fn exec(sheet: Sheet, line: []const u8) []const u8 {
	const input = std.mem.trim(u8, line, " \t\r");
	if (input.len == 0 or input[0] == '#') return "";

	const eq = std.mem.indexOfScalar(u8, input, '=') orelse return "expected NAME = formula";
	const name = std.mem.trim(u8, input[0..eq], " \t");
	const source = std.mem.trim(u8, input[eq + 1 ..], " \t");

	if (!formula.name_check(name)) return wire.fmt("bad name: {s}", .{name});

	sheet.set(name, source);
	return "";
}

pub fn render(sheet: Sheet) void {
	for (sheet.names()) |name| {
		const result = sheet.value(name);
		if (result.ok()) {
			wire.log("{s} = {d}", .{ name, result.num });
		} else {
			wire.log("{s} = #{s}", .{ name, result.err });
		}
	}
	wire.log("--", .{});
}
