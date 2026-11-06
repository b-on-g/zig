const std = @import("std");

pub const Result = struct {
	num: f64 = 0,
	err: []const u8 = "",

	pub fn fail(err: []const u8) Result {
		return .{ .err = err };
	}

	pub fn ok(self: Result) bool {
		return self.err.len == 0;
	}
};

pub fn name_check(text: []const u8) bool {
	if (text.len == 0 or !std.ascii.isUpper(text[0])) return false;
	for (text) |char| {
		if (!std.ascii.isUpper(char) and !std.ascii.isDigit(char)) return false;
	}
	return true;
}

pub fn eval(text: []const u8, ctx: anytype, comptime lookup: anytype) Result {
	var parser: Parser(@TypeOf(ctx), lookup) = .{ .text = text, .ctx = ctx };
	parser.skip();
	if (parser.pos == text.len) return .{};

	const value = parser.expr();
	if (!value.ok()) return value;

	parser.skip();
	if (parser.pos != text.len) return Result.fail("syntax");
	return value;
}

const Collector = struct {
	names: std.ArrayList([]const u8) = .empty,
	allocator: std.mem.Allocator,
};

fn collect(into: *Collector, name: []const u8) Result {
	into.names.append(into.allocator, name) catch @panic("$bog_zig_demonative_formula: out of memory");
	return .{ .num = 1 };
}

pub fn refs(allocator: std.mem.Allocator, text: []const u8) []const []const u8 {
	var into: Collector = .{ .allocator = allocator };
	_ = eval(text, &into, collect);
	return into.names.items;
}

fn Parser(comptime Ctx: type, comptime lookup: anytype) type {
	return struct {
		text: []const u8,
		ctx: Ctx,
		pos: usize = 0,

		fn skip(self: *@This()) void {
			while (self.pos < self.text.len and self.text[self.pos] == ' ') self.pos += 1;
		}

		fn peek(self: *@This()) u8 {
			self.skip();
			return if (self.pos < self.text.len) self.text[self.pos] else 0;
		}

		fn expr(self: *@This()) Result {
			var left = self.term();
			while (left.ok()) {
				const op = self.peek();
				if (op != '+' and op != '-') break;
				self.pos += 1;
				const right = self.term();
				if (!right.ok()) return right;
				left.num = if (op == '+') left.num + right.num else left.num - right.num;
			}
			return left;
		}

		fn term(self: *@This()) Result {
			var left = self.factor();
			while (left.ok()) {
				const op = self.peek();
				if (op != '*' and op != '/') break;
				self.pos += 1;
				const right = self.factor();
				if (!right.ok()) return right;
				if (op == '/' and right.num == 0) return Result.fail("div0");
				left.num = if (op == '*') left.num * right.num else left.num / right.num;
			}
			return left;
		}

		fn factor(self: *@This()) Result {
			const char = self.peek();

			if (char == '-') {
				self.pos += 1;
				var inner = self.factor();
				inner.num = -inner.num;
				return inner;
			}

			if (char == '(') {
				self.pos += 1;
				const inner = self.expr();
				if (!inner.ok()) return inner;
				if (self.peek() != ')') return Result.fail("syntax");
				self.pos += 1;
				return inner;
			}

			const start = self.pos;

			if (std.ascii.isDigit(char)) {
				while (self.pos < self.text.len and (std.ascii.isDigit(self.text[self.pos]) or self.text[self.pos] == '.')) self.pos += 1;
				const num = std.fmt.parseFloat(f64, self.text[start..self.pos]) catch return Result.fail("syntax");
				return .{ .num = num };
			}

			if (std.ascii.isUpper(char)) {
				while (self.pos < self.text.len and (std.ascii.isUpper(self.text[self.pos]) or std.ascii.isDigit(self.text[self.pos]))) self.pos += 1;
				return lookup(self.ctx, self.text[start..self.pos]);
			}

			return Result.fail("syntax");
		}
	};
}
