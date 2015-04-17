


start=1;    /* This is used to avoid multiplication etc
	 * when there is only the value '1' in the
	 * buffer. */
wvalue=0;       /* The 'value' of the window */
// start..end = window top..bottom
wstart=bits-1;  /* The top bit of the window */

if (!BN_one(r)) goto err;

for (;;)
0:{
	if ( !( P & ( 1<<wstart ) ) )
	{					//	cmpd	[start], 0
		if (!start)			//	jnz	1f
			R *= R % M
	1:	if (wstart == 0) break;		//	decb 	[wstart]
		wstart--;			//	js 	0f
		continue;			//	jmp	0b
	}
	/* We now have wstart on a 'set' bit, we now need to work out
	 * how bit a window to do.  To do this we need to scan
	 * forward until the last set bit before the end of the
	 * window */
	{
		wvalue=1;			//	mov	[wvalue], 0
		wend=0;				//	mov	[wend], 0
	3:	for (i=1; i<window; i++)	//	mov	edx, 1
						//	jmp	2f
		{
						//	mov	ecx, [wstart]
			TMP = wstart - i;	//	sub	ecx, edx
			if (TMP < 0) break;	//	js	1f
						//	mov	eax, [BN_P]
			if (BN_is_bit_set(p,TMP))//	call	bignum_get_bit
			{			//	jnc	2f
						//	mov	ecx, edx
				wvalue<<=(i-wend);//	shld	[wvalue], cl
				wvalue|=1;	//	orb	[wvalue], 1
				wend=i;		//	mov	[wend], edx
	2:		}
						//	cmp	edx, [window]
		}				//	jb	3b
	1:

		/* add the 'bytes above' */
		if (!start)
		{				//	mov	ecx, [wend]
			for (i=0; i<=wend; i++)	//	inc	ecx
	3:			R *= R % M	//
		}				//	loop 3b
		start=0;

		/* wvalue will be an odd number < 2^window */
		R *= VAL[wvalue>>1] % M

		/* move the 'window' down further */
		wvalue=0;			//	mov	[wvalue], 0
						//	mov	eax, [wend]
						//	inc	eax
		if ( wstart -= wend+1 < 0 )	//	sub	[wstart], eax
			break;			//	jns	0b
	}
0:}
