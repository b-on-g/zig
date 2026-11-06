const std = @import("std");

fn fixed(_: void, name: []const u8) Result {
	if (std.mem.eql(u8, name, "A1")) return .{ .num = 10 };
	if (std.mem.eql(u8, name, "BAD")) return Result.fail("ref");
	return .{};
}

fn calc(text: []const u8) Result {
	return eval(text, {}, fixed);
}

test "precedence and parens" {
	try std.testing.expectEqual(14, calc("2 + 3 * 4").num);
	try std.testing.expectEqual(20, calc("(2 + 3) * 4").num);
	try std.testing.expectEqual(-5, calc("-(2 + 3)").num);
	try std.testing.expectEqual(2.5, calc("5 / 2").num);
}

test "refs go through lookup" {
	try std.testing.expectEqual(25, calc("A1 * 2 + 5").num);
	try std.testing.expectEqual(0, calc("Z9").num);
	try std.testing.expectEqualStrings("ref", calc("BAD + 1").err);
}

test "errors" {
	try std.testing.expectEqualStrings("div0", calc("1 / 0").err);
	try std.testing.expectEqualStrings("syntax", calc("1 +").err);
	try std.testing.expectEqualStrings("syntax", calc("(1").err);
	try std.testing.expectEqualStrings("syntax", calc("1 2").err);
	try std.testing.expectEqual(true, calc("").ok());
}

test "names" {
	try std.testing.expectEqual(true, name_check("A1"));
	try std.testing.expectEqual(true, name_check("TOTAL"));
	try std.testing.expectEqual(false, name_check("a1"));
	try std.testing.expectEqual(false, name_check("1A"));
	try std.testing.expectEqual(false, name_check(""));
}
