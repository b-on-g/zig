const wire = @import("bog_zig_wire");

const Scene = struct {
	root: wire.Root(App),
	view: wire.Auto,
};

fn print(app: App) void {
	for (app.receipt()) |row| wire.log("{s}", .{row});
}

pub fn main() void {
	wire.run({}, struct {
		fn start(_: void) void {
			const root = shop();
			const app = root.get();
			const view = wire.Auto.make(app, print);

			wire.after(app, struct {
				fn step(a: App) void {
					wire.log("add tea, cake", .{});
					a.add("tea");
					a.add("cake");
				}
			}.step);

			wire.after(app, struct {
				fn step(a: App) void {
					wire.log("one more tea", .{});
					a.add("tea");
				}
			}.step);

			wire.after(app, struct {
				fn step(a: App) void {
					wire.log("milk price, milk not in cart", .{});
					a.catalog.set("milk", 90);
				}
			}.step);

			wire.after(app, struct {
				fn step(a: App) void {
					wire.log("cake price", .{});
					a.catalog.set("cake", 280);
				}
			}.step);

			wire.after(app, struct {
				fn step(a: App) void {
					wire.log("remove tea", .{});
					a.remove("tea");
				}
			}.step);

			wire.after(Scene{ .root = root, .view = view }, struct {
				fn step(scene: Scene) void {
					scene.view.deinit();
					scene.root.deinit();
					wire.sync();
					wire.log("nodes alive: {d}", .{wire.alive()});
				}
			}.step);
		}
	}.start);
}
