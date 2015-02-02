
		var DEBUG = true;
		var debugstr="";

		function flushDebug()
		{
		  document.getElementById("debug").innerHTML=debugstr;
		}

		function clearDebug()
		{
			debugstr="";
		}


		function debug(str)
		{
		  //document.getElementById("debug").textContent+=str;
			debugstr += str+"<br>\n";
			flushDebug();
		}

		function debugObject(obj)
		{
			var s = obj + "{ ";
			for ( var a in obj )
			{
				try{
				s += " " + a + "=" + eval("obj."+a +"");
				}catch ( e) {s+="(ERR:"+e+")";}
			}
			s += " }";
			debug(s);
		}

		function debugCoords(x, y)
		{	
			document.getElementById("coords").textContent=
				"(" +  x	+ ", " + y + ")";
		}

		function debugEl( n, s )
		{
			document.getElementById(n).textContent=s;
		}


/**
 * @return radians
 */
function angle( a, b )
{
	var z = Math.sqrt( a*a + b*b );
	z = z == 0 ? 1 : z;
	var ang = Math.acos( a / z );
	return Math.asin( b / z ) < 0 ? Math.PI * 2 - ang : ang;
}

/**
 * http://en.wikipedia.org/wiki/HSL_and_HSV
 * @param h: 0-360
 * @param s: 0..1
 * @param v: 0..1
 */
function color(h,s,v)
{
	h %= 360; h= h < 0 ? h+=360: h;
	var c = v * s;
	var h2 = h / 60.0;
	var x = c * (1 - Math.abs( (h2 % 2) -1) );

	var rgb1;
	if ( h2 < 1 )
		rgb1 = new Array(c, x, 0);
	else if ( h2 < 2 )
		rgb1 = new Array(x, c, 0);
	else if ( h2 < 3 )
		rgb1 = new Array(0, c, x);
	else if ( h2 < 4 )
		rgb1 = new Array(0, x, c);
	else if ( h2 < 5 )
		rgb1 = new Array(x, 0, c);
	else if ( h2 < 6 )
		rgb1 = new Array(c, 0, x);
	else debug("H out of range: " + h );

	var m = v - c;
	var foo = [rgb1[0] + m, rgb1[1] + m, rgb1[2] + m];
//debug("Col: " + h+","+s+","+v + "  rgb: " + foo );
	return foo;
}

function calccolor(angle, alpha)
{
	if ( typeof( alpha ) === 'undefined' ) alpha=1;

	var rgb = color(angle,1,1);//angles[0], 1, 1 );
	var red = Math.round(rgb[0] * 255);
	var green = Math.round(rgb[1] * 255);
	var blue = Math.round(rgb[2] * 255);

  return "rgba("
			+red +","
			+green+"," 
			+blue +","
			+alpha
			+")";
}

function color2str( c, a )
{
	return "rgba("
		+Math.round(c[0]*255)+","
		+Math.round(c[1]*255)+"," 
		+Math.round(c[2]*255)+","
		+(typeof(a)==='undefined'?c[3]:a)
		+")";
}


		function deg(rad)
		{
			return rad * 180 / Math.PI;
		}

		function rad(deg)
		{
			return deg * Math.PI / 180;
		}

function clip(val, min, max)
{
	return val < min ? min : val > max ? max : val;
}
function deg(rad)
{
	return rad * 180 / Math.PI;
}

function rad(deg)
{
	return deg * Math.PI / 180;
}

