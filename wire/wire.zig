const std = @import("std");
const builtin = @import("builtin");

pub const gpa: std.mem.Allocator = if (builtin.cpu.arch.isWasm()) std.heap.wasm_allocator else std.heap.smp_allocator;

var scratch: std.heap.ArenaAllocator = .init(gpa);

pub fn tmp() std.mem.Allocator {
	return scratch.allocator();
}

pub fn fmt(comptime format: []const u8, args: anytype) []const u8 {
	return std.fmt.allocPrint(tmp(), format, args) catch oom();
}

pub fn List(comptime T: type) type {
	return struct {
		inner: std.ArrayList(T) = .empty,

		pub fn push(self: *@This(), item: T) void {
			self.inner.append(tmp(), item) catch oom();
		}

		pub fn items(self: @This()) []const T {
			return self.inner.items;
		}
	};
}

fn oom() noreturn {
	@panic("$bog_zig_wire: out of memory");
}

pub const Id = struct {
	idx: u32,
	gen: u32,

	fn same(self: Id, other: Id) bool {
		return self.idx == other.idx and self.gen == other.gen;
	}
};

const State = enum(u8) { fresh, doubt, stale };

const Kind = enum { atom, auto, obj, map };

const Erased = struct {
	ptr: *anyopaque,
	free: *const fn (*anyopaque) void,
};

const Detach = struct {
	map: Id,
	key: *anyopaque,
	run: *const fn (Id, *anyopaque) void,
};

const Run = *const fn (*anyopaque, ?*const anyopaque, *anyopaque) void;

const Node = struct {
	gen: u32 = 0,
	alive: bool = true,
	kind: Kind,
	state: State = .stale,
	busy: bool = false,
	solid: bool = false,
	root: bool = false,
	value: ?Erased = null,
	ctx: ?Erased = null,
	run: ?Run = null,
	recalc: ?*const fn (Id) void = null,
	detach: ?Detach = null,
	owner: ?Id = null,
	kids: std.ArrayList(Id) = .empty,
	pubs: std.ArrayList(Id) = .empty,
	subs: std.ArrayList(Id) = .empty,
};

const Runtime = struct {
	nodes: std.ArrayList(Node) = .empty,
	free: std.ArrayList(u32) = .empty,
	current: ?Id = null,
	owner: ?Id = null,
	host: ?Id = null,
	queue: std.ArrayList(Id) = .empty,
	touched: std.ArrayList(Id) = .empty,
	orphans: std.ArrayList(Id) = .empty,
	garbage: std.ArrayList(Erased) = .empty,
	scheduled: bool = false,
};

var rt: Runtime = .{};

fn get(id: Id) ?*Node {
	if (id.idx >= rt.nodes.items.len) return null;
	const found = &rt.nodes.items[id.idx];
	if (!found.alive or found.gen != id.gen) return null;
	return found;
}

fn node(id: Id) *Node {
	return get(id) orelse @panic("$bog_zig_wire: access to destroyed node");
}

fn push(list: *std.ArrayList(Id), id: Id) void {
	list.append(gpa, id) catch oom();
}

fn has(list: std.ArrayList(Id), id: Id) bool {
	for (list.items) |item| {
		if (item.same(id)) return true;
	}
	return false;
}

fn drop(list: *std.ArrayList(Id), id: Id) void {
	var index: usize = 0;
	while (index < list.items.len) {
		if (list.items[index].same(id)) {
			_ = list.orderedRemove(index);
		} else {
			index += 1;
		}
	}
}

fn take(list: *std.ArrayList(Id)) std.ArrayList(Id) {
	const taken = list.*;
	list.* = .empty;
	return taken;
}

fn trash(item: Erased) void {
	rt.garbage.append(gpa, item) catch oom();
}

fn alloc(kind: Kind, root: bool) Id {
	const owner: ?Id = if (root) null else if (rt.owner) |o| (if (get(o) != null) o else null) else null;

	var id: Id = undefined;
	if (rt.free.pop()) |idx| {
		const gen = rt.nodes.items[idx].gen;
		rt.nodes.items[idx] = .{ .gen = gen, .kind = kind, .owner = owner, .root = root };
		id = .{ .idx = idx, .gen = gen };
	} else {
		rt.nodes.append(gpa, .{ .kind = kind, .owner = owner, .root = root }) catch oom();
		id = .{ .idx = @intCast(rt.nodes.items.len - 1), .gen = 0 };
	}

	if (owner) |o| {
		push(&node(o).kids, id);
	} else if (!root) {
		orphan(id);
	}

	return id;
}

