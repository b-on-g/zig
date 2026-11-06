namespace $ {

	export class $bog_zig_wire extends $mol_object2 {

		wasm: $mol_wasm_instance

		constructor(
			buffer: Uint8Array< ArrayBuffer >,
			imports: Record< string, Record< string, WebAssembly.ImportValue > > = {},
		) {
			super()
			this.wasm = new $mol_wasm_module( buffer ).instance({
				... imports,
				bog_zig_wire: {
					schedule: ()=> queueMicrotask( ()=> this.call( 'bog_zig_wire_sync' ) ),
					print: ( ptr: number, len: number )=> console.log( this.string( ptr, len ) ),
				},
			})
		}

		call( name: string, ... args: number[] ) {
			return ( this.wasm.get( name ) as ( ... args: number[] )=> number )( ... args )
		}

		text( value: string ) {
			const bytes = new TextEncoder().encode( value )
			const ptr = this.call( 'bog_zig_wire_alloc', bytes.length )
			this.wasm.memory( ptr, bytes.length ).set( bytes )
			return [ ptr, bytes.length ] as const
		}

		string( ptr: number, len: number ) {
			return this.wasm.string( ptr, len )
		}

	}

}