function Matrix()
{
	for ( i = 0; i < 16; i++ )
	{
		this[i] = i % 5 == 0 ? 1 : 0;
	}

	this.debug = function()
	{
		var s = "";
		for (y=0; y<4; y++)
		{
			for (x=0; x<4; x++)
			{
				s += this[y*4+x].toFixed(2) + ", ";
			}
			s += "\n";
		}
		debugEl( "matrix", s );
	};


	this.projection__ = function()
	{
		var n = 1, f = 100;
		var Q = 10;
		var t=0, b=+Q;
		var l=0, r=+Q;
		var realproj = new Matrix();
		realproj[0+0]= (2*n)/(r-l); realproj[0+2]= (r+l)/(r-l);
		realproj[4+1]= (2*n)/(t-b); realproj[4+2]= (t+b)/(t-b);
		realproj[8+2]=-(f+n)/(f-n); realproj[8+3]=-2*f*n/(f-n);
		realproj[12+2]= -1;

		//realproj = translate(realproj, w/2, h/2, 0);
		return realproj;
	};

	this.ortho = function(l,r,t,b,n,f)
	{
		var m = new Matrix();
		for ( i=0;i<16;i++) m[i]=0;

		m[0]= 2.0/(r-l);
		m[3]=-1.0*(r+l)/(r-l);
		m[5]= 2.0/(t-b);
		m[7]=-1.0*(t+b)/(t-b);
		m[10]=-2.0/(f-n);
		m[11]=-1.0*(f+n)/(f-n);
		m[15]=1;
		return m;
	};

	this.projection = function(w,h,fov)
	{
		var mode=1;

		var fovy = fov;//1.0 * h/w;
		var f = 1.0 / Math.tan( fovy / 2 *Math.PI/180.0);
		var aspect = 1.0 * w/h;
		var far = 10240;
		var near = mode==4 ? w/2 : 1;

		var m = new Matrix();
		for (i=0;i<16;i++) m[i]=0;


		switch (mode)
		{
			case 1:
			{
				var a=-1.0*far/(far-near);
				var b=-1.0;
				var c=-1.0*far*near/(far-near);
				var s= 1.0/Math.tan( fov/2 * Math.PI / 180.0 );

				m[ 0]=s; m[ 1]=0; m[ 2]=0; m[ 3]=0;
				m[ 4]=0; m[ 5]=s; m[ 6]=0; m[ 7]=0;
				m[ 8]=0; m[ 9]=0; m[10]=a; m[11]=b;
				m[12]=0; m[13]=0; m[14]=c; m[15]=0;
				break;
			}
			case 2:
			{
				//near=-near; far=-far;
				//f=-f;

				m[0*4+0] = f / aspect;

				m[1*4+1] = f;

				m[2*4+2] = 1.0*(near+far)/(near-far);//m[2*4+2]=1.0*(far-near)/(far+near);
				m[2*4+3] = 2.0*near*far/(near-far);

				m[3*4+2] = -1;

				// this matrix returns clip coords.
				// viewport[x,y,z] = clip[x,y,z]/w (w=-z);
				break;
			}
			case 3:
			{
				// from ImageUtil.java
				m[0*4+0] = f / aspect;

				m[1*4+1] = f;

				m[2*4+2] = 1.0*(near+far)/(near-far);//(far-near)/(far+near);
				m[2*4+3] = -1;

				m[3*4+2] = 2.0*near*far/(near-far);
				m[3*4+3] = 0;
				break;
			}
			case 4:
			{
				// eye coords -> clip coords -> normalized device coords (NDC)
				var f = far;
				var n = near;
				var t = h, b = 0, l=0, r=w;

				// map [l,r]->[-1,1] (and [t,b]->[-1,1])
				m[ 0]=2.0*n/(r-l); m[ 2]=1.0*(r+l)/(r-l);
				m[ 5]=2.0*n/(t-b); m[ 6]=1.0*(t+b)/(t-b);
				m[10]=-1.0*(f+n)/(f-n); m[11]=-2.0*f*n/(f-n);
				m[12]=0; m[13]=0; m[14]=-1; m[15]=0;
				break;
			}
		}

		// translate to center
		m[3*4+0] = w/2;
		m[3*4+1] = h/2;

		return m;
	}

	this.rotate = function(a, x, y, z)
	{
		var m = this;
	  	var _ = new Matrix();
		var c = Math.cos( a );
		var s = Math.sin( a );
		var r = Math.sqrt( x*x + y*y + z*z);
		x/=r; y/=r; z/=r;

		// first row (vert)
		_[0 + 0] = ( x * x * ( 1 - c ) + c );
		_[0 + 1] = ( y * x * ( 1 - c ) + z * s );
		_[0 + 2] = ( z * x * ( 1 - c ) - y * s );
		_[0 + 3] = 0;

		// second row
		_[4 + 0] = ( x * y * ( 1 - c ) - z * s );
		_[4 + 1] = ( y * y * ( 1 - c ) + c );
		_[4 + 2] = ( z * y * ( 1 - c ) + x * s );
		_[4 + 3] = 0;

		// third row
		_[8 + 0] = ( x * z * ( 1 - c ) + y * s );
		_[8 + 1] = ( y * z * ( 1 - c ) - x * s );
		_[8 + 2] = ( z * z * ( 1 - c ) + c );
		_[8 + 3] = 0;

		// fourth row
		_[12 + 0] = 0;
		_[12 + 1] = 0;
		_[12 + 2] = 0;
		_[12 + 3] = 1;

		return this.mulmat( _ );
	}

	// matrix * matrix
	this.mulmat = function(b) 
	{
		var a = this;
		var c = new Matrix();

		c[0] = a[0] * b[0] + a[1] * b[4] + a[2] * b[8] + a[3] * b[12];
		c[1] = a[0] * b[1] + a[1] * b[5] + a[2] * b[9] + a[3] * b[13];
		c[2] = a[0] * b[2] + a[1] * b[6] + a[2] * b[10] + a[3] * b[14];
		c[3] = a[0] * b[3] + a[1] * b[7] + a[2] * b[11] + a[3] * b[15];

		c[4] = a[4] * b[0] + a[5] * b[4] + a[6] * b[8] + a[7] * b[12];
		c[5] = a[4] * b[1] + a[5] * b[5] + a[6] * b[9] + a[7] * b[13];
		c[6] = a[4] * b[2] + a[5] * b[6] + a[6] * b[10] + a[7] * b[14];
		c[7] = a[4] * b[3] + a[5] * b[7] + a[6] * b[11] + a[7] * b[15];

		c[8] = a[8] * b[0] + a[9] * b[4] + a[10] * b[8] + a[11] * b[12];
		c[9] = a[8] * b[1] + a[9] * b[5] + a[10] * b[9] + a[11] * b[13];
		c[10] = a[8] * b[2] + a[9] * b[6] + a[10] * b[10] + a[11] * b[14];
		c[11] = a[8] * b[3] + a[9] * b[7] + a[10] * b[11] + a[11] * b[15];

		c[12] = a[12] * b[0] + a[13] * b[4] + a[14] * b[8] + a[15] * b[12];
		c[13] = a[12] * b[1] + a[13] * b[5] + a[14] * b[9] + a[15] * b[13];
		c[14] = a[12] * b[2] + a[13] * b[6] + a[14] * b[10] + a[15] * b[14];
		c[15] = a[12] * b[3] + a[13] * b[7] + a[14] * b[11] + a[15] * b[15];

		return c;
	}

	this.translate = function(x, y, z)
	{
	  var _ = new Matrix();
	  _[12]=x;
	  _[13]=y;
	  _[14]=z;
	  _[15]=1;
//	  return _.mulmat(this);
	  return this.mulmat(_);
	}

	this.scale = function(x, y, z)
	{
	  var _ = new Matrix();
	  _[0+0]=x;
	  _[4+1]=typeof(y)==='undefined'?x:y;
	  _[8+2]=typeof(z)==='undefined'?x:z;
	  return this.mulmat(_);//this.mul(_, m);
	};

	// matrix * point
	this.mulvec = function(p)
	{
		var m = this;
		return new Point(
			m[0*4+0]*p[0] + m[1*4+0]*p[1] + m[2*4+0]*p[2] + m[3*4+0],// x
			m[0*4+1]*p[0] + m[1*4+1]*p[1] + m[2*4+1]*p[2] + m[3*4+1],// y
			m[0*4+2]*p[0] + m[1*4+2]*p[1] + m[2*4+2]*p[2] + m[3*4+2]// *4+// z
		);
	};

}