fn track(dep: Id) void {
	const sub = rt.current orelse return;
	if (sub.same(dep)) return;
	if (!has(node(sub).pubs, dep)) push(&node(sub).pubs, dep);
	if (!has(node(dep).subs, sub)) push(&node(dep).subs, sub);
}

fn mark(start: Id, start_state: State) void {
	var stack: std.ArrayList(struct { Id, State }) = .empty;
	defer stack.deinit(gpa);
	stack.append(gpa, .{ start, start_state }) catch oom();

	while (stack.pop()) |item| {
		const id, const state = item;
		const found = get(id) orelse continue;
		const was = found.state;
		if (@intFromEnum(was) >= @intFromEnum(state)) continue;
		found.state = state;
		if (was != .fresh) continue;

		if (found.kind == .auto) {
			push(&rt.queue, id);
			schedule_check();
		}

		for (node(id).subs.items) |sub| {
			stack.append(gpa, .{ sub, .doubt }) catch oom();
		}
	}
}

fn touch(id: Id) void {
	push(&rt.touched, id);
	schedule_check();
}

fn orphan(id: Id) void {
	push(&rt.orphans, id);
	schedule_check();
}

fn schedule_check() void {
	if (rt.scheduled) return;
	rt.scheduled = true;
	schedule();
}

fn unlink_pubs(id: Id) void {
	var pubs = take(&node(id).pubs);
	defer pubs.deinit(gpa);

	for (pubs.items) |dep| {
		const found = get(dep) orelse continue;
		drop(&found.subs, id);
		if (found.subs.items.len == 0) touch(dep);
	}
}

fn adopt(owner: Id, kid: Id) void {
	const found = get(kid) orelse return;
	if (found.owner != null or found.root) return;
	found.owner = owner;
	push(&node(owner).kids, kid);
}

fn release(id: Id, keep: ?Id) void {
	var kids = take(&node(id).kids);
	defer kids.deinit(gpa);

	for (kids.items) |kid| {
		if (keep) |k| {
			if (k.same(kid)) {
				push(&node(id).kids, kid);
				continue;
			}
		}
		destroy(kid);
	}
}

fn evict(id: Id) void {
	const found = get(id) orelse return;
	if (found.kind != .atom or found.root or found.solid or found.busy or found.subs.items.len > 0) return;

	if (found.detach != null) {
		destroy(id);
		return;
	}

	unlink_pubs(id);
	release(id, null);

	const atom = node(id);
	atom.state = .stale;
	if (atom.value) |value| trash(value);
	atom.value = null;
}

fn destroy(id: Id) void {
	const found = get(id) orelse return;

	found.alive = false;
	found.gen +%= 1;
	const owner = found.owner;
	var kids = take(&found.kids);
	var pubs = take(&found.pubs);
	var subs = take(&found.subs);
	const detach = found.detach;
	if (found.value) |value| trash(value);
	if (found.ctx) |ctx| trash(ctx);
	found.* = .{ .gen = found.gen, .alive = false, .kind = found.kind };
	rt.free.append(gpa, id.idx) catch oom();

	defer kids.deinit(gpa);
	defer pubs.deinit(gpa);
	defer subs.deinit(gpa);

	if (owner) |o| {
		if (get(o)) |host| drop(&host.kids, id);
	}

	for (pubs.items) |dep| {
		const pub_node = get(dep) orelse continue;
		drop(&pub_node.subs, id);
		if (pub_node.subs.items.len == 0) touch(dep);
	}

	for (subs.items) |sub| {
		if (get(sub)) |sub_node| drop(&sub_node.pubs, id);
		mark(sub, .stale);
	}

	for (kids.items) |kid| destroy(kid);

	if (detach) |d| d.run(d.map, d.key);
}

fn reap() void {
	while (rt.touched.items.len > 0 or rt.orphans.items.len > 0) {
		var touched = take(&rt.touched);
		defer touched.deinit(gpa);
		for (touched.items) |id| evict(id);

		var orphans = take(&rt.orphans);
		defer orphans.deinit(gpa);
		for (orphans.items) |id| {
			const found = get(id) orelse continue;
			if (found.owner == null and !found.root) destroy(id);
		}
	}
}

