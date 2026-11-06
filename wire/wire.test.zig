const std = @import("std");

const Hits = struct {
	double: u32 = 0,
	label: u32 = 0,
	diamond: u32 = 0,
};

var hits: Hits = .{};

const Item = struct {
	mem: struct {
		title: Mem([]const u8),
	},

	fn title(self: Item, next: ?[]const u8) []const u8 {
		return self.mem.title.call(self, next, struct {
			fn body(_: Item, put: ?[]const u8) []const u8 {
				return put orelse "";
			}
		}.body);
	}
};

const Counter = struct {
	mem: struct {
		count: Mem(i32),
		level: Mem(i32),
		parity: Mem(bool),
		double: Mem(i32),
		label: Mem([]const u8),
		diamond: Mem(i32),
		title: MemKey(u32, []const u8),
		current: Mem(Obj(Item)),
		stored: Mem(?Obj(Item)),
		bag: Mem([]const Obj(Item)),
		item: MemKey(u32, Obj(Item)),
	},

	fn count(self: Counter, next: ?i32) i32 {
		return self.mem.count.call(self, next, struct {
			fn body(_: Counter, put: ?i32) i32 {
				return put orelse 1;
			}
		}.body);
	}

	fn level(self: Counter, next: ?i32) i32 {
		return self.mem.level.call(self, next, struct {
			fn body(_: Counter, put: ?i32) i32 {
				solid();
				return put orelse 1;
			}
		}.body);
	}

	fn parity(self: Counter) bool {
		return self.mem.parity.call(self, null, struct {
			fn body(c: Counter, _: ?bool) bool {
				return @mod(c.count(null), 2) == 0;
			}
		}.body);
	}

	fn double(self: Counter) i32 {
		return self.mem.double.call(self, null, struct {
			fn body(c: Counter, _: ?i32) i32 {
				hits.double += 1;
				return c.count(null) * 2;
			}
		}.body);
	}

	fn label(self: Counter) []const u8 {
		return self.mem.label.call(self, null, struct {
			fn body(c: Counter, _: ?[]const u8) []const u8 {
				hits.label += 1;
				return if (c.parity()) "even" else "odd";
			}
		}.body);
	}

	fn diamond(self: Counter) i32 {
		return self.mem.diamond.call(self, null, struct {
			fn body(c: Counter, _: ?i32) i32 {
				hits.diamond += 1;
				return c.double() + c.count(null);
			}
		}.body);
	}

	fn title(self: Counter, id: u32, next: ?[]const u8) []const u8 {
		return self.mem.title.call(self, id, next, struct {
			fn body(c: Counter, key: u32, put: ?[]const u8) []const u8 {
				return put orelse fmt("#{d} of {d}", .{ key, c.count(null) });
			}
		}.body);
	}

	fn current(self: Counter) Obj(Item) {
		return self.mem.current.call(self, null, struct {
			fn body(c: Counter, _: ?Obj(Item)) Obj(Item) {
				const made = Obj(Item).make(.{});
				_ = made.get().title(fmt("item {d}", .{c.count(null)}));
				return made;
			}
		}.body);
	}

	fn stored(self: Counter, next: ??Obj(Item)) ?Obj(Item) {
		return self.mem.stored.call(self, next, struct {
			fn body(_: Counter, put: ??Obj(Item)) ?Obj(Item) {
				return put orelse null;
			}
		}.body);
	}

	fn bag(self: Counter, next: ?[]const Obj(Item)) []const Obj(Item) {
		return self.mem.bag.call(self, next, struct {
			fn body(_: Counter, put: ?[]const Obj(Item)) []const Obj(Item) {
				return put orelse &.{};
			}
		}.body);
	}

	fn item(self: Counter, id: u32) Obj(Item) {
		return self.mem.item.call(self, id, null, struct {
			fn body(_: Counter, key: u32, _: ?Obj(Item)) Obj(Item) {
				const made = Obj(Item).make(.{});
				_ = made.get().title(fmt("item {d}", .{key}));
				return made;
			}
		}.body);
	}
};

fn fresh() Root(Counter) {
	sync();
	hits = .{};
	return Root(Counter).make(.{});
}

test "memoized" {
	const root = fresh();
	defer root.deinit();
	const app = root.get();

	try std.testing.expectEqual(2, app.double());
	try std.testing.expectEqual(2, app.double());
	try std.testing.expectEqual(1, hits.double);
}