Matrix.prototype = new Array(16);


function Point(x, y, z, w)
{
	if ( typeof( x ) === 'undefined' ) x=0;
	if ( typeof( y ) === 'undefined' ) y=0;
	if ( typeof( z ) === 'undefined' ) z=0;
	if ( typeof( w ) === 'undefined' ) w=0;

	this[0]=x;this[1]=y;this[2]=z; this[3]=w;

	this.sub = function(p)
	{
		return new Point(this[0]-p[0], this[1]-p[1], this[2]-p[2], this[3]-p[3]);
	}

	this.cross = function(p)
	{
		return new Point(
			this[1]*p[2] - this[2]*p[1],
			this[2]*p[0] - this[0]*p[2],
			this[0]*p[1] - this[1]*p[0] );
	}

	this.in = function(p)
	{
		return new Point( this[0]*p[0], this[1]*p[1], this[2]*p[2] );
	}

	this.dot = function(p)
	{
		return this[0]*p[0] + this[1]*p[1] + this[2]*p[2];
	}

	this.add = function(p)
	{
		return new Point( this[0]+p[0], this[1]+p[1], this[2]+p[2], this[3]+p[3] );
	}

	this.normalize = function()
	{
		return this.mul( 1.0 / Math.sqrt( this.dot( this ) ) );
	}

	this.mul = function(f)
	{
		return new Point( this[0]*f, this[1]*f, this[2]*f, this[3]*f );
	}
}


