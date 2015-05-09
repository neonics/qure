/** @author: <kenney@neonics.com> */

_(function(_) {

	function mouseEventInstaller(el) {
		_(el)	.on( 'mouseenter', function(){console.log("ENTER", this, arguments); el.classList.add('open')} )
				.on( 'mouseleave', function(){console.log("LEAVE", this, arguments); el.classList.remove('open')} )
	}


	_.cn("footnote").each( function(el) {
		mouseEventInstaller( _(el) );
	} )

	_("aside").each( function(el) {
		el.classList.add( 'aside' );
		mouseEventInstaller( el );
	} )

});

