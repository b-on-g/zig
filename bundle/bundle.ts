namespace $ {

	export class $bog_zig_bundle extends $bog_build2_bundle {

		@ $mol_mem_key
		slice_artifacts( slice: $bog_build2_package_slice ) {
			const prefix = slice.prefix()

			if( prefix === 'node' ) {
				const test = slice.pack().slice( this.$.$bog_build2_package_slice_node_test )
				return [ ... this.native( slice ), ... this.test( test ) ]
			}

			if( prefix === 'web' ) return this.wasm( slice )

			return []
		}

		module_dir( file: $bog_build2_file ) {
			let dir = file.parent()
			while( /^-/.test( dir.name() ) ) dir = dir.parent()
			return dir
		}

		module_name( dir: $bog_build2_file ) {
			return dir.relate( this.root().dir() ).replace( /\//g, '_' )
		}

		modules( slice: $bog_build2_package_slice ) {
			const modules = new Map< $bog_build2_file, $bog_build2_file[] >()

			for( const file of slice.files() ) {
				if( !/\.zig$/.test( file.name() ) ) continue
				if( /^web/.test( slice.prefix() ) && /\.native\./.test( file.name() ) ) continue
				const dir = this.module_dir( file )
				modules.set( dir, [ ... modules.get( dir ) ?? [], file ] )
			}

			return modules
		}

		module_code( files: $bog_build2_file[] ) {
			const imports = new Set< string >()
			const chunks = [] as string[]

			for( const file of files ) {
				const lines = file.text().split( '\n' ).filter( line => {
					if( !/^(pub )?const \w+ = @import\("[^"]+"\);\s*$/.test( line ) ) return true
					if( imports.has( line.trim() ) ) return false
					imports.add( line.trim() )
					return true
				} )

				chunks.push( `// ${ file.relate( this.root().dir() ) }\n` + lines.join( '\n' ) )
			}

			return chunks.join( '\n' ).replace(
				/@import\(\s*"([a-z][a-z0-9]*(?:_[a-z0-9]+)+)"\s*\)/g,
				( _, name )=> `@import("${ name }.zig")`,
			)
		}

		emit( slice: $bog_build2_package_slice ) {
			const out = slice.pack().output().resolve( `zig/${ slice.prefix() }` )
			const names = [] as string[]

			for( const[ dir, files ] of this.modules( slice ) ) {
				const name = this.module_name( dir )
				out.resolve( `${ name }.zig` ).text( this.module_code( files ) )
				names.push( name )
			}

			const main = this.module_name( slice.pack().dir() )
			const code = this.modules( slice ).get( slice.pack().dir() )?.map( file => file.text() ).join( '\n' ) ?? null

			return { out, names, main, code }
		}

		zig( dir: $bog_build2_file, args: string[] ) {
			this.$.$bog_build2_file.unwatched( ()=> this.$.$mol_run.spawn({
				command: [ 'zig', ... args, '--cache-dir', '.zig-cache' ],
				dir: dir.path(),
			}), dir.path() )
		}

		native( slice: $bog_build2_package_slice ) {
			const { out, main, code } = this.emit( slice )
			if( !code || !/\bpub fn main\(/.test( code ) ) return []

			const start = Date.now()
			const target = slice.pack().output().resolve( 'native' )

			this.zig( out, [ 'build-exe', `${ main }.zig`, '-O', 'ReleaseSafe', `-femit-bin=${ target.path() }` ] )
			this.log( target, Date.now() - start )

			return [ target ]
		}

		test( slice: $bog_build2_package_slice ) {
			const { out, names } = this.emit( slice )
			if( !names.length ) return []

			const start = Date.now()
			const root = out.resolve( 'test.zig' )
			root.text( `test {\n${ names.map( name => `\t_ = @import("${ name }.zig");\n` ).join( '' ) }}\n` )

			this.zig( out, [ 'test', 'test.zig' ] )
			this.log( root, Date.now() - start )

			return [ root ]
		}

		wasm( slice: $bog_build2_package_slice ) {
			const { out, main, code } = this.emit( slice )
			if( !code || !/^export fn /m.test( code ) ) return []

			const start = Date.now()
			const target = slice.pack().output().resolve( 'web.wasm' )

			this.zig( out, [
				'build-exe', `${ main }.zig`,
				'-target', 'wasm32-freestanding', '-fno-entry', '-rdynamic', '-O', 'ReleaseSmall',
				`-femit-bin=${ target.path() }`,
			] )
			this.log( target, Date.now() - start )

			return [ target ]
		}

	}

	$bog_build2_root.plugin( $bog_zig_bundle )

}