Point.prototype = new Array(3);

function project(p)
{
	var vd = 1000.0;
	return [
		w/2 + p[0]*vd / (vd + p[2]),
		h/2 + p[1]*vd / (vd + p[2])
	];
}
function Mesh()
{
	this.center = function(m) {
		if ( this._center == null )
		{
			var c = new Point();
			for (i=0; i<this.vertices.length; i++)
			{
				c = c.add( this.vertices[i] );
			}

			this._center = c.mul( 1.0 / this.vertices.length );
		}

		return m.mulvec( this._center );
	}
}

function QuadMesh(v,q)
{
	this.vertices = new Array(v);
	this.quads = new Array(q);
}

QuadMesh.prototype = new Mesh();


function initQuadMesh(d)
{
	var mesh = new QuadMesh(8, 6);

	//var d = (w+h)/10;

	mesh.vertices[0] = new Point( -d, -d, +d );
	mesh.vertices[1] = new Point( +d, -d, +d );
	mesh.vertices[2] = new Point( +d, +d, +d );
	mesh.vertices[3] = new Point( -d, +d, +d );

	mesh.vertices[4] = new Point( -d, -d, -d );
	mesh.vertices[5] = new Point( +d, -d, -d );
	mesh.vertices[6] = new Point( +d, +d, -d );
	mesh.vertices[7] = new Point( -d, +d, -d );

	mesh.quads[0] = [3,2,1,0];//[0,1,2,3];
	mesh.quads[1] = [0,1,5,4];//[4,5,1,0];
	mesh.quads[2] = [1,2,6,5];//[5,6,2,1];
	mesh.quads[3] = [2,3,7,6];//[6,7,3,2];
	mesh.quads[4] = [0,4,7,3];//[3,7,4,0];
	mesh.quads[5] = [4,5,6,7];//[7,6,5,4];

	mesh.quads[0] = [0,1,2,3];
	mesh.quads[1] = [4,5,1,0];
	mesh.quads[2] = [5,6,2,1];
	mesh.quads[3] = [6,7,3,2];
	mesh.quads[4] = [3,7,4,0];
	mesh.quads[5] = [7,6,5,4];

	mesh.render = function(mm, alpha, color, handler) {
		renderQuadMesh( this, mm, alpha, color, handler );
	};

	mesh.renderNormals = 0;

	return mesh;
}