test "invalidated by put" {
	const root = fresh();
	defer root.deinit();
	const app = root.get();

	try std.testing.expectEqual(2, app.double());
	_ = app.count(5);
	try std.testing.expectEqual(10, app.double());
	try std.testing.expectEqual(2, hits.double);
}

test "equal value stops propagation" {
	const root = fresh();
	defer root.deinit();
	const app = root.get();

	try std.testing.expectEqualStrings("odd", app.label());
	_ = app.count(3);
	try std.testing.expectEqualStrings("odd", app.label());
	try std.testing.expectEqual(1, hits.label);
	_ = app.count(4);
	try std.testing.expectEqualStrings("even", app.label());
	try std.testing.expectEqual(2, hits.label);
}

test "diamond once" {
	const root = fresh();
	defer root.deinit();
	const app = root.get();

	try std.testing.expectEqual(3, app.diamond());
	_ = app.count(10);
	try std.testing.expectEqual(30, app.diamond());
	try std.testing.expectEqual(2, hits.diamond);
}

test "keyed mem" {
	const root = fresh();
	defer root.deinit();
	const app = root.get();

	try std.testing.expectEqualStrings("#7 of 1", app.title(7, null));
	_ = app.count(2);
	try std.testing.expectEqualStrings("#7 of 2", app.title(7, null));
	_ = app.title(7, "custom");
	try std.testing.expectEqualStrings("custom", app.title(7, null));
	try std.testing.expectEqualStrings("#8 of 2", app.title(8, null));
}

var seen: std.ArrayList(bool) = .empty;

test "auto reruns on sync" {
	const root = fresh();
	defer root.deinit();
	const app = root.get();
	seen.clearRetainingCapacity();

	const view = Auto.make(app, struct {
		fn body(c: Counter) void {
			seen.append(gpa, std.mem.eql(u8, c.label(), "even")) catch oom();
		}
	}.body);

	_ = app.count(3);
	sync();
	_ = app.count(6);
	sync();
	try std.testing.expectEqualSlices(bool, &.{ false, true }, seen.items);

	view.deinit();
	_ = app.count(7);
	sync();
	try std.testing.expectEqual(2, seen.items.len);
}

test "root deinit frees everything" {
	sync();
	const base = alive();

	const root = Root(Counter).make(.{});
	const app = root.get();
	_ = app.count(3);
	_ = app.diamond();
	_ = app.title(1, null);
	_ = app.current();
	_ = app.stored(Obj(Item).make(.{}));
	sync();
	root.deinit();

	try std.testing.expectEqual(base, alive());
}

test "unobserved caches evicted on sync" {
	const root = fresh();
	defer root.deinit();
	const app = root.get();
	sync();
	const base = alive();

	for (0..100) |id| _ = app.title(@intCast(id), null);
	try std.testing.expectEqual(base + 100, alive());

	sync();
	try std.testing.expectEqual(base, alive());
}

test "observed caches survive sync" {
	const root = fresh();
	defer root.deinit();
	const app = root.get();

	const view = Auto.make(app, struct {
		fn body(c: Counter) void {
			_ = c.title(1, null);
		}
	}.body);
	sync();
	const base = alive();

	sync();
	try std.testing.expectEqual(base, alive());
	try std.testing.expectEqualStrings("#1 of 1", app.title(1, null));

	view.deinit();
	sync();
	try std.testing.expectEqual(base - 1 - 1, alive());
}

test "put state kept until first unsubscribe" {
	const root = fresh();
	defer root.deinit();
	const app = root.get();

	_ = app.count(5);
	sync();
	try std.testing.expectEqual(5, app.count(null));

	const view = Auto.make(app, struct {
		fn body(c: Counter) void {
			_ = c.count(null);
		}
	}.body);
	sync();
	try std.testing.expectEqual(5, app.count(null));

	view.deinit();
	sync();
	try std.testing.expectEqual(1, app.count(null));
}

test "solid state survives unsubscribe" {
	const root = fresh();
	defer root.deinit();
	const app = root.get();

	_ = app.level(5);
	const view = Auto.make(app, struct {
		fn body(c: Counter) void {
			_ = c.level(null);
		}
	}.body);
	sync();
	view.deinit();
	sync();

	try std.testing.expectEqual(5, app.level(null));
}

