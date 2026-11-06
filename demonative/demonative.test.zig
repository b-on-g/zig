const std = @import("std");
const wire = @import("bog_zig_wire");

test "exec sets and clears cells" {
	const root = wire.Root(Sheet).make(.{});
	defer root.deinit();
	const sheet = root.get();

	try std.testing.expectEqualStrings("", exec(sheet, "A1 = 2"));
	try std.testing.expectEqualStrings("", exec(sheet, " B1=A1*A1 "));
	try std.testing.expectEqual(4, sheet.value("B1").num);

	try std.testing.expectEqualStrings("", exec(sheet, "A1 ="));
	try std.testing.expectEqual(0, sheet.value("B1").num);
	try std.testing.expectEqual(1, sheet.names().len);
}

test "exec rejects garbage" {
	const root = wire.Root(Sheet).make(.{});
	defer root.deinit();
	const sheet = root.get();

	try std.testing.expectEqualStrings("", exec(sheet, "# comment"));
	try std.testing.expectEqualStrings("expected NAME = formula", exec(sheet, "hello"));
	try std.testing.expectEqualStrings("bad name: a1", exec(sheet, "a1 = 1"));
	try std.testing.expectEqual(0, sheet.names().len);
}