function renderQuadMesh(mesh, m, oalpha, colr, handler)
{
	// apply transformation
	var vert0 = new Array( mesh.vertices.length );
	var vert = new Array( mesh.vertices.length );
	for ( i=0; i< vert.length; i ++)
	{
		var v=mesh.vertices[i];
		vert0[i] = m.mulvec( v );
		vert[i] = project( vert0[i] );
	}

	var depth = new Array( mesh.quads.length );
	var normals = new Array( mesh.quads.length );
	var centers = new Array( mesh.quads.length );
	var quadidx = new Array( mesh.quads.length );

	for (q=0; q<mesh.quads.length; q++)
	{
		quadidx[q] = q;

		var a = vert0[ mesh.quads[q][0] ];
		var b = vert0[ mesh.quads[q][1] ];
		var c = vert0[ mesh.quads[q][2] ];
		var d = vert0[ mesh.quads[q][3] ];

		var center = a.add(b).add(c).add(d);
		center=center.mul(.25);

		var u = b.sub( c );
		var v = b.sub( a );
		var n = u.cross(v).normalize();
		// n[2] = direction of surface normal: face culling

		normals[q] = n;
		centers[q] = center;
		depth[q] = center[2];
	}

	quadidx.sort( function(a,b) { return depth[b] - depth[a]; } );

	mesh.front=new Array(0);
	mesh.frontcolor=new Array(0);
	mesh.frontcolor_rgba=new Array(0);
	alpha = clip(oalpha, 0, 1);
//	alpha = oalpha < 0.1 ? 0.1 : oalpha > .9 ? .9 : oalpha;
	for (j=0,i=0;i<quadidx.length;i++)
	{
		//if ( normals[ quadidx[i] ][2] > 0.1 )
		if ( normals[ quadidx[quadidx.length-1-i] ][2] < -0.1 )
		//if ( centers[ quadidx[i] ][2] > 0 )
		{
		mesh.front[j] = quadidx[quadidx.length-1-i];
		mesh.frontcolor_rgba[j] = color( 360.0 * mesh.front[j] / mesh.quads.length, 1, 1);
		mesh.frontcolor_rgba[j][3] = normals[quadidx[i]][2];
		mesh.frontcolor[j] = calccolor( 360.0 * mesh.front[j] / mesh.quads.length, alpha);
		j++;
		}
	}
	//debugEl("debug", "front faces: " + j );


	for ( q=0; q<quadidx.length; q++)
	{
		var quad = mesh.quads[ quadidx[q] ];

		if ( quad != null )
		{
			if ( 1 )	// render quads
			{
				var a = normals[ quadidx[q] ];
//				debugEl("debug", a[2]);

				ctx.beginPath();

				var alph=alpha*(0.6 + 0.4*(1-(a[2]+1)/2));	// depth alpha adjustment
				ctx.fillStyle = colr==null
					? calccolor(
						360.0 * quadidx[q] / mesh.quads.length,
						alph
						)
					: typeof(colr)=='number'
						? calccolor(colr*360,alph)
						: colr
					/*
						: typeof(colr)=='string' ? color2str( colr ) : colr
					*/
					;

				ctx.strokeStyle= "rgba(0,0,0,"+
					alpha*(0.6 + 0.4*(1-(a[2]+1)/2))	// depth alpha adjustment
					+")";
				for (i=0;i<4;i++)
				{
					var p = vert[ quad[i] ];
					if ( i == 0)
						ctx.moveTo( p[0], p[1] );
					else
						ctx.lineTo( p[0], p[1] );
				}
				ctx.closePath();
				ctx.fill();
				ctx.stroke();
			}

			alpha = alpha < 0 ? 0 : alpha > 1 ? 1 : alpha;

			if ( handler != null )
				handler( mesh, alpha, quadidx, normals, centers );
		}
	}
}


function quadhandler( mesh, alpha, quadidx, normals, centers )
{
debugEl("debug", "quadhandler, alpha="+alpha);
	//if ( mesh.renderNormals )	// render normals
	var alphathresh = 0.5;
	var maxalpha = 0.7
	if ( alpha > alphathresh )
	{
		var alp = (alpha - alphathresh) / ((maxalpha-alphathresh));
		ctx.save();
		var n = normals[ quadidx[q] ];
		var nrm = n;
		var center = centers[ quadidx[q] ];
		n=n.mul(50).add(center);
		n=project(n);////n=pm.mulvec(n);
		center=project(center);//center = pm.mulvec(center);

		ctx.fillStyle = calccolor( 360.0 * quadidx[q] / mesh.quads.length, alp);
		ctx.strokeStyle="rgba(0,0,0,"+alp+")";

//		ctx.fillRect( n[0], n[1], 4, 4);
//		ctx.fillRect( center[0], center[1], 8, 8);
		ctx.beginPath();
		ctx.moveTo(center[0], center[1]);
		ctx.lineTo(n[0], n[1]);
		ctx.closePath();
		ctx.fill(); ctx.stroke();
		ctx.font="20px Arial";
		ctx.fillText(menu[quadidx[q]].label, n[0], n[1] );
		ctx.strokeText(menu[quadidx[q]].label, n[0], n[1] );

		if ( 0 )
		{
			ctx.font="12pt Courier";

			var str="("
				+ nrm[0].toFixed(2) + ", "
				+ nrm[1].toFixed(2) + ", "
				+ nrm[2].toFixed(2)+")";

			ctx.strokeText(str, n[0], n[1]-20 );
		}

		ctx.restore();
	}
}


function TriMesh(v,q)
{
	this.vertices = new Array(v);
	this.tris = new Array(q);

	this.render = function(mm, alpha, col, handler) {
		renderTriMesh( this, mm, alpha, col, handler );
	};
}

TriMesh.prototype = new Mesh();

function initTriMesh(d)
{
	var mesh = new TriMesh(4,4);

	var mh = new Matrix().rotate( Math.PI*2/3, 1, 0, 0 );
	var mv = new Matrix().rotate( Math.PI*2/3, 0, 1, 0 );

	d *= Math.sqrt( 3.0/2 );

	mesh.vertices[0] = new Point( 0, -d, 0 );
	mesh.vertices[1] = mh.mulvec( mesh.vertices[0] );
	mesh.vertices[2] = mv.mulvec( mesh.vertices[1] );
	mesh.vertices[3] = mv.mulvec( mesh.vertices[2] );

	mesh.tris[0] = [0,1,2].reverse();
	mesh.tris[1] = [3,2,1].reverse();
	mesh.tris[2] = [0,2,3].reverse();
	mesh.tris[3] = [1,0,3].reverse();

	return mesh;
}

