const std = @import("std");
const wire = @import("bog_zig_wire");
const formula = @import("bog_zig_demonative_formula");

pub const Result = formula.Result;

pub const Cell = struct {
	name: []const u8,
	text: []const u8,
};

fn listed(list: []const []const u8, name: []const u8) bool {
	for (list) |item| {
		if (std.mem.eql(u8, item, name)) return true;
	}
	return false;
}

fn ascending(_: void, left: []const u8, right: []const u8) bool {
	return std.mem.order(u8, left, right) == .lt;
}

pub const Sheet = struct {
	mem: struct {
		cells: wire.Mem([]const Cell),
		names: wire.Mem([]const []const u8),
		text: wire.MemKey([]const u8, []const u8),
		refs: wire.MemKey([]const u8, []const []const u8),
		value: wire.MemKey([]const u8, Result),
	},

	pub fn cells(self: Sheet, next: ?[]const Cell) []const Cell {
		return self.mem.cells.call(self, next, struct {
			fn body(_: Sheet, put: ?[]const Cell) []const Cell {
				wire.solid();
				return put orelse &.{};
			}
		}.body);
	}

	pub fn names(self: Sheet) []const []const u8 {
		return self.mem.names.call(self, null, struct {
			fn body(sheet: Sheet, _: ?[]const []const u8) []const []const u8 {
				var out: wire.List([]const u8) = .{};
				for (sheet.cells(null)) |cell| out.push(cell.name);
				const sorted = wire.tmp().dupe([]const u8, out.items()) catch @panic("$bog_zig_demonative_sheet: out of memory");
				std.mem.sort([]const u8, sorted, {}, ascending);
				return sorted;
			}
		}.body);
	}

	pub fn text(self: Sheet, name: []const u8) []const u8 {
		return self.mem.text.call(self, name, null, struct {
			fn body(sheet: Sheet, key: []const u8, _: ?[]const u8) []const u8 {
				for (sheet.cells(null)) |cell| {
					if (std.mem.eql(u8, cell.name, key)) return cell.text;
				}
				return "";
			}
		}.body);
	}

	pub fn refs(self: Sheet, name: []const u8) []const []const u8 {
		return self.mem.refs.call(self, name, null, struct {
			fn body(sheet: Sheet, key: []const u8, _: ?[]const []const u8) []const []const u8 {
				return formula.refs(wire.tmp(), sheet.text(key));
			}
		}.body);
	}

	pub fn cyclic(self: Sheet, name: []const u8) bool {
		var seen: wire.List([]const u8) = .{};
		var queue: wire.List([]const u8) = .{};
		for (self.refs(name)) |dep| queue.push(dep);

		var index: usize = 0;
		while (index < queue.items().len) : (index += 1) {
			const dep = queue.items()[index];
			if (std.mem.eql(u8, dep, name)) return true;
			if (listed(seen.items(), dep)) continue;
			seen.push(dep);
			for (self.refs(dep)) |next| queue.push(next);
		}

		return false;
	}

	pub fn value(self: Sheet, name: []const u8) Result {
		return self.mem.value.call(self, name, null, struct {
			fn body(sheet: Sheet, key: []const u8, _: ?Result) Result {
				wire.log("  calc {s}", .{key});
				if (sheet.cyclic(key)) return Result.fail("cycle");
				return formula.eval(sheet.text(key), sheet, ref);
			}
		}.body);
	}

	fn ref(sheet: Sheet, name: []const u8) Result {
		return sheet.value(name);
	}

	pub fn set(self: Sheet, name: []const u8, source: []const u8) void {
		var next: wire.List(Cell) = .{};
		var found = false;

		for (self.cells(null)) |cell| {
			if (!std.mem.eql(u8, cell.name, name)) {
				next.push(cell);
				continue;
			}
			found = true;
			if (source.len > 0) next.push(.{ .name = cell.name, .text = source });
		}

		if (!found and source.len > 0) next.push(.{ .name = name, .text = source });
		_ = self.cells(next.items());
	}
};
