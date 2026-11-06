namespace $.$$ {

	type $bog_zig_demo_price = { sku: string, price: number }
	type $bog_zig_demo_row = { sku: string, qty: number, sum: number }
	type $bog_zig_demo_state = { products: $bog_zig_demo_price[], lines: $bog_zig_demo_row[], total: number }

	export class $bog_zig_demo extends $.$bog_zig_demo {

		@ $mol_mem
		zig() {
			const buffer = new Uint8Array( $mol_fetch.buffer( 'web.wasm' ) )
			const zig = new $bog_zig_wire( buffer, {
				bog_zig_demo: {
					render: ( ptr: number, len: number )=> this.state( JSON.parse( zig.string( ptr, len ) ) ),
				},
			} )
			zig.call( 'bog_zig_demo_start' )
			return zig
		}

		@ $mol_mem
		state( next?: $bog_zig_demo_state ) {
			return next ?? { products: [], lines: [], total: 0 }
		}

		auto() {
			this.zig()
		}

		alive_label() {
			this.state()
			return `nodes: ${ this.zig().call( 'bog_zig_demo_alive' ) }`
		}

		@ $mol_mem
		prices() {
			return new Map( this.state().products.map( item => [ item.sku, item ] ) )
		}

		@ $mol_mem
		rows() {
			return new Map( this.state().lines.map( item => [ item.sku, item ] ) )
		}

		products() {
			return this.state().products.map( item => this.Product( item.sku ) )
		}

		lines() {
			return this.state().lines.map( item => this.Line( item.sku ) )
		}

		total() {
			return `Итого: ${ this.state().total }`
		}

		product_title( sku: string ) {
			return sku
		}

		product_price( sku: string, next?: number ) {
			if( next !== undefined ) {
				this.zig().call( 'bog_zig_demo_price', ... this.zig().text( sku ), Math.max( 0, next ) )
				return next
			}
			return this.prices().get( sku )?.price ?? 0
		}

		product_add( sku: string ) {
			this.zig().call( 'bog_zig_demo_add', ... this.zig().text( sku ) )
		}

		line_title( sku: string ) {
			return sku
		}

		line_qty( sku: string, next?: number ) {
			if( next !== undefined ) {
				this.zig().call( 'bog_zig_demo_qty', ... this.zig().text( sku ), Math.max( 0, next ) )
				return next
			}
			return this.rows().get( sku )?.qty ?? 0
		}

		line_sum( sku: string ) {
			return String( this.rows().get( sku )?.sum ?? 0 )
		}

		line_remove( sku: string ) {
			this.zig().call( 'bog_zig_demo_qty', ... this.zig().text( sku ), 0 )
		}

	}

}