function renderTriMesh(mesh, m, oalpha, colr, handler)
{
	// apply transformation
	var vert0 = new Array( mesh.vertices.length );
	var vert = new Array( mesh.vertices.length );
	for ( i=0; i< vert.length; i ++)
	{
		var v=mesh.vertices[i];
		vert0[i] = m.mulvec( v );
		vert[i] = project( vert0[i] );
	}

	var depth = new Array( mesh.tris.length );
	var normals = new Array( mesh.tris.length );
	var centers = new Array( mesh.tris.length );
	var triidx = new Array( mesh.tris.length );

	for (q=0; q<mesh.tris.length; q++)
	{
		triidx[q] = q;

		var a = vert0[ mesh.tris[q][0] ];
		var b = vert0[ mesh.tris[q][1] ];
		var c = vert0[ mesh.tris[q][2] ];

		var center = a.add(b).add(c);
		center=center.mul(1.0/3);

		var u = b.sub( c );
		var v = b.sub( a );
		var n = u.cross(v).normalize();
		// n[2] = direction of surface normal: face culling

		normals[q] = n;
		centers[q] = center;
		depth[q] = center[2];
	}

	triidx.sort( function(a,b) { return depth[b] - depth[a]; } );

	mesh.front=new Array(0);
	mesh.frontcolor=new Array(0);
	mesh.frontcolor_rgba=new Array(0);
	alpha = clip( oalpha, 0, 1 );
	//alpha = oalpha < 0.1 ? 0.1 : oalpha > .9 ? .9 : oalpha;
	for (j=0,i=0;i<triidx.length;i++)
	{
		if ( normals[ triidx[triidx.length-1-i] ][2] < -0.06 )
		//if ( centers[ triidx[i] ][2] > 0 )
		{
		mesh.front[j] = triidx[triidx.length-1-i];
		mesh.frontcolor_rgba[j] = color( 360.0 * mesh.front[j] / mesh.tris.length, 1, 1);
		mesh.frontcolor_rgba[j][3] = normals[triidx[i]][2];
		mesh.frontcolor[j] = calccolor( 360.0 * mesh.front[j] / mesh.tris.length, alpha);
		j++;
		}
	}
	//debugEl("debug", "front faces: " + j  + ", " + mesh.tris.length);


	for ( q=0; q<triidx.length; q++)
	{
		var tri = mesh.tris[ triidx[q] ];

		if ( tri != null )
		{
			if ( 1 )	// render tris
			{
				var a = normals[ triidx[q] ];
//				debugEl("debug", a[2]);

				ctx.beginPath();
				ctx.fillStyle = calccolor( 360.0 * triidx[q] / mesh.tris.length,
					alpha*0.6 + 0.4*(1-(a[2]+1)/2)	// depth alpha adjustment
				);
				for (i=0;i<3;i++)
				{
					var p = vert[ tri[i] ];
					if ( i == 0)
						ctx.moveTo( p[0], p[1] );
					else
						ctx.lineTo( p[0], p[1] );
				}
				ctx.closePath();
				ctx.fill();
				ctx.stroke();
			}

			alpha = alpha < 0 ? 0 : alpha > 1 ? 1 : alpha;

			if ( handler != null )
				handler( alpha, normals, centers );
		}
	}

}



