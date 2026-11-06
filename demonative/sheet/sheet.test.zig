const std = @import("std");
const wire = @import("bog_zig_wire");

var runs: u32 = 0;

fn watch_b(sheet: Sheet) void {
	_ = sheet.value("B1");
	runs += 1;
}

fn watch_all(sheet: Sheet) void {
	for (sheet.names()) |name| _ = sheet.value(name);
}

test "chain follows source" {
	const root = wire.Root(Sheet).make(.{});
	defer root.deinit();
	const sheet = root.get();

	sheet.set("A1", "10");
	sheet.set("B1", "A1 * 2");
	sheet.set("C1", "B1 + A1");
	try std.testing.expectEqual(30, sheet.value("C1").num);

	sheet.set("A1", "1");
	try std.testing.expectEqual(3, sheet.value("C1").num);
}

test "unrelated cell keeps dependents" {
	const root = wire.Root(Sheet).make(.{});
	defer root.deinit();
	const sheet = root.get();
	sheet.set("A1", "10");
	sheet.set("B1", "A1 * 2");
	sheet.set("D1", "5");

	runs = 0;
	const view = wire.Auto.make(sheet, watch_b);
	defer view.deinit();

	sheet.set("D1", "6");
	sheet.set("A1", "5 + 5");
	wire.sync();

	try std.testing.expectEqual(1, runs);
	try std.testing.expectEqual(20, sheet.value("B1").num);
}

test "cycle is error and heals" {
	const root = wire.Root(Sheet).make(.{});
	defer root.deinit();
	const sheet = root.get();
	const view = wire.Auto.make(sheet, watch_all);
	defer view.deinit();

	sheet.set("A1", "B1 + 1");
	sheet.set("B1", "A1 + 1");
	wire.sync();
	try std.testing.expectEqualStrings("cycle", sheet.value("A1").err);
	try std.testing.expectEqualStrings("cycle", sheet.value("B1").err);

	sheet.set("B1", "1");
	wire.sync();
	try std.testing.expectEqual(2, sheet.value("A1").num);
	try std.testing.expectEqual(1, sheet.value("B1").num);
}

test "error flows to dependents" {
	const root = wire.Root(Sheet).make(.{});
	defer root.deinit();
	const sheet = root.get();

	sheet.set("A1", "1 / 0");
	sheet.set("B1", "A1 + 1");
	try std.testing.expectEqualStrings("div0", sheet.value("B1").err);

	sheet.set("A1", "4");
	try std.testing.expectEqual(5, sheet.value("B1").num);
}

test "names sorted and removal frees" {
	const root = wire.Root(Sheet).make(.{});
	defer root.deinit();
	const sheet = root.get();
	const view = wire.Auto.make(sheet, watch_all);
	defer view.deinit();

	sheet.set("B1", "2");
	sheet.set("A1", "1");
	wire.sync();
	const names = sheet.names();
	try std.testing.expectEqual(2, names.len);
	try std.testing.expectEqualStrings("A1", names[0]);
	try std.testing.expectEqualStrings("B1", names[1]);
	const base = wire.alive();

	sheet.set("C1", "3");
	wire.sync();
	try std.testing.expectEqual(base + 3, wire.alive());

	sheet.set("C1", "");
	wire.sync();
	try std.testing.expectEqual(base, wire.alive());
}

test "cycle made by editing computed cell" {
	const root = wire.Root(Sheet).make(.{});
	defer root.deinit();
	const sheet = root.get();
	const view = wire.Auto.make(sheet, watch_all);
	defer view.deinit();

	sheet.set("A1", "B1 + 1");
	wire.sync();
	try std.testing.expectEqual(1, sheet.value("A1").num);

	sheet.set("B1", "A1");
	wire.sync();
	try std.testing.expectEqualStrings("cycle", sheet.value("A1").err);
	try std.testing.expectEqualStrings("cycle", sheet.value("B1").err);

	sheet.set("B1", "10");
	wire.sync();
	try std.testing.expectEqual(11, sheet.value("A1").num);
}
