/* Code further maintained at [git:~/code/js3d/lib/]_.js  */
/**
 *
 * @author Kenney Westerhof <kenney@neonics.com>
 */
(function(window, undefined){
	"use strict";

	function log() {
		if ( log.level == 0 || log.indent >= log.level ) return; //  0 && log.indent - log.level > 0 ) return;
		var args = [/*"(",log.indent, log.level,")",*/ "  ".repeat(log.indent)];
		for ( var i in arguments ) args.push( arguments[i] );	// arguments is not a real array

		console.log.apply( console.log, args );
	}
	log.indent = 0;
	log.level = 0;
	function logopen()	{ 				log.apply(null, arguments); log.indent++ }
	function logclose()	{ log.indent--; log.apply(null, arguments); 			 }


	logopen("Initializing", 'this',this,'args',arguments);

	var
		rootLib,
		lib = function(sel, ctx ) {
			logopen("MAIN FUNC", arguments);
			var ret= new lib.fn.init( sel, ctx, rootLib );
			logclose("RET: ", ret );
			return ret;
		},

		getclass = function(obj) { return obj.constructor.toString().match( /function (\w+)/ )[1]; },

		loaded = function() {
			log("DOMContentLoaded", rootLib.events, lib.events );//this, "lib: ", lib);

			if ( document.addEventListener ) document.removeEventListener( "DOMContentLoaded", loaded, false );
			else if ( document.readyState == "complete" ) document.detachEvent( "onreadystatechange", loaded );

			lib.ready();
		}
	;


// contextualized instance methods
lib.fn = lib.prototype = {
		constructor: lib,

		// the actual constructor
		init: function(sel,ctx,root) {
			var t = typeof(sel),
				c = t == 'object' ? getclass( sel ) : undefined
				;

			if (!sel) return this;
			switch ( t )
			{
				case 'string':		sel = document.querySelectorAll( sel ); // fallthrough to 'object' or 'array'
				case 'object':		
				case 'array':		this.context = this[0] = sel; return this;
				case 'function':	lib.events.onload.push( sel ); return this;
				default: log(t, "UNKNOWN"); return this;
			}
		},

		on: function(e,f) { return this.each( function(el) { el['on'+e] = f; } ) },

		each: function(cb) {
			if ( this.context.nodeType ) {
				cb.call( this, this.context );
			}
			else if ( this.context.length ) {
				for ( var i = 0; i < this.context.length; i ++ )
					cb.call( this, this.context[i], i );
			}
			else
				console.warn( "unknown context: ", this.context,
				"\n",(new Error()).stack );
			return this;
		},


		// utility
		prependChild: function(newChild) {
			//console.log(this,arguments);
			if ( newChild instanceof HTMLCollection )
				for ( var i = newChild.length -1; i >= 0; i -- )
					newChild = this.context.insertBefore( newChild.item(i), this.context.firstChild );
			else
				console.warn( "prependChild: don't know how to handle ", newChild );
		},
		appendChild: function(newChild) {
			//console.log(this,arguments);
			if ( newChild instanceof HTMLCollection )
				for ( var i = newChild.length -1; i >= 0; i -- )
					newChild = this.context.appendChild( newChild.item(i) );
			else
				console.warn( "prependChild: don't know how to handle ", newChild );
		},




		data: function(name) {
			return this.context.getAttribute( "data-" + name );
		},

	};

lib.fn.init.prototype = lib.fn;
lib.extend = lib.fn.extend = function() {
	if ( arguments.length != 1 )
	{
		log("multi-arg extend not implemented");
		return;
	}

	for ( var i = 0, options = null; i < arguments.length; i ++ )
		if ( (options=arguments[i]) != null )
			for ( var name in options )
				this[name] = options[name]; // not deep copy

	return this;
};


// static methods
lib.extend({
	events: {
		onload: []
	},

	ready: function() {
		log("another ready!", this.events);
			for ( var i in this.events.onload )
			{
				log("calling", this.events.onload[i], "with", this);
				lib.events.onload[i].call(this, this);
			}

	},

	cn: function(cssclass)    { return new lib( document.getElementsByClassName( cssclass ) ); },
	en: function(elementName) { return new lib( document.getElementsByClassName( cssclass ) ); }, // XXX should contextualize for chaining


	html: function(htmlText) {
		var el = document.createElement( "div" );
		el.innerHTML = htmlText;
		return el.children;
	},
});


	rootLib = lib( document );
	window._ = lib;	//	export
	document.addEventListener( "DOMContentLoaded", loaded, false );

	logclose("initialized", _ );

})(window);


/* Usage example:

_(function(_) {
	_.cn("footnote").each( function(el) {
		_(el)
			.on( 'mouseenter', function(){console.log("ENTER", this, arguments); el.classList.add('open')} )
			.on( 'mouseleave', function(){console.log("LEAVE", this, arguments); el.classList.remove('open')} )
	} )
});

*/