function trihandler( alpha, normals, centers )
{
	if ( 0 ) { // mesh.renderNormals )	// render normals
	var alphathresh = 0.7;
	if ( alpha > alphathresh )
	{
		var alp = (alpha - alphathresh) / (1.0-alphathresh);
		ctx.save();
		var n = normals[ triidx[q] ];
		var nrm = n;
		var center = centers[ triidx[q] ];
		n=n.mul(50).add(center);
		n=project(n);
		center = project(center);

		ctx.fillStyle = calccolor( 360.0 * triidx[q] / mesh.tris.length, alp);
		ctx.strokeStyle="rgba(0,0,0,"+alp+")";

		ctx.fillRect( n[0], n[1], 4, 4);
		ctx.fillRect( center[0], center[1], 8, 8);
		ctx.beginPath();
		ctx.moveTo(center[0], center[1]);
		ctx.lineTo(n[0], n[1]);
		ctx.closePath();
		ctx.fill(); ctx.stroke();
		ctx.font="20px Arial";
		ctx.fillText(menu[triidx[q]].label, n[0], n[1] );
		ctx.strokeText(menu[triidx[q]].label, n[0], n[1] );

		if ( 0 )
		{
			ctx.font="12pt Courier";

			var str="("
				+ nrm[0].toFixed(2) + ", "
				+ nrm[1].toFixed(2) + ", "
				+ nrm[2].toFixed(2)+")";

			ctx.strokeText(str, n[0], n[1]-20 );
			ctx.restore();
		}
	}
	}
}

		var canvas, ctx;

		var tetra;
		var cube;

		var foo=0;

		var lock = 0;

		var mx=1000, my=0;
		var ox, oy;
		var w, h;
		var canvasscale=1;


var mox, moy;
var scaledelay=0;
var scaledir = 0;

