const std = @import("std");
const wire = @import("bog_zig_wire");

pub const Item = struct {
	sku: []const u8,
	qty: u32,
};

pub const Cart = struct {
	mem: struct {
		items: wire.Mem([]const Item),
		skus: wire.Mem([]const []const u8),
		qty: wire.MemKey([]const u8, u32),
	},

	pub fn items(self: Cart, next: ?[]const Item) []const Item {
		return self.mem.items.call(self, next, struct {
			fn body(_: Cart, put: ?[]const Item) []const Item {
				wire.solid();
				return put orelse &.{};
			}
		}.body);
	}

	pub fn skus(self: Cart) []const []const u8 {
		return self.mem.skus.call(self, null, struct {
			fn body(cart: Cart, _: ?[]const []const u8) []const []const u8 {
				var out: wire.List([]const u8) = .{};
				for (cart.items(null)) |item| out.push(item.sku);
				return out.items();
			}
		}.body);
	}

	pub fn qty(self: Cart, sku: []const u8) u32 {
		return self.mem.qty.call(self, sku, null, struct {
			fn body(cart: Cart, key: []const u8, _: ?u32) u32 {
				for (cart.items(null)) |item| {
					if (std.mem.eql(u8, item.sku, key)) return item.qty;
				}
				return 0;
			}
		}.body);
	}

	pub fn set(self: Cart, sku: []const u8, count: u32) void {
		var next: wire.List(Item) = .{};
		var found = false;

		for (self.items(null)) |item| {
			if (!std.mem.eql(u8, item.sku, sku)) {
				next.push(item);
				continue;
			}
			found = true;
			if (count > 0) next.push(.{ .sku = item.sku, .qty = count });
		}

		if (!found and count > 0) next.push(.{ .sku = sku, .qty = count });
		_ = self.items(next.items());
	}
};