test "solid state freed with owner" {
	sync();
	const base = alive();

	const root = Root(Counter).make(.{});
	_ = root.get().level(5);
	sync();
	root.deinit();

	try std.testing.expectEqual(base, alive());
}

test "derived object replaced without leak" {
	const root = fresh();
	defer root.deinit();
	const app = root.get();

	const view = Auto.make(app, struct {
		fn body(c: Counter) void {
			_ = c.current();
		}
	}.body);
	sync();
	const base = alive();

	for (0..10) |n| {
		_ = app.count(@intCast(n));
		sync();
	}
	try std.testing.expectEqual(base, alive());

	const old = app.current();
	_ = app.count(100);
	sync();
	try std.testing.expectEqual(false, old.alive());
	try std.testing.expectEqualStrings("item 100", app.current().get().title(null));

	view.deinit();
	sync();
	try std.testing.expectEqual(base - 1 - 2, alive());
}

test "keyed object lives while observed" {
	const root = fresh();
	defer root.deinit();
	const app = root.get();
	sync();
	const base = alive();

	const view = Auto.make(app, struct {
		fn body(c: Counter) void {
			_ = c.item(1).get().title(null);
		}
	}.body);
	sync();

	const found = app.item(1);
	sync();
	try std.testing.expectEqual(true, found.alive());
	try std.testing.expectEqual(true, eql(Obj(Item), found, app.item(1)));

	view.deinit();
	sync();
	try std.testing.expectEqual(false, found.alive());
	try std.testing.expectEqual(base, alive());
}

test "collection owns nothing" {
	const root = fresh();
	defer root.deinit();
	const app = root.get();
	sync();
	const base = alive();

	const first = Obj(Item).make(.{});
	const second = Obj(Item).make(.{});
	_ = app.bag(&.{ first, second });
	sync();

	try std.testing.expectEqual(false, first.alive());
	try std.testing.expectEqual(false, second.alive());
	try std.testing.expectEqual(2, app.bag(null).len);
	try std.testing.expectEqual(base, alive());
}

test "orphans freed on sync" {
	const root = fresh();
	defer root.deinit();
	sync();
	const base = alive();

	const lost = Obj(Item).make(.{});
	_ = lost.get().title("lost");
	try std.testing.expectEqual(base + 2, alive());

	sync();
	try std.testing.expectEqual(base, alive());
	try std.testing.expectEqual(false, lost.alive());
}

test "put catches and releases" {
	const root = fresh();
	defer root.deinit();
	const app = root.get();
	sync();
	const base = alive();

	const first = Obj(Item).make(.{});
	const second = Obj(Item).make(.{});
	_ = app.stored(first);
	sync();
	try std.testing.expectEqual(true, first.alive());
	try std.testing.expectEqual(false, second.alive());
	try std.testing.expectEqual(base + 2, alive());

	const third = Obj(Item).make(.{});
	_ = app.stored(third);
	try std.testing.expectEqual(false, first.alive());
	try std.testing.expectEqual(true, third.alive());
	try std.testing.expectEqual(base + 2, alive());
}

var doubles: std.ArrayList(i32) = .empty;

const Scene = struct {
	root: Root(Counter),
	view: Auto,
};

test "tick after each task" {
	sync();
	const base = alive();
	doubles.clearRetainingCapacity();

	run({}, struct {
		fn main(_: void) void {
			const root = Root(Counter).make(.{});
			const app = root.get();
			const view = Auto.make(app, struct {
				fn body(c: Counter) void {
					doubles.append(gpa, c.double()) catch oom();
				}
			}.body);

			_ = app.count(2);
			_ = app.count(3);

			after(Scene{ .root = root, .view = view }, struct {
				fn step(scene: Scene) void {
					_ = scene.root.get().count(4);
					after(scene, struct {
						fn done(last: Scene) void {
							last.view.deinit();
							last.root.deinit();
						}
					}.done);
				}
			}.step);
		}
	}.main);

	try std.testing.expectEqualSlices(i32, &.{ 2, 6, 8 }, doubles.items);
	try std.testing.expectEqual(base, alive());
}

test "unobserved reaped after task" {
	const root = fresh();
	defer root.deinit();

	run(root.get(), struct {
		fn main(app: Counter) void {
			_ = app.double();
			after(app, struct {
				fn again(c: Counter) void {
					_ = c.double();
				}
			}.again);
		}
	}.main);

	try std.testing.expectEqual(2, hits.double);
}
