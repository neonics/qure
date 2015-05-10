/** @author: <kenney@neonics.com> */

_(function(_) {

	function mouseEventInstaller(el) {
		_(el)	.on( 'mouseenter', function(){ el.classList.   add('open') } )
				.on( 'mouseleave', function(){ el.classList.remove('open') } )
	}

	_.cn("footnote").each( function(el) {
		mouseEventInstaller( el );
	} )

	_("aside").each( function(el) {
		el.classList.add( 'aside' );
		mouseEventInstaller( el );
	} )

});