fn drain() void {
	while (rt.garbage.items.len > 0) {
		var garbage = rt.garbage;
		rt.garbage = .empty;
		defer garbage.deinit(gpa);
		for (garbage.items) |item| item.free(item.ptr);
	}
}

pub fn solid() void {
	if (rt.host) |host| node(host).solid = true;
}

pub fn alive() usize {
	var count: usize = 0;
	for (rt.nodes.items) |item| {
		if (item.alive) count += 1;
	}
	return count;
}

pub fn sync() void {
	while (true) {
		var queue = take(&rt.queue);
		defer queue.deinit(gpa);
		for (queue.items) |id| refresh(id);
		reap();
		if (rt.queue.items.len == 0) break;
	}

	rt.scheduled = false;
	drain();
	_ = scratch.reset(.retain_capacity);
}

fn refresh(id: Id) void {
	const found = get(id) orelse return;
	if (found.busy) @panic("$bog_zig_wire: cyclic dependency");

	if (found.state == .doubt) {
		const pubs = gpa.dupe(Id, found.pubs.items) catch oom();
		defer gpa.free(pubs);

		for (pubs) |dep| {
			refresh(dep);
			const now = get(id) orelse return;
			if (now.state != .doubt) break;
		}

		const now = get(id) orelse return;
		if (now.state == .doubt) now.state = .fresh;
	}

	const now = get(id) orelse return;
	if (now.state != .stale) return;
	if (now.recalc) |recalc| recalc(id);
}

pub fn eql(comptime T: type, left: T, right: T) bool {
	switch (@typeInfo(T)) {
		.pointer => |info| {
			if (info.size != .slice) return left == right;
			if (left.len != right.len) return false;
			for (left, right) |l, r| {
				if (!eql(info.child, l, r)) return false;
			}
			return true;
		},
		.array => |info| {
			for (left, right) |l, r| {
				if (!eql(info.child, l, r)) return false;
			}
			return true;
		},
		.optional => |info| {
			const l = left orelse return right == null;
			const r = right orelse return false;
			return eql(info.child, l, r);
		},
		.@"struct" => |info| {
			if (@hasDecl(T, "wire_eql")) return T.wire_eql(left, right);
			inline for (info.field_names, info.field_types) |name, F| {
				if (!eql(F, @field(left, name), @field(right, name))) return false;
			}
			return true;
		},
		.@"union" => @compileError("$bog_zig_wire: unions are not values: " ++ @typeName(T)),
		else => return left == right,
	}
}

pub fn clone(comptime T: type, value: T) T {
	switch (@typeInfo(T)) {
		.pointer => |info| {
			if (info.size != .slice) return value;
			const copy = gpa.alloc(info.child, value.len) catch oom();
			for (copy, value) |*c, v| c.* = clone(info.child, v);
			return copy;
		},
		.array => |info| {
			var copy: T = undefined;
			for (&copy, value) |*c, v| c.* = clone(info.child, v);
			return copy;
		},
		.optional => |info| {
			const inner = value orelse return null;
			return clone(info.child, inner);
		},
		.@"struct" => |info| {
			if (@hasDecl(T, "wire_eql")) return value;
			var copy: T = undefined;
			inline for (info.field_names, info.field_types) |name, F| {
				@field(copy, name) = clone(F, @field(value, name));
			}
			return copy;
		},
		else => return value,
	}
}

pub fn free(comptime T: type, value: T) void {
	switch (@typeInfo(T)) {
		.pointer => |info| {
			if (info.size != .slice) return;
			for (value) |v| free(info.child, v);
			gpa.free(value);
		},
		.array => |info| {
			for (value) |v| free(info.child, v);
		},
		.optional => |info| {
			if (value) |inner| free(info.child, inner);
		},
		.@"struct" => |info| {
			if (@hasDecl(T, "wire_eql")) return;
			inline for (info.field_names, info.field_types) |name, F| {
				free(F, @field(value, name));
			}
		},
		else => {},
	}
}

fn owning(comptime T: type, value: T) ?Id {
	switch (@typeInfo(T)) {
		.optional => |info| {
			const inner = value orelse return null;
			return owning(info.child, inner);
		},
		.@"struct" => {
			if (@hasDecl(T, "wire_owning")) return value.wire_owning();
			return null;
		},
		else => return null,
	}
}

fn cast(comptime T: type, ptr: anytype) if (@typeInfo(@TypeOf(ptr)).pointer.attrs.@"const") *const T else *T {
	return @ptrCast(@alignCast(ptr));
}

