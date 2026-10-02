// One-command capture for the three.js look-dev spike.
//   node capture.mjs            -> full packet into review/archive/bakeoff/B/
//   node capture.mjs test       -> a handful of stills into out/test/ (quick look-dev)
//   node capture.mjs stills|sheets|video|perf   -> just that stage (packet dir)
// Serves this folder plus the shared game data/textures, drives headed Chrome (WebGPU) with Playwright,
// renders with a fixed 30 fps timestep, reads pixels back from the canvas.

import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { spawn, execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { chromium } from 'playwright-core';

const HERE = path.dirname( fileURLToPath( import.meta.url ) );
const ROOT = path.resolve( HERE, '..', '..' );
const OUT = path.join( HERE, 'out' );
const PACKET = path.join( ROOT, 'review', 'archive', 'bakeoff', 'B' );
const FFMPEG = process.env.FFMPEG || path.join( process.env.LOCALAPPDATA || '', 'Microsoft', 'WinGet', 'Links', 'ffmpeg.exe' );
const CHROME = process.env.CHROME || 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe';
const PY = process.env.PYTHON || 'python';
const mode = process.argv[ 2 ] || 'all';
const extraQuery = process.argv[ 3 ] || '';

const shots = JSON.parse( fs.readFileSync( path.join( HERE, 'data', 'shots_4242.json' ), 'utf8' ) );
const track = JSON.parse( fs.readFileSync( path.join( HERE, 'data', 'track_4242.json' ), 'utf8' ) );

const MIME = { '.js': 'text/javascript', '.mjs': 'text/javascript', '.html': 'text/html', '.json': 'application/json', '.png': 'image/png', '.m4a': 'audio/mp4' };
const routes = [
	[ '/data/', path.join( HERE, 'data' ) ],
	[ '/level/', path.join( ROOT, 'game', 'data' ) ],
	[ '/tex/', path.join( ROOT, 'game', 'assets', 'textures', 'level0' ) ],
	[ '/node_modules/', path.join( HERE, 'node_modules' ) ],
	[ '/src/', path.join( HERE, 'src' ) ],
];

let videoSink = null;
const server = http.createServer( ( req, res ) => {
	const url = new URL( req.url, 'http://x' );
	if ( req.method === 'POST' ) {
		const chunks = [];
		req.on( 'data', ( c ) => chunks.push( c ) );
		req.on( 'end', () => {
			const buf = Buffer.concat( chunks );
			if ( url.pathname === '/video' ) {
				if ( videoSink ) { const ok = videoSink.stdin.write( buf ); if ( ! ok ) { videoSink.stdin.once( 'drain', () => res.end( 'ok' ) ); return; } }
			} else if ( url.pathname === '/file' ) {
				const p = url.searchParams.get( 'p' );
				fs.mkdirSync( path.dirname( p ), { recursive: true } );
				fs.writeFileSync( p, buf );
			} else if ( url.pathname === '/log' ) {
				console.log( '[page]', buf.toString() );
			}
			res.end( 'ok' );
		} );
		return;
	}
	let file = null;
	if ( url.pathname === '/' || url.pathname === '/index.html' ) file = path.join( HERE, 'index.html' );
	else for ( const [ pre, dir ] of routes ) if ( url.pathname.startsWith( pre ) ) { file = path.join( dir, decodeURIComponent( url.pathname.slice( pre.length ) ) ); break; }
	if ( ! file || ! fs.existsSync( file ) ) { res.statusCode = 404; res.end( 'nf' ); return; }
	res.setHeader( 'Content-Type', MIME[ path.extname( file ) ] || 'application/octet-stream' );
	res.setHeader( 'Cache-Control', 'no-store' );
	fs.createReadStream( file ).pipe( res );
} );

function log( ...a ) { console.log( new Date().toISOString().slice( 11, 19 ), ...a ); }

async function launch( port ) {
	const browser = await chromium.launch( {
		executablePath: CHROME, headless: false,
		args: [ '--enable-unsafe-webgpu', '--force_high_performance_gpu', '--disable-gpu-vsync', '--disable-frame-rate-limit',
			'--disable-backgrounding-occluded-windows', '--disable-renderer-backgrounding', '--disable-background-timer-throttling',
			'--window-position=0,0', '--window-size=1280,760', '--ignore-gpu-blocklist', '--enable-webgpu-developer-features', '--no-proxy-server', '--proxy-bypass-list=*' ]
	} );
	const ctx = await browser.newContext( process.env.NO_VIEWPORT ? { viewport: null } : { viewport: { width: 2560, height: 1440 }, deviceScaleFactor: 1 } );
	const page = await ctx.newPage();
	page.on( 'console', ( m ) => { const t = m.text(); if ( m.type() === 'error' || m.type() === 'warning' ) console.log( '[console]', m.type(), t.slice( 0, 400 ) ); } );
	page.on( 'pageerror', ( e ) => console.log( '[pageerror]', e.message ) );
	try {
		await page.goto( `http://127.0.0.1:${port}/index.html?${extraQuery}` );
		await page.waitForFunction( () => window.APP && ( window.APP.status === 'ready' || window.APP.status.startsWith( 'error' ) ), null, { timeout: 150000 } );
	} catch ( e ) { await browser.close(); throw e; }
	const st = await page.evaluate( () => window.APP.status );
	if ( st !== 'ready' ) { await browser.close(); throw new Error( st ); }
	const info = await page.evaluate( () => window.APP.adapterInfo );
	log( 'GPU adapter:', JSON.stringify( info ) );
	if ( ! info || ! /nvidia/i.test( JSON.stringify( info ) ) ) log( 'WARNING: adapter does not look like the NVIDIA GPU' );
	return { browser, page, info };
}

// in-page helpers
async function renderTrackRange( page, i0, i1 ) {
	await page.evaluate( async ( [ a, b ] ) => {
		const APP = window.APP;
		APP.resetExposure();
		for ( let i = a; i <= b; i ++ ) { APP.setTrackFrame( i ); APP.render( 1 / 30 ); }
	}, [ i0, i1 ] );
}
async function savePNG( page, file ) {
	await page.evaluate( async ( p ) => {
		const blob = await window.APP.grab( 'image/png' );
		await fetch( '/file?p=' + encodeURIComponent( p ), { method: 'POST', body: blob } );
	}, file );
}
function trackIndex( frameNo ) {
	const i = track.frames.findIndex( ( f ) => f[ 0 ] === frameNo );
	return i >= 0 ? i : Math.min( track.frames.length - 1, frameNo - 1 );
}

async function stills( page, dir ) {
	await page.evaluate( () => window.APP.setSize( 2560, 1440 ) );
	const names = Object.keys( shots.frames ).sort();
	for ( const n of names ) {
		const s = shots.frames[ n ];
		if ( s.kind === 'track' ) {
			const idx = trackIndex( s.render_frame );
			await renderTrackRange( page, Math.max( 0, idx - 30 ), idx );
		} else {
			await page.evaluate( async ( p ) => {
				const APP = window.APP; APP.resetExposure(); APP.setPose( p );
				for ( let i = 0; i < 60; i ++ ) APP.render( 1 / 30 );
			}, s );
		}
		await savePNG( page, path.join( dir, 'frames', n ) );
		log( 'still', n );
	}
}

async function sheets( page, dir ) {
	await page.evaluate( () => window.APP.setSize( 2560, 1440 ) );
	const tmp = path.join( OUT, 'sheetcells' );
	fs.rmSync( tmp, { recursive: true, force: true } ); fs.mkdirSync( tmp, { recursive: true } );
	const spec = {};
	for ( const [ name, frames ] of Object.entries( shots.sheets ) ) {
		spec[ name ] = [];
		const first = trackIndex( frames[ 0 ] );
		const last = trackIndex( frames[ frames.length - 1 ] );
		await renderTrackRange( page, Math.max( 0, first - 30 ), first - 1 );
		for ( let i = first; i <= last; i ++ ) {
			await page.evaluate( ( k ) => { window.APP.setTrackFrame( k ); window.APP.render( 1 / 30 ); }, i );
			const fno = track.frames[ i ][ 0 ];
			if ( frames.includes( fno ) ) {
				const f = path.join( tmp, `${name}_${fno}.png` );
				await savePNG( page, f );
				spec[ name ].push( f );
			}
		}
		log( 'sheet cells', name );
	}
	fs.writeFileSync( path.join( tmp, 'spec.json' ), JSON.stringify( { out: path.join( dir, 'sheets' ), sheets: spec } ) );
	execFileSync( PY, [ path.join( HERE, 'make_sheets.py' ), path.join( tmp, 'spec.json' ) ], { stdio: 'inherit' } );
}

async function video( page, dir ) {
	await page.evaluate( () => window.APP.setSize( 1920, 1080 ) );
	fs.mkdirSync( path.join( dir, 'video' ), { recursive: true } );
	const outFile = path.join( dir, 'video', 'clip.mp4' );
	const n = track.frames.length;
	videoSink = spawn( FFMPEG, [ '-y', '-loglevel', 'error', '-f', 'image2pipe', '-framerate', '30', '-c:v', 'mjpeg', '-i', '-',
		'-i', path.join( HERE, 'data', 'audio_4242.m4a' ), '-map', '0:v', '-map', '1:a',
		'-vf', 'scale=in_range=pc:out_range=tv,format=yuv420p', '-c:v', 'libx264', '-preset', 'medium', '-crf', '19', '-pix_fmt', 'yuv420p', '-color_range', 'tv', '-r', '30', '-c:a', 'copy', '-movflags', '+faststart', outFile ], { stdio: [ 'pipe', 'inherit', 'inherit' ] } );
	const done = new Promise( ( r ) => videoSink.on( 'close', r ) );
	const t0 = Date.now();
	const CH = 30;
	for ( let a = 0; a < n; a += CH ) {
		const b = Math.min( n - 1, a + CH - 1 );
		await page.evaluate( async ( [ a, b ] ) => {
			const APP = window.APP;
			if ( a === 0 ) APP.resetExposure();
			for ( let i = a; i <= b; i ++ ) {
				APP.setTrackFrame( i ); APP.render( 1 / 30 );
				const blob = await APP.grab( 'image/jpeg', 0.95 );
				await fetch( '/video', { method: 'POST', body: blob } );
			}
		}, [ a, b ] );
		if ( a % 300 === 0 ) log( `video ${b + 1}/${n}  (${( ( Date.now() - t0 ) / 1000 ).toFixed( 0 )} s)` );
	}
	videoSink.stdin.end();
	await done;
	videoSink = null;
	log( 'video written', outFile );
}

async function perf( page, dir, info ) {
	await page.evaluate( () => window.APP.setSize( 2560, 1440 ) );
	const r = await page.evaluate( async () => {
		const APP = window.APP, fr = APP.track.frames;
		const WARM = 4000, MEAS = 40000;
		return await new Promise( ( resolve ) => {
			const times = []; let t0 = null, last = null;
			APP.resetExposure();
			function tick( now ) {
				if ( t0 === null ) t0 = now;
				const el = now - t0;
				const idx = Math.floor( el / 1000 * 30 ) % fr.length;
				APP.setTrackFrame( idx );
				APP.render( last === null ? 1 / 30 : ( now - last ) / 1000 );
				if ( el > WARM && last !== null ) times.push( now - last );
				last = now;
				if ( el > WARM + MEAS ) { resolve( times ); return; }
				requestAnimationFrame( tick );
			}
			requestAnimationFrame( tick );
		} );
	} );
	const sum = r.reduce( ( a, b ) => a + b, 0 );
	const sorted = [ ...r ].sort( ( a, b ) => a - b );
	const p99 = sorted[ Math.floor( sorted.length * 0.99 ) ];
	const worst = sorted.slice( Math.floor( sorted.length * 0.99 ) );
	const worstAvg = worst.reduce( ( a, b ) => a + b, 0 ) / worst.length;
	const out = {
		avg_fps: +( r.length / ( sum / 1000 ) ).toFixed( 1 ),
		avg_frame_ms: +( sum / r.length ).toFixed( 2 ),
		frames: r.length,
		gpu: info && ( info.description || info.device || info.vendor ) || 'unknown',
		low_1pct_fps: +( 1000 / worstAvg ).toFixed( 1 ),
		p99_frame_ms: +p99.toFixed( 2 ),
		preset: 'high',
		resolution: '2560x1440',
		seconds_measured: +( sum / 1000 ).toFixed( 1 ),
		seed: 4242
	};
	fs.writeFileSync( path.join( dir, 'perf.json' ), JSON.stringify( out, null, 2 ) + '\n' );
	log( 'perf', JSON.stringify( out ) );
}

async function test( page ) {
	const dir = path.join( OUT, 'test' );
	await page.evaluate( () => window.APP.setSize( 2560, 1440 ) );
	if ( process.env.TEST_EVAL ) await page.evaluate( process.env.TEST_EVAL );
	const pick = ( process.env.TEST_SHOTS || 'frame_01.png,frame_10.png,frame_12.png,frame_13.png' ).split( ',' );
	for ( const n of pick ) {
		const s = shots.frames[ n ];
		if ( s.kind === 'track' ) { const idx = trackIndex( s.render_frame ); await renderTrackRange( page, Math.max( 0, idx - 30 ), idx ); }
		else await page.evaluate( async ( p ) => { const APP = window.APP; APP.resetExposure(); APP.setPose( p ); for ( let i = 0; i < 60; i ++ ) APP.render( 1 / 30 ); }, s );
		await savePNG( page, path.join( dir, n ) );
		log( 'test', n );
	}
	// quick timing probe
	const ms = await page.evaluate( async () => {
		const APP = window.APP; const t = performance.now();
		for ( let i = 0; i < 60; i ++ ) { APP.setTrackFrame( 500 + i ); APP.render( 1 / 30 ); }
		await APP.renderer.backend.device.queue.onSubmittedWorkDone();
		return ( performance.now() - t ) / 60;
	} );
	log( 'approx ms/frame (2560x1440, offline loop):', ms.toFixed( 2 ) );
}

( async () => {
	await new Promise( ( r ) => server.listen( 0, '127.0.0.1', r ) );
	const port = server.address().port;
	log( 'server on', port, 'mode', mode );
	const t0 = Date.now();
	let L = null;
	for ( let attempt = 1; attempt <= 3 && ! L; attempt ++ ) {
		try { L = await launch( port ); } catch ( e ) { log( `launch attempt ${attempt} failed: ${String( e && e.message || e ).slice( 0, 300 )}` ); }
	}
	if ( ! L ) throw new Error( 'could not start the renderer' );
	const { browser, page, info } = L;
	try {
		if ( mode === 'test' ) await test( page );
		else if ( mode === 'eval' ) console.log( JSON.stringify( await page.evaluate( process.env.EVAL_JS ), null, 1 ) );
		else {
			if ( mode === 'all' ) { fs.rmSync( PACKET, { recursive: true, force: true } ); }
			fs.mkdirSync( PACKET, { recursive: true } );
			if ( mode === 'all' || mode === 'stills' ) await stills( page, PACKET );
			if ( mode === 'all' || mode === 'sheets' ) await sheets( page, PACKET );
			if ( mode === 'all' || mode === 'video' ) await video( page, PACKET );
			if ( mode === 'all' || mode === 'perf' ) await perf( page, PACKET, info );
			fs.copyFileSync( path.join( ROOT, 'review', 'store_page.md' ), path.join( PACKET, 'store_page.md' ) );
		}
	} finally {
		await browser.close();
		server.close();
	}
	log( `done in ${( ( Date.now() - t0 ) / 1000 ).toFixed( 0 )} s` );
} )().catch( ( e ) => { console.error( e ); process.exit( 1 ); } );
