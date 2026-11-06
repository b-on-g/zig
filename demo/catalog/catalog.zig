const std = @import("std");
const wire = @import("bog_zig_wire");

pub const Price = struct {
	sku: []const u8,
	price: u32,
};

pub const Catalog = struct {
	mem: struct {
		prices: wire.Mem([]const Price),
		price: wire.MemKey([]const u8, u32),
	},

	pub fn prices(self: Catalog, next: ?[]const Price) []const Price {
		return self.mem.prices.call(self, next, struct {
			fn body(_: Catalog, put: ?[]const Price) []const Price {
				wire.solid();
				return put orelse &.{};
			}
		}.body);
	}

	pub fn price(self: Catalog, sku: []const u8) u32 {
		return self.mem.price.call(self, sku, null, struct {
			fn body(catalog: Catalog, key: []const u8, _: ?u32) u32 {
				for (catalog.prices(null)) |item| {
					if (std.mem.eql(u8, item.sku, key)) return item.price;
				}
				return 0;
			}
		}.body);
	}

	pub fn set(self: Catalog, sku: []const u8, value: u32) void {
		var next: wire.List(Price) = .{};
		var found = false;

		for (self.prices(null)) |item| {
			if (std.mem.eql(u8, item.sku, sku)) {
				next.push(.{ .sku = sku, .price = value });
				found = true;
			} else {
				next.push(item);
			}
		}

		if (!found) next.push(.{ .sku = sku, .price = value });
		_ = self.prices(next.items());
	}
};