fn Box(comptime T: type) type {
	return struct {
		fn make(value: T) Erased {
			const box = gpa.create(T) catch oom();
			box.* = value;
			return .{ .ptr = @ptrCast(box), .free = release_box };
		}

		fn release_box(ptr: *anyopaque) void {
			const box = cast(T, ptr);
			free(T, box.*);
			gpa.destroy(box);
		}
	};
}

fn Calc(comptime T: type) type {
	return struct {
		fn recalc(id: Id) void {
			apply(id, null);
		}

		fn apply(id: Id, next: ?T) void {
			const task = node(id).run orelse @panic("$bog_zig_wire: atom without task");
			const ctx = node(id).ctx.?.ptr;
			const put = next != null;

			unlink_pubs(id);
			node(id).busy = true;

			const host = rt.host;
			const current = rt.current;
			const owner = rt.owner;
			rt.host = id;
			rt.current = if (put) null else id;
			rt.owner = null;

			var out: T = undefined;
			if (next) |*value| {
				task(ctx, @ptrCast(value), @ptrCast(&out));
			} else {
				task(ctx, null, @ptrCast(&out));
			}

			rt.host = host;
			rt.current = current;
			rt.owner = owner;

			const kid = owning(T, out);
			if (kid) |k| adopt(id, k);
			release(id, kid);

			const atom = node(id);
			atom.busy = false;
			atom.state = .fresh;

			const changed = if (atom.value) |old| !eql(T, cast(T, old.ptr).*, out) else true;
			if (changed) {
				if (atom.value) |old| trash(old);
				atom.value = Box(T).make(clone(T, out));

				const subs = gpa.dupe(Id, atom.subs.items) catch oom();
				defer gpa.free(subs);
				for (subs) |sub| mark(sub, .stale);
			}

			if (!put) touch(id);
		}
	};
}

fn read(comptime T: type, id: Id) T {
	const value = node(id).value orelse @panic("$bog_zig_wire: atom without value");
	return cast(T, value.ptr).*;
}

fn pull(comptime T: type, id: Id, next: ?T) T {
	if (next) |value| {
		Calc(T).apply(id, value);
	} else {
		track(id);
		refresh(id);
	}
	return read(T, id);
}

fn Runner(comptime T: type, comptime Ctx: type, comptime body: anytype) type {
	return struct {
		fn run(ctx: *anyopaque, next: ?*const anyopaque, out: *anyopaque) void {
			const value: ?T = if (next) |ptr| cast(T, ptr).* else null;
			cast(T, out).* = body(cast(Ctx, ctx).*, value);
		}

		fn release_ctx(ctx: *anyopaque) void {
			gpa.destroy(cast(Ctx, ctx));
		}
	};
}

fn bind(comptime T: type, comptime body: anytype, id: Id, ctx: anytype) void {
	const Ctx = @TypeOf(ctx);
	if (node(id).run != null) return;

	const box = gpa.create(Ctx) catch oom();
	box.* = ctx;

	const atom = node(id);
	atom.ctx = .{ .ptr = @ptrCast(box), .free = Runner(T, Ctx, body).release_ctx };
	atom.run = Runner(T, Ctx, body).run;
	atom.recalc = Calc(T).recalc;
}

pub fn Mem(comptime T: type) type {
	return struct {
		id: Id,

		pub fn wire_init() @This() {
			return .{ .id = alloc(.atom, false) };
		}

		pub fn call(self: @This(), ctx: anytype, next: ?T, comptime body: anytype) T {
			bind(T, body, self.id, ctx);
			return pull(T, self.id, next);
		}
	};
}

fn KeyContext(comptime K: type) type {
	if (K == []const u8) return std.hash_map.StringContext;
	return std.hash_map.AutoContext(K);
}

