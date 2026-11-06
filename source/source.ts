namespace $ {

	export class $bog_zig_source extends $bog_build2_source {

		static match( file: $bog_build2_file ) {
			return /\.zig$/.test( file.name() )
		}

		@ $mol_mem
		deps() {
			const deps = super.deps()

			for( const line of String( this.file().text() ).split( '\n' ) ) {
				const code = line.replace( /\/\/.*$/, '' )
				const priority = this.priority( line )

				for( const [ , name ] of code.matchAll( /@import\(\s*"([a-z][a-z0-9]*(?:_[a-z0-9]+)+)"\s*\)/g ) ) {
					this.fqn_add( deps, name, priority )
				}
			}

			return deps
		}

	}

	$bog_build2_root.plugin( $bog_zig_source )

}
