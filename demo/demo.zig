const wire = @import("bog_zig_wire");
const Catalog = @import("bog_zig_demo_catalog").Catalog;
const Cart = @import("bog_zig_demo_cart").Cart;
const Line = @import("bog_zig_demo_line").Line;

pub const App = struct {
	catalog: Catalog,
	cart: Cart,
	mem: struct {
		line: wire.MemKey([]const u8, wire.Obj(Line)),
		total: wire.Mem(u32),
		receipt: wire.Mem([]const []const u8),
	},

	pub fn line(self: App, sku: []const u8) wire.Obj(Line) {
		return self.mem.line.call(self, sku, null, struct {
			fn body(app: App, key: []const u8, _: ?wire.Obj(Line)) wire.Obj(Line) {
				return wire.Obj(Line).make(.{ .catalog = app.catalog, .cart = app.cart, .sku = key });
			}
		}.body);
	}

	pub fn lines(self: App) []const wire.Obj(Line) {
		var out: wire.List(wire.Obj(Line)) = .{};
		for (self.cart.skus()) |sku| out.push(self.line(sku));
		return out.items();
	}

	pub fn add(self: App, sku: []const u8) void {
		const found = self.line(sku).get();
		_ = found.qty(found.qty(null) + 1);
	}

	pub fn remove(self: App, sku: []const u8) void {
		self.cart.set(sku, 0);
	}

	pub fn total(self: App) u32 {
		return self.mem.total.call(self, null, struct {
			fn body(app: App, _: ?u32) u32 {
				var out: u32 = 0;
				for (app.lines()) |item| out += item.get().sum();
				return out;
			}
		}.body);
	}

	pub fn receipt(self: App) []const []const u8 {
		return self.mem.receipt.call(self, null, struct {
			fn body(app: App, _: ?[]const []const u8) []const []const u8 {
				var rows: wire.List([]const u8) = .{};
				for (app.lines()) |item| rows.push(item.get().label());
				rows.push(wire.fmt("total {d}", .{app.total()}));
				return rows.items();
			}
		}.body);
	}
};

pub fn shop() wire.Root(App) {
	const root = wire.Root(App).make(.{});
	const app = root.get();
	app.catalog.set("tea", 120);
	app.catalog.set("cake", 300);
	app.catalog.set("milk", 80);
	return root;
}
