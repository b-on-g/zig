const std = @import("std");
const wire = @import("bog_zig_wire");

var runs: u32 = 0;

fn watch_tea(app: App) void {
	_ = app.line("tea").get().label();
	runs += 1;
}

fn watch_receipt(app: App) void {
	_ = app.receipt();
}

test "total follows cart" {
	const root = shop();
	defer root.deinit();
	const app = root.get();

	app.add("tea");
	app.add("tea");
	app.add("cake");
	try std.testing.expectEqual(540, app.total());

	_ = app.line("tea").get().qty(1);
	try std.testing.expectEqual(420, app.total());
}

test "price of other sku keeps line" {
	const root = shop();
	defer root.deinit();
	const app = root.get();
	app.add("tea");
	app.add("cake");

	runs = 0;
	const view = wire.Auto.make(app, watch_tea);
	defer view.deinit();

	app.catalog.set("cake", 280);
	app.catalog.set("milk", 90);
	wire.sync();

	try std.testing.expectEqual(1, runs);
	try std.testing.expectEqual(400, app.total());
}

test "qty of other sku keeps line" {
	const root = shop();
	defer root.deinit();
	const app = root.get();
	app.add("tea");
	app.add("cake");

	runs = 0;
	const view = wire.Auto.make(app, watch_tea);
	defer view.deinit();

	app.add("cake");
	wire.sync();

	try std.testing.expectEqual(1, runs);
	try std.testing.expectEqualStrings("tea x1 = 120", app.line("tea").get().label());
}

test "removed line dies" {
	const root = shop();
	defer root.deinit();
	const app = root.get();
	app.add("tea");
	app.add("cake");

	const view = wire.Auto.make(app, watch_receipt);
	defer view.deinit();
	const tea = app.line("tea");

	app.remove("tea");
	wire.sync();

	try std.testing.expectEqual(false, tea.alive());
	try std.testing.expectEqual(true, app.line("cake").alive());

	const rows = app.receipt();
	try std.testing.expectEqual(2, rows.len);
	try std.testing.expectEqualStrings("cake x1 = 300", rows[0]);
	try std.testing.expectEqualStrings("total 300", rows[1]);
}

test "line reborn from cart" {
	const root = shop();
	defer root.deinit();
	const app = root.get();
	app.add("tea");
	app.add("tea");
	wire.sync();

	try std.testing.expectEqual(2, app.line("tea").get().qty(null));
}

test "root deinit frees graph" {
	wire.sync();
	const base = wire.alive();

	const root = shop();
	const app = root.get();
	app.add("tea");
	const view = wire.Auto.make(app, watch_receipt);
	view.deinit();
	root.deinit();
	wire.sync();

	try std.testing.expectEqual(base, wire.alive());
}