pub fn MemKey(comptime K: type, comptime T: type) type {
	return struct {
		id: Id,

		const Map = std.HashMapUnmanaged(K, Id, KeyContext(K), std.hash_map.default_max_load_percentage);

		fn map(id: Id) *Map {
			return cast(Map, node(id).value.?.ptr);
		}

		fn release_map(ptr: *anyopaque) void {
			const dict = cast(Map, ptr);
			dict.deinit(gpa);
			gpa.destroy(dict);
		}

		fn unlist(map_id: Id, key: *anyopaque) void {
			if (get(map_id) == null) return;
			_ = map(map_id).remove(cast(K, key).*);
		}

		fn Keyed(comptime Ctx: type, comptime body: anytype) type {
			return struct {
				ctx: Ctx,
				key: K,

				fn run(ptr: *anyopaque, next: ?*const anyopaque, out: *anyopaque) void {
					const self = cast(@This(), ptr);
					const value: ?T = if (next) |p| cast(T, p).* else null;
					cast(T, out).* = body(self.ctx, self.key, value);
				}

				fn release_ctx(ptr: *anyopaque) void {
					const self = cast(@This(), ptr);
					free(K, self.key);
					gpa.destroy(self);
				}
			};
		}

		pub fn wire_init() @This() {
			const id = alloc(.map, false);
			const dict = gpa.create(Map) catch oom();
			dict.* = .empty;
			node(id).value = .{ .ptr = @ptrCast(dict), .free = release_map };
			return .{ .id = id };
		}

		pub fn call(self: @This(), ctx: anytype, key: K, next: ?T, comptime body: anytype) T {
			const atom = map(self.id).get(key) orelse spawn: {
				const Ctx = Keyed(@TypeOf(ctx), body);

				const owner = rt.owner;
				rt.owner = self.id;
				const id = alloc(.atom, false);
				rt.owner = owner;

				const box = gpa.create(Ctx) catch oom();
				box.* = .{ .ctx = ctx, .key = clone(K, key) };

				const created = node(id);
				created.ctx = .{ .ptr = @ptrCast(box), .free = Ctx.release_ctx };
				created.run = Ctx.run;
				created.recalc = Calc(T).recalc;
				created.detach = .{ .map = self.id, .key = @ptrCast(&box.key), .run = unlist };

				map(self.id).put(gpa, box.key, id) catch oom();
				break :spawn id;
			};

			return pull(T, atom, next);
		}
	};
}

pub fn init(comptime T: type, fields: anytype) T {
	const Fields = @TypeOf(fields);
	const info = @typeInfo(T).@"struct";
	var made: T = undefined;

	inline for (info.field_names, info.field_types, info.field_attrs) |name, F, attrs| {
		if (@hasField(Fields, name)) {
			@field(made, name) = @field(fields, name);
		} else if (@typeInfo(F) == .@"struct" and @hasDecl(F, "wire_init")) {
			@field(made, name) = F.wire_init();
		} else if (attrs.defaultValue(F)) |default| {
			@field(made, name) = default;
		} else if (@typeInfo(F) == .@"struct") {
			@field(made, name) = init(F, .{});
		} else {
			@compileError("$bog_zig_wire: field " ++ name ++ " of " ++ @typeName(T) ++ " is not set");
		}
	}

	return made;
}

pub fn Obj(comptime T: type) type {
	return struct {
		id: Id,
		inner: T,

		fn build(root: bool, fields: anytype) @This() {
			const id = alloc(.obj, root);
			const owner = rt.owner;
			rt.owner = id;
			defer rt.owner = owner;
			return .{ .id = id, .inner = init(T, fields) };
		}

		pub fn make(fields: anytype) @This() {
			return build(false, fields);
		}

		pub fn get(self: @This()) T {
			if (!self.alive()) @panic("$bog_zig_wire: access to destroyed object");
			return self.inner;
		}

		pub fn alive(self: @This()) bool {
			return root_get(self.id) != null;
		}

		pub fn wire_eql(left: @This(), right: @This()) bool {
			return left.id.same(right.id);
		}

		pub fn wire_owning(self: @This()) ?Id {
			return self.id;
		}
	};
}

fn root_get(id: Id) ?*Node {
	return get(id);
}

pub fn Root(comptime T: type) type {
	return struct {
		obj: Obj(T),

		pub fn make(fields: anytype) @This() {
			return .{ .obj = Obj(T).build(true, fields) };
		}

		pub fn get(self: @This()) T {
			return self.obj.get();
		}

		pub fn deinit(self: @This()) void {
			destroy(self.obj.id);
		}
	};
}

pub const Auto = struct {
	id: Id,

	fn Body(comptime Ctx: type, comptime body: anytype) type {
		return struct {
			fn run(ctx: Ctx, _: ?void) void {
				body(ctx);
			}
		};
	}

	pub fn make(ctx: anytype, comptime body: anytype) Auto {
		const id = alloc(.auto, true);
		bind(void, Body(@TypeOf(ctx), body).run, id, ctx);
		refresh(id);
		return .{ .id = id };
	}

	pub fn deinit(self: Auto) void {
		destroy(self.id);
	}
};
