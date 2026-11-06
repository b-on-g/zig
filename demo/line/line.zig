const wire = @import("bog_zig_wire");
const Catalog = @import("bog_zig_demo_catalog").Catalog;
const Cart = @import("bog_zig_demo_cart").Cart;

pub const Line = struct {
	catalog: Catalog,
	cart: Cart,
	sku: []const u8,
	mem: struct {
		sum: wire.Mem(u32),
		label: wire.Mem([]const u8),
	},

	pub fn qty(self: Line, next: ?u32) u32 {
		if (next) |count| self.cart.set(self.sku, count);
		return self.cart.qty(self.sku);
	}

	pub fn sum(self: Line) u32 {
		return self.mem.sum.call(self, null, struct {
			fn body(line: Line, _: ?u32) u32 {
				wire.log("  sum {s}", .{line.sku});
				return line.catalog.price(line.sku) * line.qty(null);
			}
		}.body);
	}

	pub fn label(self: Line) []const u8 {
		return self.mem.label.call(self, null, struct {
			fn body(line: Line, _: ?[]const u8) []const u8 {
				return wire.fmt("{s} x{d} = {d}", .{ line.sku, line.qty(null), line.sum() });
			}
		}.body);
	}
};