var unit;
		function init()
		{
			canvas = document.getElementById( "canvas" );
			ctx = canvas.getContext( "2d" );

			w = canvas.clientWidth; xo=w/2;
			h = canvas.clientHeight; yo=w/2;
			ox = canvas.offsetLeft;//clientLeft;=0
			oy = canvas.offsetTop;//clientTop;

			canvasscale = 1.0 * w/400;

			ctx.fillStyle="black";
			ctx.fillRect(0,0,w,h);

			//debug("WxH="+w+"x"+h);

			unit = w/6;//Math.sqrt(w*w+h*h)/3;
			tetra = initTriMesh(unit);
			cube = initQuadMesh(unit/2);

			var lx=0, ly=0;

			canvas.onmousedown = function(e) { lock^=1; };

			canvas.onmousemove = function(e)
			{
				if ( lock ) return;

				var x = e.clientX - canvas.offsetLeft + document.documentElement.scrollLeft;
				var y = e.clientY - canvas.offsetTop + document.documentElement.scrollTop;

				mox=x;moy=y;

				// rel center
				var _x = x - w/2;
				var _y = y - h/2;
				var r = Math.sqrt( _x*_x + _y*_y );

				foo = unit / r;	// alpha

				if ( lx != null )
				{
					var dx = x-lx;
					var dy = y-ly;
				}
				lx=x;
				ly=y;
				//debugEl("debug", "(" + dx + ", " + dy + ")");

				mx = _x;//x-w/2;
				my = _y;//y-h/2;
//				scaledelay=0;//5 * fps;
				var dist = Math.sqrt(mx*mx+my*my);
				if ( dist > 100 * canvasscale )
				{
					if ( scaledir >= 0 )
					scaledelay=5;
					scaledir=-.1;
				}
				else
				{
					if ( scaledir <= 0 )
					scaledelay=0;
					scaledir=+.1;
				}

				if ( r < 3*unit )
				{
					impetus[0]+=dx/20.0;
					impetus[1]+=dy/20.0;
				}

				if ( 0 )	// coordinate problem..
				{
					ctx.save();
					ctx.fillStyle="black";
					ctx.fillRect( mx-2, my-2, 4, 4 );
					ctx.restore();
				}

			};
		}

		var frame=0;
		var fps = 25;

		var angles=[0,0];
		var impetus=[10,7];

		function render()
		{
			if ( Math.abs(impetus[0]) > 0.001 || Math.abs(impetus[1]) > 0.001 )
			{

				ctx.save();
				//ctx.fillStyle="black";
				ctx.clearRect( 0,0,w,h );
				ctx.restore();

				{
					var mm = new Matrix().scale(canvasscale); // model matrix
					mm = mm.rotate( angles[0], 0, 1, 0 );
					mm = mm.rotate( angles[1], 1, 0, 0 );

					angles[0] += 1.0 * impetus[0] / fps;
					angles[1] += 1.0 * impetus[1] / fps;

					ctx.strokeStyle = lock ? "red" : "black";

					var threshdist = 100*canvasscale;
					var dist = Math.sqrt( mx*mx + my*my );
					if ( clip(scaledelay,0,1)==0)//dist > threshdist )
					{
						tetra.render( mm, foo );
					}
					else
					{
						//var s = 1-1.0*dist/threshdist * (1-clip(scaledelay/100, 0,1));
						var s = clip(scaledelay, 0,1);
						var m1 = new Matrix().scale(canvasscale).translate(0,1.5*unit,0).scale(s);
						var m2 = m1.rotate(2*Math.atan(Math.sqrt(2)), 1, 0, 0);
						var m3 = m2.rotate(Math.PI*2/3, 0, 1, 0);
						var m4 = m3.rotate(Math.PI*2/3, 0, 1, 0);
						m1 = m1.mulmat( mm );
						m2 = m2.mulmat( mm );
						m3 = m3.mulmat( mm );
						m4 = m4.mulmat( mm );

						var scene = [
							{ id: 0, mesh: tetra, matrix: mm },
							{ id: 1, mesh: cube,  matrix: m1, color:.25 },
							{ id: 2, mesh: cube,  matrix: m2, color:.5 },
							{ id: 3, mesh: cube,  matrix: m3, color:.75 },
							{ id: 4, mesh: cube,  matrix: m4, color:.0 }
						];

						scene.sort( function(a,b) {
							var _a = a.mesh.center(a.matrix)[2];
							var _b = b.mesh.center(b.matrix)[2];
		//					return b.mesh.center(a.matrix)[2] - a.mesh.center(b.matrix)[2]
							return _a < _b ? 1 : _a > _b ? -1 : 0;
						} );

						var str="";
						var match=null;

						for (var i=0; i < scene.length; i++)
						{
							var me = scene[i].mesh;
							var ma = scene[i].matrix;
							var p = project( me.center(ma) );
							var dst=[p[0]-w/2-mx, p[1]-h/2-my];
							dst = Math.sqrt( dst[0]*dst[0] + dst[1]*dst[1] );
							if ( dst < unit/2 )
							{
								match=scene[i];
							}

						}

						for (var i=0; i < scene.length; i++)
						{
							var me = scene[i].mesh;
							var ma = scene[i].matrix;

							var a = me == tetra ? foo :
								1-clip(1.0*dist/threshdist, .1,.9);

							var c = me.center(ma);
							var p=project(c);

							if ( match!=null && scene[i].id == match.id )
							{
								me.render( ma, a, 
									scene[i].color == null ? null :
									color2str(
										color( 360*(scene[i].color + Math.sin(frame/6.1)/12), 1,1 ),
										Math.sin(frame/4.1)/3.0+0.5
									)
								);
							}
							else
							{
								me.render( ma, a, scene[i].color );
							}
						}

						if ( match != null && match.id > 0 )
						{
							var el = document.getElementById("link");
							el.textContent = "";
							var sp = el.appendChild( document.createElement("span") );
							sp.style.backgroundColor = calccolor( 360 * match.color );
							sp.textContent= menu[match.id-1].label;
						}

						//debugEl( "debug", "scaledelay " + scaledelay + " --- " + str );
					}

/*
					for (i=0; i<tetra.front.length; i++)
					{
						ctx.fillStyle = tetra.frontcolor[i];
						ctx.strokeRect(i*25, 0, 20, 20 );
						ctx.fillRect( i*25+1, 1, 18, 18 );
					}

					var el = document.getElementById("link");
					if ( tetra.front.length == 1 )
					{
						el.textContent = menu[tetra.front[0]].label;
						var col = color( 360 * tetra.front[0]/tetra.tris.length, 1, 1);
						var f=128, b=127;
						 col = "rgb(" + (b+f*col[0]) + ","+(b+f*col[1]) + ","+(b+f*col[2])+")";
						//el.style.color = "white";
						el.style.backgroundColor = col;
					}
					else if ( ! lock )
					{
						el.textContent = "(roll the dice; click to toggle lock)";
						el.style.backgroundColor = "white";
					}
	*/
				}
					
				frame++;
				//scaledelay--;
				scaledelay += scaledir;
				/*
				debugEl( "debug", "["+ox+","+oy+"] "+ "("+mx+", "+my+") frame " +frame
					+ " scaledelay " + scaledelay.toFixed(2) + " dir " + scaledir
					+ " SC " + canvasscale);
				*/
			}
			else
			{
				//debugEl( "debug", "pause" );
			}

			impetus[0] /= 1.05;
			impetus[1] /= 1.05;

			setTimeout( render, 1000/fps );
		}

		var menu = [
			{ label:"0 Issues" },
			{ label:"1 Philosophy" },
			{ label:"2 Source" },
			{ label:"3 Documentation" },
			{ label:"Development" },
			{ label:"Contact" }
		];
