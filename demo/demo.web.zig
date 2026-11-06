const std = @import("std");
const wire = @import("bog_zig_wire");
const Price = @import("bog_zig_demo_catalog").Price;

extern "bog_zig_demo" fn render(ptr: [*]const u8, len: usize) void;

const Row = struct {
	sku: []const u8,
	qty: u32,
	sum: u32,
};

const State = struct {
	products: []const Price,
	lines: []const Row,
	total: u32,
};

const Running = struct {
	root: wire.Root(App),
	view: wire.Auto,
};

var running: ?Running = null;

fn current() App {
	const found = running orelse @panic("$bog_zig_demo: call bog_zig_demo_start first");
	return found.root.get();
}

fn send(shown: App) void {
	var rows: wire.List(Row) = .{};
	for (shown.lines()) |item| {
		const row = item.get();
		rows.push(.{ .sku = row.sku, .qty = row.qty(null), .sum = row.sum() });
	}

	const state: State = .{ .products = shown.catalog.prices(null), .lines = rows.items(), .total = shown.total() };
	const json = wire.fmt("{f}", .{std.json.fmt(state, .{})});
	render(json.ptr, json.len);
}

export fn bog_zig_demo_start() void {
	const root = shop();
	running = .{ .root = root, .view = wire.Auto.make(root.get(), send) };
}

export fn bog_zig_demo_add(ptr: [*]const u8, len: usize) void {
	current().add(wire.text(ptr, len));
}

export fn bog_zig_demo_qty(ptr: [*]const u8, len: usize, count: u32) void {
	_ = current().line(wire.text(ptr, len)).get().qty(count);
}

export fn bog_zig_demo_price(ptr: [*]const u8, len: usize, value: u32) void {
	current().catalog.set(wire.text(ptr, len), value);
}

export fn bog_zig_demo_alive() usize {
	return wire.alive();
}
