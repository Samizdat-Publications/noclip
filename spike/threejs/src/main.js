// Level 0 look-dev spike, three.js WebGPU renderer.
// Builds the hero slice from level0_hero.json + scene_4242.json, drives the camera from track_4242.json.
// Exposes window.APP for the capture harness (capture.mjs). No UI, no overlays.

import * as THREE from 'three/webgpu';
import {
	Fn, uniform, uniformArray, texture, positionWorld, normalWorld, vec2, vec3, vec4, float, int,
	mix, smoothstep, clamp, max, mx_noise_float, uv, normalMap, attribute, pass, mrt, output,
	normalView, diffuseColor, velocity, packNormalToRGB, unpackRGBToNormal, sample, fog,
	densityFogFactor, screenUV, dot, exp, select, abs, hash, vertexColor, pow, length
} from 'three/tsl';
import { ssgi } from 'three/addons/tsl/display/SSGINode.js';
import { traa } from 'three/addons/tsl/display/TRAANode.js';
import { bloom } from 'three/addons/tsl/display/BloomNode.js';
import { RectAreaLightTexturesLib } from 'three/addons/lights/RectAreaLightTexturesLib.js';
import { DecalGeometry } from 'three/addons/geometries/DecalGeometry.js';

const PARAMS = new URLSearchParams( location.search );
const POOL = parseInt( PARAMS.get( 'pool' ) || '28' );

const H_CEIL = 2.6, H_PLEN = 3.3, WT = 0.2, DOOR_H = 2.1, TILE = 0.6;
const MAP = 30;
const L_NITS = 15.0;         // rect light luminance scale (scene units, exposure 1 -> AgX)
const VIS_N = 512;           // per-light 2D visibility map resolution
const GI_N = 128;            // GI irradiance map resolution

const APP = window.APP = { ready: null, status: 'loading' };

async function loadJSON( u ) { const r = await fetch( u ); return r.json(); }

APP.ready = main().catch( ( e ) => { APP.status = 'error: ' + ( e && e.stack || e ); console.error( e ); throw e; } );

async function main() {

	const [ level, scn, track ] = await Promise.all( [
		loadJSON( '/level/level0_hero.json' ),
		loadJSON( '/data/scene_4242.json' ),
		loadJSON( '/data/track_4242.json' )
	] );
	APP.track = track;

	// ------------------------------------------------------------------ renderer
	const adapter = await navigator.gpu.requestAdapter( { powerPreference: 'high-performance' } );
	APP.adapterInfo = adapter ? { vendor: adapter.info.vendor, architecture: adapter.info.architecture, description: adapter.info.description, device: adapter.info.device } : null;

	THREE.RectAreaLightNode.setLTC( RectAreaLightTexturesLib.init() );

	const renderer = new THREE.WebGPURenderer( { antialias: false, powerPreference: 'high-performance' } );
	renderer.setPixelRatio( 1 );
	renderer.setSize( 2560, 1440, false );
	renderer.toneMapping = THREE.AgXToneMapping;
	renderer.toneMappingExposure = 1.0;
	renderer.shadowMap.enabled = false;
	document.body.appendChild( renderer.domElement );
	renderer.domElement.style.width = '100vw';
	renderer.domElement.style.height = '100vh';
	await renderer.init();
	APP.renderer = renderer;

	const scene = new THREE.Scene();
	scene.background = new THREE.Color( 0x000000 );
	const camera = new THREE.PerspectiveCamera( 78, 16 / 9, 0.05, 80 );
	camera.rotation.order = 'YXZ';
	scene.add( camera );

	// ------------------------------------------------------------------ textures
	const texLoader = new THREE.TextureLoader();
	const maxAniso = renderer.getMaxAnisotropy();
	function tex( name, srgb = false, flipY = true ) {
		return new Promise( ( res ) => {
			texLoader.load( '/tex/' + name + '.png', ( t ) => {
				t.wrapS = t.wrapT = THREE.RepeatWrapping;
				t.colorSpace = srgb ? THREE.SRGBColorSpace : THREE.NoColorSpace;
				t.anisotropy = maxAniso;
				t.flipY = flipY;
				t.needsUpdate = true;
				res( t );
			} );
		} );
	}
	const T = {};
	const texList = [
		[ 'wallpaper_albedo', 1 ], [ 'wallpaper_normal', 0 ], [ 'wallpaper_roughness', 0 ], [ 'wallpaper_ao', 0 ],
		[ 'carpet_albedo', 1 ], [ 'carpet_normal', 0 ], [ 'carpet_roughness', 0 ], [ 'carpet_ao', 0 ],
		[ 'ceiling_tile_albedo', 1 ], [ 'ceiling_tile_stained_albedo', 1 ], [ 'ceiling_tile_normal', 0 ], [ 'ceiling_tile_roughness', 0 ], [ 'ceiling_tile_ao', 0 ],
		[ 'troffer_lens_albedo', 1 ], [ 'troffer_lens_emission', 1 ], [ 'troffer_lens_normal', 0 ],
		[ 'baseboard_albedo', 1 ], [ 'baseboard_normal', 0 ], [ 'baseboard_roughness', 0 ],
	];
	await Promise.all( texList.map( async ( [ n, s ] ) => { T[ n ] = await tex( n, !! s ); } ) );
	const decalNames = [ 'decal_ceiling_stain', 'decal_floor_wetpatch', 'decal_mold', 'decal_wall_grime_low', 'decal_wall_waterdamage' ];
	await Promise.all( decalNames.map( async ( n ) => { T[ n ] = await tex( n, true, false ); T[ n ].wrapS = T[ n ].wrapT = THREE.ClampToEdgeWrapping; } ) );

	// ------------------------------------------------------------------ geometry helpers
	class Builder {
		constructor() { this.p = []; this.n = []; this.u = []; this.t = []; this.c = []; this.f = []; this.i = []; this.vc = 0; }
		// corners CCW seen from the normal side; uvs per corner
		quad( P, U, N, col = [ 1, 1, 1 ], fid = 0 ) {
			const e1 = sub( P[ 1 ], P[ 0 ] ), e2 = sub( P[ 3 ], P[ 0 ] );
			const du1 = U[ 1 ][ 0 ] - U[ 0 ][ 0 ], dv1 = U[ 1 ][ 1 ] - U[ 0 ][ 1 ];
			const du2 = U[ 3 ][ 0 ] - U[ 0 ][ 0 ], dv2 = U[ 3 ][ 1 ] - U[ 0 ][ 1 ];
			let r = du1 * dv2 - du2 * dv1; r = Math.abs( r ) < 1e-12 ? 1 : 1 / r;
			let Tg = norm( [ ( e1[ 0 ] * dv2 - e2[ 0 ] * dv1 ) * r, ( e1[ 1 ] * dv2 - e2[ 1 ] * dv1 ) * r, ( e1[ 2 ] * dv2 - e2[ 2 ] * dv1 ) * r ] );
			const Bt = [ ( e2[ 0 ] * du1 - e1[ 0 ] * du2 ) * r, ( e2[ 1 ] * du1 - e1[ 1 ] * du2 ) * r, ( e2[ 2 ] * du1 - e1[ 2 ] * du2 ) * r ];
			const w = dot3( cross( N, Tg ), Bt ) < 0 ? - 1 : 1;
			for ( let k = 0; k < 4; k ++ ) {
				this.p.push( ...P[ k ] ); this.n.push( ...N ); this.u.push( ...U[ k ] ); this.t.push( ...Tg, w ); this.c.push( ...col ); this.f.push( fid );
			}
			const b = this.vc;
			this.i.push( b, b + 1, b + 2, b, b + 2, b + 3 );
			this.vc += 4;
		}
		geometry() {
			const g = new THREE.BufferGeometry();
			g.setAttribute( 'position', new THREE.Float32BufferAttribute( this.p, 3 ) );
			g.setAttribute( 'normal', new THREE.Float32BufferAttribute( this.n, 3 ) );
			g.setAttribute( 'uv', new THREE.Float32BufferAttribute( this.u, 2 ) );
			g.setAttribute( 'tangent', new THREE.Float32BufferAttribute( this.t, 4 ) );
			g.setAttribute( 'color', new THREE.Float32BufferAttribute( this.c, 3 ) );
			g.setAttribute( 'fid', new THREE.Float32BufferAttribute( this.f, 1 ) );
			g.setIndex( this.vc > 65535 ? new THREE.Uint32BufferAttribute( this.i, 1 ) : new THREE.Uint16BufferAttribute( this.i, 1 ) );
			g.computeBoundingSphere();
			return g;
		}
	}
	function sub( a, b ) { return [ a[ 0 ] - b[ 0 ], a[ 1 ] - b[ 1 ], a[ 2 ] - b[ 2 ] ]; }
	function cross( a, b ) { return [ a[ 1 ] * b[ 2 ] - a[ 2 ] * b[ 1 ], a[ 2 ] * b[ 0 ] - a[ 0 ] * b[ 2 ], a[ 0 ] * b[ 1 ] - a[ 1 ] * b[ 0 ] ]; }
	function dot3( a, b ) { return a[ 0 ] * b[ 0 ] + a[ 1 ] * b[ 1 ] + a[ 2 ] * b[ 2 ]; }
	function norm( a ) { const l = Math.hypot( a[ 0 ], a[ 1 ], a[ 2 ] ) || 1; return [ a[ 0 ] / l, a[ 1 ] / l, a[ 2 ] / l ]; }

	// vertical face: horizontal extent along xz from point a to b (CCW from normal side means a = left, b = right as seen by a viewer facing it)
	// uvMode: 'wall' (0.6 m world tiling, v from ceiling), 'base' (1 m along, 0.1 m tall), 'plain' (1 m)
	function vface( B, ax, az, bx, bz, y0, y1, N, uvMode ) {
		const right = cross( [ 0, 1, 0 ], N ); // viewer's right
		const P = [ [ ax, y0, az ], [ bx, y0, bz ], [ bx, y1, bz ], [ ax, y1, az ] ];
		// make sure P[0] is the left corner
		if ( dot3( P[ 0 ], right ) > dot3( P[ 1 ], right ) ) { P[ 0 ] = [ bx, y0, bz ]; P[ 1 ] = [ ax, y0, az ]; P[ 2 ] = [ ax, y1, az ]; P[ 3 ] = [ bx, y1, bz ]; }
		const U = P.map( ( p ) => {
			const s = dot3( p, right );
			if ( uvMode === 'wall' ) return [ s / TILE, ( p[ 1 ] - H_CEIL ) / TILE ];
			if ( uvMode === 'base' ) return [ s / 1.0, p[ 1 ] / 0.1 ];
			return [ s, p[ 1 ] ];
		} );
		B.quad( P, U, N );
	}
	// horizontal face at height y over rect x0..x1, z0..z1, facing up (+1) or down (-1)
	function hface( B, x0, z0, x1, z1, y, up, uvScale = 1, col, fid = 0, uvOverride = null ) {
		let P, U;
		if ( up > 0 ) {
			// seen from above: screen right = +X, screen up = -Z
			P = [ [ x0, y, z1 ], [ x1, y, z1 ], [ x1, y, z0 ], [ x0, y, z0 ] ];
			U = P.map( ( p ) => [ p[ 0 ] / uvScale, - p[ 2 ] / uvScale ] );
		} else {
			P = [ [ x0, y, z0 ], [ x1, y, z0 ], [ x1, y, z1 ], [ x0, y, z1 ] ];
			U = P.map( ( p ) => [ p[ 0 ] / uvScale, p[ 2 ] / uvScale ] );
		}
		if ( uvOverride ) U = uvOverride;
		B.quad( P, U, up > 0 ? [ 0, 1, 0 ] : [ 0, - 1, 0 ], col, fid );
	}
	// axis aligned box (all faces optional)
	function box( B, x0, y0, z0, x1, y1, z1, uvMode = 'plain', skip = {} ) {
		if ( ! skip.pz ) vface( B, x0, z1, x1, z1, y0, y1, [ 0, 0, 1 ], uvMode );
		if ( ! skip.nz ) vface( B, x0, z0, x1, z0, y0, y1, [ 0, 0, - 1 ], uvMode );
		if ( ! skip.px ) vface( B, x1, z0, x1, z1, y0, y1, [ 1, 0, 0 ], uvMode );
		if ( ! skip.nx ) vface( B, x0, z0, x0, z1, y0, y1, [ - 1, 0, 0 ], uvMode );
		if ( ! skip.py ) hface( B, x0, z0, x1, z1, y1, 1 );
		if ( ! skip.ny ) hface( B, x0, z0, x1, z1, y0, - 1 );
	}

	// ------------------------------------------------------------------ level geometry
	const walls = level.walls.map( ( w ) => ( { x0: Math.min( w[ 0 ], w[ 2 ] ), z0: Math.min( w[ 1 ], w[ 3 ] ), x1: Math.max( w[ 0 ], w[ 2 ] ), z1: Math.max( w[ 1 ], w[ 3 ] ), h: w[ 1 ] === w[ 3 ] } ) );
	const doors = level.doors.map( ( d ) => ( { x0: Math.min( d[ 0 ], d[ 2 ] ), z0: Math.min( d[ 1 ], d[ 3 ] ), x1: Math.max( d[ 0 ], d[ 2 ] ), z1: Math.max( d[ 1 ], d[ 3 ] ), h: d[ 1 ] === d[ 3 ] } ) );
	const eps = 1e-4;
	function onPerp( w, x, z ) {
		for ( const o of walls ) {
			if ( o === w || o.h === w.h ) continue;
			if ( o.h ) { if ( Math.abs( o.z0 - z ) < eps && x >= o.x0 - eps && x <= o.x1 + eps ) return true; }
			else { if ( Math.abs( o.x0 - x ) < eps && z >= o.z0 - eps && z <= o.z1 + eps ) return true; }
		}
		return false;
	}
	function isDoorEnd( x, z ) {
		for ( const d of doors ) if ( ( Math.abs( d.x0 - x ) < eps && Math.abs( d.z0 - z ) < eps ) || ( Math.abs( d.x1 - x ) < eps && Math.abs( d.z1 - z ) < eps ) ) return true;
		return false;
	}

	const Bwall = new Builder(), Bbase = new Builder(), Btrim = new Builder();
	const HW = WT / 2, BP = 0.012, BH = 0.1;
	for ( const w of walls ) {
		const ext0 = onPerp( w, w.x0, w.z0 ), ext1 = onPerp( w, w.x1, w.z1 );
		if ( w.h ) {
			const xa = w.x0 - ( ext0 ? HW : 0 ), xb = w.x1 + ( ext1 ? HW : 0 ), z = w.z0;
			vface( Bwall, xa, z + HW, xb, z + HW, 0, H_PLEN, [ 0, 0, 1 ], 'wall' );
			vface( Bwall, xa, z - HW, xb, z - HW, 0, H_PLEN, [ 0, 0, - 1 ], 'wall' );
			box( Bbase, xa, 0, z + HW, xb, BH, z + HW + BP, 'base', { nz: 1, ny: 1 } );
			box( Bbase, xa, 0, z - HW - BP, xb, BH, z - HW, 'base', { pz: 1, ny: 1 } );
			if ( ! ext0 ) {
				const door = isDoorEnd( w.x0, z );
				vface( door ? Btrim : Bwall, xa, z - HW, xa, z + HW, 0, H_PLEN, [ - 1, 0, 0 ], door ? 'plain' : 'wall' );
				if ( ! door ) box( Bbase, xa - BP, 0, z - HW - BP, xa, BH, z + HW + BP, 'base', { px: 1, ny: 1 } );
			}
			if ( ! ext1 ) {
				const door = isDoorEnd( w.x1, z );
				vface( door ? Btrim : Bwall, xb, z - HW, xb, z + HW, 0, H_PLEN, [ 1, 0, 0 ], door ? 'plain' : 'wall' );
				if ( ! door ) box( Bbase, xb, 0, z - HW - BP, xb + BP, BH, z + HW + BP, 'base', { nx: 1, ny: 1 } );
			}
		} else {
			const za = w.z0 - ( ext0 ? HW : 0 ), zb = w.z1 + ( ext1 ? HW : 0 ), x = w.x0;
			vface( Bwall, x + HW, za, x + HW, zb, 0, H_PLEN, [ 1, 0, 0 ], 'wall' );
			vface( Bwall, x - HW, za, x - HW, zb, 0, H_PLEN, [ - 1, 0, 0 ], 'wall' );
			box( Bbase, x + HW, 0, za, x + HW + BP, BH, zb, 'base', { nx: 1, ny: 1 } );
			box( Bbase, x - HW - BP, 0, za, x - HW, BH, zb, 'base', { px: 1, ny: 1 } );
			if ( ! ext0 ) {
				const door = isDoorEnd( x, w.z0 );
				vface( door ? Btrim : Bwall, x - HW, za, x + HW, za, 0, H_PLEN, [ 0, 0, - 1 ], door ? 'plain' : 'wall' );
				if ( ! door ) box( Bbase, x - HW - BP, 0, za - BP, x + HW + BP, BH, za, 'base', { pz: 1, ny: 1 } );
			}
			if ( ! ext1 ) {
				const door = isDoorEnd( x, w.z1 );
				vface( door ? Btrim : Bwall, x - HW, zb, x + HW, zb, 0, H_PLEN, [ 0, 0, 1 ], door ? 'plain' : 'wall' );
				if ( ! door ) box( Bbase, x - HW - BP, 0, zb, x + HW + BP, BH, zb + BP, 'base', { nz: 1, ny: 1 } );
			}
		}
	}
	// door headers + casings
	const CW = 0.07, CP = 0.018;
	for ( const d of doors ) {
		if ( d.h ) {
			const z = d.z0;
			vface( Bwall, d.x0, z + HW, d.x1, z + HW, DOOR_H, H_PLEN, [ 0, 0, 1 ], 'wall' );
			vface( Bwall, d.x0, z - HW, d.x1, z - HW, DOOR_H, H_PLEN, [ 0, 0, - 1 ], 'wall' );
			hface( Btrim, d.x0, z - HW, d.x1, z + HW, DOOR_H, - 1 );
			for ( const s of [ 1, - 1 ] ) {
				const za = s > 0 ? z + HW : z - HW - CP, zb = s > 0 ? z + HW + CP : z - HW;
				box( Btrim, d.x0 - CW, 0, za, d.x0, DOOR_H + CW, zb );
				box( Btrim, d.x1, 0, za, d.x1 + CW, DOOR_H + CW, zb );
				box( Btrim, d.x0 - CW, DOOR_H, za, d.x1 + CW, DOOR_H + CW, zb );
			}
		} else {
			const x = d.x0;
			vface( Bwall, x + HW, d.z0, x + HW, d.z1, DOOR_H, H_PLEN, [ 1, 0, 0 ], 'wall' );
			vface( Bwall, x - HW, d.z0, x - HW, d.z1, DOOR_H, H_PLEN, [ - 1, 0, 0 ], 'wall' );
			hface( Btrim, x - HW, d.z0, x + HW, d.z1, DOOR_H, - 1 );
			for ( const s of [ 1, - 1 ] ) {
				const xa = s > 0 ? x + HW : x - HW - CP, xb = s > 0 ? x + HW + CP : x - HW;
				box( Btrim, xa, 0, d.z0 - CW, xb, DOOR_H + CW, d.z0 );
				box( Btrim, xa, 0, d.z1, xb, DOOR_H + CW, d.z1 + CW );
				box( Btrim, xa, DOOR_H, d.z0 - CW, xb, DOOR_H + CW, d.z1 + CW );
			}
		}
	}
	// pillars
	for ( const [ cx, cz, s ] of level.pillars ) {
		const h = s / 2;
		box( Bwall, cx - h, 0, cz - h, cx + h, H_PLEN, cz + h, 'wall', { py: 1, ny: 1 } );
		box( Bbase, cx - h - BP, 0, cz - h - BP, cx + h + BP, BH, cz + h + BP, 'base', { ny: 1 } );
	}

	// floor
	const Bfloor = new Builder();
	hface( Bfloor, 0, 0, MAP, MAP, 0, 1, 1.0 );
	// plenum
	const Bplen = new Builder();
	hface( Bplen, 0, 0, MAP, MAP, H_PLEN, - 1, 1.0 );

	// ceiling tiles
	const NT = Math.round( MAP / TILE );
	const fixtures = scn.fixtures;
	const fixCell = new Set();
	for ( const f of fixtures ) {
		const i = Math.round( ( f.x - 0.3 ) / TILE ), j0 = Math.round( ( f.z - 0.6 ) / TILE );
		fixCell.add( i + ',' + j0 ); fixCell.add( i + ',' + ( j0 + 1 ) );
	}
	const Bceil = new Builder(), BceilS = new Builder();
	for ( const [ i, j, rnd, stained, sag, drop ] of scn.special_tiles ) {
		const x0 = i * TILE, z0 = j * TILE, x1 = x0 + TILE, z1 = z0 + TILE;
		const flip = rnd > 0.5;
		const UVs = flip ? [ [ 1, 1 ], [ 0, 1 ], [ 0, 0 ], [ 1, 0 ] ] : [ [ 0, 0 ], [ 1, 0 ], [ 1, 1 ], [ 0, 1 ] ];
		const b = 0.955 + 0.09 * rnd;
		const B = stained ? BceilS : Bceil;
		const y = H_CEIL;
		if ( drop > 0 ) {
			const P = [ [ x0, y, z0 ], [ x1, y, z0 ], [ x1, y - drop, z1 ], [ x0, y - drop, z1 ] ];
			const N = norm( cross( sub( P[ 3 ], P[ 0 ] ), sub( P[ 1 ], P[ 0 ] ) ) );
			B.quad( P, UVs, N[ 1 ] < 0 ? N : [ - N[ 0 ], - N[ 1 ], - N[ 2 ] ], [ b, b, b ] );
		} else {
			hface( B, x0, z0, x1, z1, y, - 1, 1, [ b, b, b ], 0, UVs );
		}
	}
	// T-bar grid (cell edges, skipped inside fixtures)
	const Btbar = new Builder();
	const TW = 0.012, TD = 0.014;
	for ( let j = 0; j <= NT; j ++ ) for ( let i = 0; i < NT; i ++ ) {
		// edge along x at z = j*TILE between cells (i,j-1) and (i,j)
		const a = fixCell.has( i + ',' + ( j - 1 ) ), b = fixCell.has( i + ',' + j );
		if ( a && b ) {
			// interior of a fixture only if both belong to the same fixture: fixtures are 2 cells in z
			const f = fixtures.find( ( f ) => Math.abs( f.x - ( i * TILE + 0.3 ) ) < 0.01 && Math.abs( f.z - j * TILE ) < 0.01 );
			if ( f ) continue;
		}
		const z = j * TILE, x0 = i * TILE, x1 = x0 + TILE;
		box( Btbar, x0 - TW, H_CEIL - TD, z - TW, x1 + TW, H_CEIL, z + TW, 'plain', { py: 1 } );
	}
	for ( let i = 0; i <= NT; i ++ ) for ( let j = 0; j < NT; j ++ ) {
		const x = i * TILE, z0 = j * TILE, z1 = z0 + TILE;
		box( Btbar, x - TW, H_CEIL - TD, z0, x + TW, H_CEIL, z1, 'plain', { py: 1 } );
	}

	// troffers: lens + white housing reveal
	const Blens = new Builder(), Bhouse = new Builder();
	const LENS_Y = H_CEIL + 0.03;
	fixtures.forEach( ( f, k ) => {
		const x0 = f.x - 0.3, x1 = f.x + 0.3, z0 = f.z - 0.6, z1 = f.z + 0.6;
		const col = [ f.tint[ 0 ] * f.energy, f.tint[ 1 ] * f.energy, f.tint[ 2 ] * f.energy ];
		// lens: u across (0.6), v along (1.2); emission map is 512x1024 (portrait) so v runs along z
		hface( Blens, x0 + 0.01, z0 + 0.01, x1 - 0.01, z1 - 0.01, LENS_Y, - 1, 1, col, k, [ [ 0, 0 ], [ 1, 0 ], [ 1, 1 ], [ 0, 1 ] ] );
		vface( Bhouse, x0, z0, x1, z0, H_CEIL - 0.002, LENS_Y, [ 0, 0, 1 ], 'plain' );
		vface( Bhouse, x0, z1, x1, z1, H_CEIL - 0.002, LENS_Y, [ 0, 0, - 1 ], 'plain' );
		vface( Bhouse, x0, z0, x0, z1, H_CEIL - 0.002, LENS_Y, [ 1, 0, 0 ], 'plain' );
		vface( Bhouse, x1, z0, x1, z1, H_CEIL - 0.002, LENS_Y, [ - 1, 0, 0 ], 'plain' );
		// thin white flange frame around the opening, slightly below the grid
		const FL = 0.025, fy = H_CEIL - TD - 0.002;
		hface( Bhouse, x0 - FL, z0 - FL, x1 + FL, z0, fy, - 1 );
		hface( Bhouse, x0 - FL, z1, x1 + FL, z1 + FL, fy, - 1 );
		hface( Bhouse, x0 - FL, z0, x0, z1, fy, - 1 );
		hface( Bhouse, x1, z0, x1 + FL, z1, fy, - 1 );
	} );

	// ------------------------------------------------------------------ light visibility + GI bake (2D, walls are full height)
	const segs = [];
	for ( const w of walls ) segs.push( [ w.x0, w.z0, w.x1, w.z1 ] );
	for ( const [ cx, cz, s ] of level.pillars ) { const h = s / 2; segs.push( [ cx - h, cz - h, cx + h, cz + h ], [ cx - h, cz + h, cx + h, cz - h ] ); }

	const emitIdx = []; // fixture index for each vis layer
	const layerOf = new Int32Array( fixtures.length ).fill( - 1 );
	fixtures.forEach( ( f, k ) => { if ( f.state !== 1 ) { layerOf[ k ] = emitIdx.length; emitIdx.push( k ); } } );
	const NL = emitIdx.length;
	const visData = new Uint8Array( VIS_N * VIS_N * NL );
	{
		const S = VIS_N / MAP;
		const cv = new OffscreenCanvas( VIS_N, VIS_N ); const ctx = cv.getContext( '2d', { willReadFrequently: true } );
		const ac = new OffscreenCanvas( VIS_N, VIS_N ); const actx = ac.getContext( '2d', { willReadFrequently: true } );
		const samples = [];
		for ( const sx of [ - 0.2, 0.2 ] ) for ( const sz of [ - 0.45, - 0.15, 0.15, 0.45 ] ) samples.push( [ sx, sz ] );
		for ( let l = 0; l < NL; l ++ ) {
			const f = fixtures[ emitIdx[ l ] ];
			actx.globalCompositeOperation = 'source-over'; actx.globalAlpha = 1; actx.fillStyle = '#000'; actx.fillRect( 0, 0, VIS_N, VIS_N );
			for ( const [ sx, sz ] of samples ) {
				const lx = f.x + sx, lz = f.z + sz;
				ctx.globalCompositeOperation = 'source-over'; ctx.filter = 'none';
				ctx.fillStyle = '#fff'; ctx.fillRect( 0, 0, VIS_N, VIS_N );
				ctx.fillStyle = '#000'; ctx.beginPath();
				for ( const [ ax, az, bx, bz ] of segs ) {
					const da = Math.hypot( ax - lx, az - lz ) || 1e-3, db = Math.hypot( bx - lx, bz - lz ) || 1e-3;
					const K = 80;
					ctx.moveTo( ax * S, az * S ); ctx.lineTo( bx * S, bz * S );
					ctx.lineTo( ( bx + ( bx - lx ) / db * K ) * S, ( bz + ( bz - lz ) / db * K ) * S );
					ctx.lineTo( ( ax + ( ax - lx ) / da * K ) * S, ( az + ( az - lz ) / da * K ) * S );
					ctx.closePath();
				}
				ctx.fill( 'nonzero' );
				actx.globalCompositeOperation = 'lighter'; actx.globalAlpha = 1 / samples.length;
				actx.drawImage( cv, 0, 0 );
			}
			// range window so the pool can swap lights without pops
			actx.globalAlpha = 1; actx.globalCompositeOperation = 'multiply';
			const g = actx.createRadialGradient( f.x * S, f.z * S, 5.0 * S, f.x * S, f.z * S, 11.0 * S );
			g.addColorStop( 0, '#fff' ); g.addColorStop( 1, '#000' );
			actx.fillStyle = g; actx.fillRect( 0, 0, VIS_N, VIS_N );
			ctx.globalCompositeOperation = 'source-over'; ctx.clearRect( 0, 0, VIS_N, VIS_N );
			ctx.filter = 'blur(1.2px)'; ctx.drawImage( ac, 0, 0 ); ctx.filter = 'none';
			const img = ctx.getImageData( 0, 0, VIS_N, VIS_N ).data;
			const off = l * VIS_N * VIS_N;
			for ( let p = 0; p < VIS_N * VIS_N; p ++ ) visData[ off + p ] = img[ p * 4 ];
		}
	}
	APP.visCPU = ( l, x, z ) => {
		const i = Math.min( VIS_N - 1, Math.max( 0, Math.floor( x / MAP * VIS_N ) ) ), j = Math.min( VIS_N - 1, Math.max( 0, Math.floor( z / MAP * VIS_N ) ) );
		return visData[ l * VIS_N * VIS_N + j * VIS_N + i ] / 255;
	};
	const visTex = new THREE.DataArrayTexture( visData, VIS_N, VIS_N, NL );
	visTex.format = THREE.RedFormat; visTex.type = THREE.UnsignedByteType;
	visTex.minFilter = visTex.magFilter = THREE.LinearFilter; visTex.generateMipmaps = false;
	visTex.wrapS = visTex.wrapT = THREE.ClampToEdgeWrapping;
	visTex.needsUpdate = true;

	// GI: layer 0 = all steady lights, layers 1..A = animated lights (weighted per frame)
	const animIdx = []; fixtures.forEach( ( f, k ) => { if ( f.state >= 2 ) animIdx.push( k ); } );
	const GL = 1 + animIdx.length;
	const giF = new Float32Array( GI_N * GI_N * GL );
	{
		const R = VIS_N / GI_N;
		const addLight = ( layer, k ) => {
			const f = fixtures[ k ], l = layerOf[ k ];
			const e = f.energy;
			for ( let j = 0; j < GI_N; j ++ ) for ( let i = 0; i < GI_N; i ++ ) {
				const x = ( i + 0.5 ) / GI_N * MAP, z = ( j + 0.5 ) / GI_N * MAP;
				const d2 = ( x - f.x ) ** 2 + ( z - f.z ) ** 2;
				if ( d2 > 144 ) continue;
				let v = 0;
				for ( let b = 0; b < R; b ++ ) for ( let a = 0; a < R; a ++ ) v += visData[ l * VIS_N * VIS_N + ( j * R + b ) * VIS_N + i * R + a ];
				v /= R * R * 255;
				giF[ layer * GI_N * GI_N + j * GI_N + i ] += v * e / ( 1 + d2 / 4.0 );
			}
		};
		fixtures.forEach( ( f, k ) => { if ( f.state === 0 ) addLight( 0, k ); } );
		animIdx.forEach( ( k, a ) => addLight( 1 + a, k ) );
		// blur each layer: 2 tight box passes (~0.47 m), then mix in a wide spill (~2 m) so light bleeds through doors into dark rooms
		const tmp = new Float32Array( GI_N * GI_N );
		const blur = ( o, rad, passes ) => {
			for ( let pass = 0; pass < passes; pass ++ ) {
				for ( let j = 0; j < GI_N; j ++ ) for ( let i = 0; i < GI_N; i ++ ) { let s = 0, c = 0; for ( let d = - rad; d <= rad; d ++ ) { const ii = i + d; if ( ii >= 0 && ii < GI_N ) { s += giF[ o + j * GI_N + ii ]; c ++; } } tmp[ j * GI_N + i ] = s / c; }
				for ( let j = 0; j < GI_N; j ++ ) for ( let i = 0; i < GI_N; i ++ ) { let s = 0, c = 0; for ( let d = - rad; d <= rad; d ++ ) { const jj = j + d; if ( jj >= 0 && jj < GI_N ) { s += tmp[ jj * GI_N + i ]; c ++; } } giF[ o + j * GI_N + i ] = s / c; }
			}
		};
		for ( let L = 0; L < GL; L ++ ) {
			const o = L * GI_N * GI_N;
			const orig = giF.slice( o, o + GI_N * GI_N );
			blur( o, 8, 3 );
			const wide = giF.slice( o, o + GI_N * GI_N );
			giF.set( orig, o );
			blur( o, 2, 2 );
			for ( let p = 0; p < GI_N * GI_N; p ++ ) giF[ o + p ] = giF[ o + p ] * 0.85 + wide[ p ] * 0.35 + ( L === 0 ? 0.035 : 0 );
		}
	}
	APP.giCPU = ( x, z, w ) => {
		const i = Math.min( GI_N - 1, Math.max( 0, Math.floor( x / MAP * GI_N ) ) ), j = Math.min( GI_N - 1, Math.max( 0, Math.floor( z / MAP * GI_N ) ) );
		let s = 0; for ( let L = 0; L < GL; L ++ ) s += giF[ L * GI_N * GI_N + j * GI_N + i ] * w[ L ];
		return s;
	};
	const giHalf = new Uint16Array( giF.length ); for ( let p = 0; p < giF.length; p ++ ) giHalf[ p ] = THREE.DataUtils.toHalfFloat( giF[ p ] );
	const giTex = new THREE.DataArrayTexture( giHalf, GI_N, GI_N, GL );
	giTex.format = THREE.RedFormat; giTex.type = THREE.HalfFloatType;
	giTex.minFilter = giTex.magFilter = THREE.LinearFilter; giTex.generateMipmaps = false;
	giTex.wrapS = giTex.wrapT = THREE.ClampToEdgeWrapping;
	giTex.needsUpdate = true;

	// ------------------------------------------------------------------ shared TSL nodes
	const seedOff = vec2( scn.seed_offset[ 0 ], scn.seed_offset[ 1 ] );
	const giW = uniformArray( new Array( GL ).fill( 0 ), 'float' );
	const giK = uniform( 0.17 );
	const giTint = uniform( new THREE.Color( 1.0, 0.84, 0.52 ) );
	const giIrr = Fn( () => {
		const p = positionWorld.xz.add( normalWorld.xz.mul( 0.15 ) ).div( MAP );
		let s = texture( giTex, p ).depth( int( 0 ) ).r.mul( giW.element( int( 0 ) ) );
		for ( let k = 1; k < GL; k ++ ) s = s.add( texture( giTex, p ).depth( int( k ) ).r.mul( giW.element( int( k ) ) ) );
		return s;
	} );
	// height shaping: a bit less bounce right at the ceiling plane, more near the lit floor
	const giHeight = Fn( () => mix( float( 1.0 ), float( 0.62 ), smoothstep( 1.4, 2.6, positionWorld.y ) ) );
	const indirect = ( albedo, ao ) => albedo.mul( giTint ).mul( giIrr() ).mul( giK ).mul( giHeight() ).mul( ao );

	// haze: exponential fog whose colour follows the local bounce light, so dark rooms stay dark
	const hazeK = uniform( 0.07 );
	scene.fogNode = fog( giTint.mul( giIrr() ).mul( hazeK ), densityFogFactor( 0.032 ) );

	// ------------------------------------------------------------------ materials
	const wallMat = new THREE.MeshStandardNodeMaterial();
	{
		const P = positionWorld, y = P.y;
		const along = select( abs( normalWorld.x ).greaterThan( 0.5 ), P.z, P.x ).add( seedOff.x );
		const base = texture( T.wallpaper_albedo, uv() ).rgb;
		const nT = mx_noise_float( vec3( P.x.add( seedOff.x ).mul( 0.11 ), y.mul( 0.22 ), P.z.add( seedOff.y ).mul( 0.11 ) ) ).mul( 0.5 ).add( 0.5 );
		const nT2 = mx_noise_float( vec3( P.x.mul( 0.9 ), y.mul( 0.6 ), P.z.mul( 0.9 ) ).add( 7.7 ) ).mul( 0.5 ).add( 0.5 );
		const tint = mix( vec3( 1.03, 1.01, 0.97 ), vec3( 0.88, 0.84, 0.72 ), nT ).mul( mix( 0.96, 1.03, nT2 ) );
		// water wicking band with tide line
		const gW = smoothstep( 0.0, 0.3, mx_noise_float( vec2( along.mul( 0.085 ), seedOff.y.mul( 0.1 ) ) ) );
		const hb = float( 0.12 ).add( mx_noise_float( vec2( along.mul( 0.8 ), 3.1 ) ).mul( 0.5 ).add( 0.5 ).mul( 0.26 ) ).add( mx_noise_float( vec2( along.mul( 9.0 ), y.mul( 2.0 ).add( 1.3 ) ) ).mul( 0.035 ) );
		const edgeN = mx_noise_float( vec2( along.mul( 3.0 ), y.mul( 4.0 ) ) ).mul( 0.5 ).add( 0.5 );
		const inBand = float( 1 ).sub( smoothstep( hb.sub( 0.07 ), hb, y ) );
		const tide = smoothstep( hb.sub( 0.10 ), hb.sub( 0.015 ), y ).mul( inBand );
		const stain = inBand.mul( mix( 0.45, 1.0, tide ) ).mul( mix( 0.7, 1.0, edgeN ) ).mul( gW );
		const inBandR = inBand.mul( gW );
		const wick = mix( vec3( 1 ), vec3( 0.68, 0.57, 0.40 ), stain.mul( 0.8 ) );
		// drip staining from the ceiling
		const gD = smoothstep( 0.1, 0.4, mx_noise_float( vec2( along.mul( 0.1 ).add( 40.0 ), seedOff.x.mul( 0.1 ) ) ) );
		const streak = smoothstep( 0.05, 0.55, mx_noise_float( vec2( along.mul( 6.5 ), y.mul( 0.3 ) ) ) );
		const dripLen = float( 0.4 ).add( mx_noise_float( vec2( along.mul( 1.3 ), 9.0 ) ).mul( 0.5 ).add( 0.5 ).mul( 1.5 ) );
		const dripFade = smoothstep( float( H_CEIL ).sub( dripLen ), H_CEIL, y );
		const ceilBand = smoothstep( H_CEIL - 0.12, H_CEIL, y ).mul( 0.5 );
		const drip = mix( vec3( 1 ), vec3( 0.74, 0.63, 0.45 ), streak.mul( dripFade ).add( ceilBand ).clamp( 0, 1 ).mul( gD ) );
		const albedo = base.mul( tint ).mul( wick ).mul( drip );
		const ao = texture( T.wallpaper_ao, uv() ).r;
		wallMat.colorNode = albedo.mul( mix( 1.0, ao, 0.5 ) );
		wallMat.roughnessNode = texture( T.wallpaper_roughness, uv() ).r.mul( mix( 1.0, 0.8, inBandR ) );
		wallMat.metalnessNode = float( 0 );
		wallMat.normalNode = normalMap( texture( T.wallpaper_normal, uv() ), vec2( 0.55, 0.55 ) );
		wallMat.emissiveNode = indirect( albedo, ao );
	}

	const leaks = scn.leaks;
	const floorMat = new THREE.MeshStandardNodeMaterial();
	{
		const P2 = positionWorld.xz;
		const cuv = uv();
		const uv2 = vec2( cuv.x.mul( 0.8 ).sub( cuv.y.mul( 0.6 ) ), cuv.x.mul( 0.6 ).add( cuv.y.mul( 0.8 ) ) ).mul( 0.87 ).add( 0.31 );
		const bl = smoothstep( - 0.25, 0.25, mx_noise_float( P2.add( seedOff ).mul( 0.23 ) ) );
		const a = mix( texture( T.carpet_albedo, cuv ).rgb, texture( T.carpet_albedo, uv2 ).rgb, bl );
		const drift = mx_noise_float( P2.add( seedOff ).mul( 0.07 ).add( 11.0 ) );
		const drift2 = mx_noise_float( P2.add( seedOff ).mul( 0.6 ).add( 3.0 ) );
		let leakT = float( 0 );
		for ( const [ lx, lz ] of leaks ) leakT = leakT.add( exp( length( P2.sub( vec2( lx, lz ) ) ).pow( 2 ).mul( - 0.5 ) ).mul( 0.8 ) );
		const wetN = mx_noise_float( P2.add( seedOff ).mul( 0.15 ).add( vec2( 5.3, 1.7 ) ) ).add( mx_noise_float( P2.mul( 1.1 ).add( 2.0 ) ).mul( 0.15 ) );
		const wet = smoothstep( 0.5, 0.68, wetN.add( leakT ) );
		const ao = texture( T.carpet_ao, cuv ).r;
		const albedo = a.mul( drift.mul( 0.10 ).add( 1.0 ) ).mul( drift2.mul( 0.04 ).add( 1.0 ) ).mul( mix( vec3( 1 ), vec3( 0.56, 0.5, 0.42 ), wet ) );
		floorMat.colorNode = albedo.mul( mix( 1.0, ao, 0.6 ) );
		floorMat.roughnessNode = mix( mix( texture( T.carpet_roughness, cuv ).r, texture( T.carpet_roughness, uv2 ).r, bl ), float( 0.42 ), wet );
		floorMat.metalnessNode = float( 0 );
		floorMat.normalNode = normalMap( texture( T.carpet_normal, cuv ), vec2( mix( 1.4, 0.8, wet ) ) );
		floorMat.emissiveNode = indirect( albedo, ao );
	}

	function ceilMaterial( alb ) {
		const m = new THREE.MeshStandardNodeMaterial();
		const albedo = texture( alb, uv() ).rgb.mul( vertexColor() );
		const ao = texture( T.ceiling_tile_ao, uv() ).r;
		m.colorNode = albedo.mul( mix( 1.0, ao, 0.5 ) );
		m.roughnessNode = texture( T.ceiling_tile_roughness, uv() ).r;
		m.metalnessNode = float( 0 );
		m.normalNode = normalMap( texture( T.ceiling_tile_normal, uv() ) );
		m.emissiveNode = indirect( albedo, ao );
		return m;
	}
	const ceilMat = ceilMaterial( T.ceiling_tile_albedo ), ceilSMat = ceilMaterial( T.ceiling_tile_stained_albedo );

	function plainMat( color, rough, giScale = 1 ) {
		const m = new THREE.MeshStandardNodeMaterial();
		const c = vec3( color[ 0 ], color[ 1 ], color[ 2 ] );
		m.colorNode = c; m.roughnessNode = float( rough ); m.metalnessNode = float( 0 );
		m.emissiveNode = indirect( c, float( giScale ) );
		return m;
	}
	const tbarMat = plainMat( [ 0.80, 0.79, 0.74 ], 0.45 );
	// painted trim: worn semi-gloss paint, scuffed and darker toward the floor
	const trimMat = new THREE.MeshStandardNodeMaterial();
	{
		const P = positionWorld;
		const n1 = mx_noise_float( P.mul( 3.1 ) ).mul( 0.5 ).add( 0.5 );
		const n2 = mx_noise_float( P.mul( 23.0 ).add( 4.0 ) ).mul( 0.5 ).add( 0.5 );
		const low = smoothstep( 0.45, 0.0, P.y );
		const albedo = vec3( 0.60, 0.56, 0.46 ).mul( mix( 0.86, 1.02, n1 ) ).mul( mix( 0.94, 1.0, n2 ) ).mul( mix( vec3( 1 ), vec3( 0.62, 0.55, 0.44 ), low.mul( 0.8 ) ) );
		trimMat.colorNode = albedo;
		trimMat.roughnessNode = mix( 0.32, 0.55, n1 );
		trimMat.metalnessNode = float( 0 );
		trimMat.normalNode = normalMap( texture( T.wallpaper_normal, uv().mul( 0.35 ) ), vec2( 0.25 ) );
		trimMat.emissiveNode = indirect( albedo, float( 1 ) );
	}
	const houseMat = plainMat( [ 0.86, 0.86, 0.84 ], 0.35, 0.8 );
	const plenMat = plainMat( [ 0.035, 0.032, 0.03 ], 0.95, 0.15 );

	const baseMat = new THREE.MeshStandardNodeMaterial();
	{
		const albedo = texture( T.baseboard_albedo, uv() ).rgb;
		baseMat.colorNode = albedo;
		baseMat.roughnessNode = texture( T.baseboard_roughness, uv() ).r;
		baseMat.metalnessNode = float( 0 );
		baseMat.normalNode = normalMap( texture( T.baseboard_normal, uv() ) );
		baseMat.emissiveNode = indirect( albedo, float( 0.8 ) );
	}

	// lens: per-fixture level from a uniform array indexed by vertex attribute
	const levels = uniformArray( new Array( fixtures.length ).fill( 0 ), 'float' );
	const cathodes = fixtures.map( ( f ) => f.cathode || 0 );
	const cathArr = uniformArray( cathodes, 'float' );
	const lensK = uniform( L_NITS * 1.15 );
	// the lens is an emitter: unlit material (rect lights evaluated on a surface 4 mm from their own plane give LTC noise)
	const lensMat = new THREE.MeshBasicNodeMaterial();
	{
		const fid = attribute( 'fid', 'float' ).add( 0.5 ).floor().toInt(); // round: the interpolated varying is not exact
		const lv = levels.element( fid );
		const cath = cathArr.element( fid );
		const lu = uv();
		const albedo = texture( T.troffer_lens_albedo, lu ).rgb.mul( 0.85 );
		const em = mix( texture( T.troffer_lens_emission, lu ).rgb, vec3( 0.8 ), 0.35 );
		const ends = smoothstep( 0.1, 0.0, lu.y ).add( smoothstep( 0.9, 1.0, lu.y ) ).mul( smoothstep( 0.0, 0.15, lu.x ).mul( smoothstep( 1.0, 0.85, lu.x ) ) );
		lensMat.colorNode = em.mul( vertexColor() ).mul( lv ).mul( lensK )
			.add( vec3( 1.0, 0.38, 0.08 ).mul( cath ).mul( ends ).mul( 2.5 ) )
			.add( indirect( albedo, float( 0.6 ) ) );
	}

	// ------------------------------------------------------------------ meshes
	const meshes = {};
	function addMesh( name, B, mat ) { const m = new THREE.Mesh( B.geometry(), mat ); m.name = name; scene.add( m ); meshes[ name ] = m; return m; }
	addMesh( 'walls', Bwall, wallMat );
	addMesh( 'base', Bbase, baseMat );
	addMesh( 'trim', Btrim, trimMat );
	addMesh( 'floor', Bfloor, floorMat );
	addMesh( 'plenum', Bplen, plenMat );
	addMesh( 'ceil', Bceil, ceilMat );
	addMesh( 'ceilS', BceilS, ceilSMat );
	addMesh( 'tbar', Btbar, tbarMat );
	addMesh( 'lens', Blens, lensMat );
	addMesh( 'house', Bhouse, houseMat );
	scene.updateMatrixWorld( true );

	// decals (projected along local -Y; u along local X, v along local Z)
	const decalMats = {};
	for ( const n of decalNames ) {
		const m = new THREE.MeshStandardNodeMaterial( { transparent: true, depthWrite: false, polygonOffset: true, polygonOffsetFactor: - 4, polygonOffsetUnits: - 4 } );
		const t = texture( T[ n ], uv() );
		const wetD = n === 'decal_floor_wetpatch';
		const albedo = t.rgb;
		m.colorNode = albedo;
		m.opacityNode = t.a.mul( wetD ? 0.9 : 0.85 );
		m.roughnessNode = float( wetD ? 0.3 : 0.85 );
		m.metalnessNode = float( 0 );
		m.emissiveNode = indirect( albedo, float( 1 ) );
		decalMats[ n ] = m;
	}
	for ( const d of scn.decals ) {
		const b = d.basis;
		const X = new THREE.Vector3( b[ 0 ], b[ 1 ], b[ 2 ] ), Y = new THREE.Vector3( b[ 3 ], b[ 4 ], b[ 5 ] ), Z = new THREE.Vector3( b[ 6 ], b[ 7 ], b[ 8 ] );
		const sx = X.length(), sy = Y.length(), sz = Z.length();
		X.normalize(); Y.normalize(); Z.normalize();
		const mtx = new THREE.Matrix4().makeBasis( X, Z, Y.clone().negate() );
		const eul = new THREE.Euler().setFromRotationMatrix( mtx );
		const pos = new THREE.Vector3( ...d.origin );
		const size = new THREE.Vector3( d.size[ 0 ] * sx, d.size[ 2 ] * sz, d.size[ 1 ] * sy );
		let targets;
		if ( d.tex === 'decal_floor_wetpatch' ) targets = [ meshes.floor ];
		else if ( d.tex === 'decal_ceiling_stain' ) targets = [ meshes.ceil, meshes.ceilS ];
		else targets = [ meshes.walls, meshes.base ];
		for ( const tm of targets ) {
			const g = new DecalGeometry( tm, pos, eul, size );
			if ( g.attributes.position.count === 0 ) continue;
			const dm = new THREE.Mesh( g, decalMats[ d.tex ] );
			dm.renderOrder = 2;
			scene.add( dm );
		}
	}

	// ------------------------------------------------------------------ light pool (rect area lights with 2D visibility masks)
	const pool = [];
	for ( let k = 0; k < POOL; k ++ ) {
		const light = new THREE.RectAreaLight( 0xffffff, 1, 0.58, 1.18 );
		const colU = uniform( new THREE.Color( 0, 0, 0 ) );
		const layerU = uniform( 0, 'int' );
		const vis = Fn( () => {
			const p = positionWorld.xz.add( normalWorld.xz.mul( 0.12 ) ).div( MAP );
			return texture( visTex, p ).depth( layerU ).r;
		} );
		light.colorNode = colU.mul( vis() );
		light.rotation.x = - Math.PI / 2;
		light.position.set( 0, LENS_Y + 0.004, 0 );
		scene.add( light );
		pool.push( { light, colU, layerU, fix: - 1 } );
	}

	// ------------------------------------------------------------------ post
	const pipeline = new THREE.RenderPipeline( renderer );
	const scenePass = pass( scene, camera );
	scenePass.setMRT( mrt( { output, diffuseColor, normal: packNormalToRGB( normalView ), velocity } ) );
	const colorT = scenePass.getTextureNode( 'output' );
	const diffT = scenePass.getTextureNode( 'diffuseColor' );
	const depthT = scenePass.getTextureNode( 'depth' );
	const normT = scenePass.getTextureNode( 'normal' );
	const velT = scenePass.getTextureNode( 'velocity' );
	scenePass.getTexture( 'diffuseColor' ).type = THREE.UnsignedByteType;
	scenePass.getTexture( 'normal' ).type = THREE.UnsignedByteType;
	const sceneNormal = sample( ( u ) => unpackRGBToNormal( normT.sample( u ) ) );
	const giBeauty = vec4( colorT.rgb.min( vec3( 0.7 ) ), colorT.a ); // clamp emitters so SSGI does not sparkle
	const giPass = ssgi( giBeauty, depthT, sceneNormal, camera );
	giPass.sliceCount.value = 2;
	giPass.stepCount.value = 8;
	giPass.radius.value = 3.0;
	giPass.giIntensity.value = 0.0; // screen-space GI sparkles on dim surfaces at this sample count; bounce comes from the baked 2D GI map instead
	giPass.aoIntensity.value = 1.15;
	giPass.thickness.value = 0.6;
	const aoN = giPass.getAONode();
	// keep AO off emitters (its 4x4 sampling lattice shows up on the very bright lenses)
	const emitMask = smoothstep( 1.2, 3.0, max( colorT.r, max( colorT.g, colorT.b ) ) );
	const comp = vec4( colorT.rgb.mul( mix( aoN, float( 1 ), emitMask ) ), colorT.a );
	const taa = traa( comp, depthT, velT, camera );
	const taaTex = taa.getTextureNode();
	const bloomPass = bloom( taa, 0.16, 0.45, 2.6 );
	const frameU = uniform( 0 );
	const exposureU = uniform( 1.0 );
	const post = Fn( () => {
		const suv = screenUV;
		const d = suv.sub( 0.5 );
		const r2 = dot( d, d );
		const off = d.mul( r2 ).mul( 0.0045 );
		const c = PARAMS.has( 'notaa' ) ? comp.rgb : vec3( taaTex.sample( suv.sub( off ) ).r, taa.g, taaTex.sample( suv.add( off ) ).b ).add( bloomPass.rgb );
		const asp = vec2( d.x.mul( 16 / 9 ), d.y );
		const vig = float( 1 ).sub( smoothstep( 0.35, 1.25, length( asp ) ).mul( 0.42 ) );
		const n = hash( suv.mul( vec2( 2560, 1440 ) ).floor().add( frameU.mul( vec2( 17.13, 31.71 ) ) ).dot( vec2( 1.0, 4096.0 ) ) );
		const n2 = hash( suv.mul( vec2( 2560, 1440 ) ).floor().add( frameU.mul( vec2( 7.3, 11.9 ) ).add( 91.0 ) ).dot( vec2( 1.0, 4096.0 ) ) );
		const grain = n.add( n2 ).sub( 1.0 ).mul( PARAMS.has( 'nograin' ) ? 0.0 : 0.055 );
		const ce = c.mul( vig ).mul( exposureU ).max( 0 );
		const cc = pow( ce.div( 0.18 ), vec3( 1.12 ) ).mul( 0.18 ); // gentle filmic contrast around mid grey
		return vec4( cc.mul( grain.add( 1.0 ) ), 1.0 );
	} );
	pipeline.outputNode = post();

	// ------------------------------------------------------------------ per-frame state
	const curLevels = new Float32Array( fixtures.length );
	function setLevels( lv ) {
		for ( let k = 0; k < fixtures.length; k ++ ) {
			const s = fixtures[ k ].state;
			let v = s === 0 ? 1 : 0;
			if ( s >= 2 ) v = lv && lv[ String( k ) ] !== undefined ? lv[ String( k ) ] : 1;
			curLevels[ k ] = v;
			levels.array[ k ] = v;
		}
		giW.array[ 0 ] = 1;
		animIdx.forEach( ( k, a ) => { giW.array[ 1 + a ] = curLevels[ k ]; } );
	}

	const fwd = new THREE.Vector3();
	function assignPool() {
		camera.getWorldDirection( fwd );
		const cx = camera.position.x, cz = camera.position.z;
		const fl = Math.hypot( fwd.x, fwd.z ) || 1, fx = fwd.x / fl, fz = fwd.z / fl;
		const cand = [];
		for ( let l = 0; l < NL; l ++ ) {
			const k = emitIdx[ l ];
			if ( curLevels[ k ] < 0.004 ) continue;
			const f = fixtures[ k ];
			const dx = f.x - cx, dz = f.z - cz, d = Math.hypot( dx, dz );
			if ( d > 26 ) continue;
			const front = d < 3 ? 1 : ( dx * fx + dz * fz ) / d;
			const visCam = APP.visCPU( l, cx, cz );
			let score = d - 7 * Math.min( 1, visCam * 2 ) - 5 * Math.max( 0, front );
			if ( front < - 0.5 && d > 6 ) score += 12;
			cand.push( [ score, k, l ] );
		}
		cand.sort( ( a, b ) => a[ 0 ] - b[ 0 ] );
		for ( let p = 0; p < POOL; p ++ ) {
			const e = pool[ p ];
			if ( p < cand.length ) {
				const [ , k, l ] = cand[ p ];
				const f = fixtures[ k ];
				const I = L_NITS * f.energy * curLevels[ k ];
				e.colU.value.setRGB( f.tint[ 0 ] * I, f.tint[ 1 ] * I, f.tint[ 2 ] * I );
				e.layerU.value = l;
				e.light.position.set( f.x, LENS_Y + 0.004, f.z );
				e.light.visible = true;
			} else {
				e.colU.value.setRGB( 0, 0, 0 );
				e.light.position.set( - 100, - 100, - 100 );
			}
		}
	}

	// slow auto exposure driven by the bounce-light level the camera is looking into
	let expCur = null;
	const EXP_KEY = 0.55;
	function meterTarget() {
		camera.getWorldDirection( fwd );
		const w = giW.array;
		let s = 0, c = 0;
		for ( const dist of [ 0, 1.0, 2.0, 3.5, 5.0 ] ) for ( const side of [ - 0.35, 0, 0.35 ] ) {
			const ang = Math.atan2( fwd.z, fwd.x ) + side;
			const x = camera.position.x + Math.cos( ang ) * dist, z = camera.position.z + Math.sin( ang ) * dist;
			if ( x < 0 || z < 0 || x > MAP || z > MAP ) continue;
			s += APP.giCPU( x, z, w ); c ++;
		}
		const avg = Math.max( 0.05, s / Math.max( 1, c ) );
		return Math.min( 1.9, Math.max( 0.55, Math.pow( EXP_KEY / avg, 0.5 ) ) );
	}
	function updateExposure( dt, snap ) {
		const tgt = meterTarget();
		if ( expCur === null || snap ) expCur = tgt;
		const k = 1 - Math.exp( - dt / 1.6 );
		expCur += ( tgt - expCur ) * k;
		exposureU.value = expCur;
	}

	let frameNo = 0;
	function render( dt = 1 / 30 ) {
		assignPool();
		updateExposure( dt, false );
		frameU.value = ( frameNo ++ ) % 1000;
		pipeline.render();
	}

	function setTrackFrame( idx ) {
		const fr = track.frames[ idx ];
		camera.position.set( fr[ 2 ], fr[ 3 ], fr[ 4 ] );
		camera.quaternion.set( fr[ 5 ], fr[ 6 ], fr[ 7 ], fr[ 8 ] );
		if ( camera.fov !== fr[ 9 ] ) { camera.fov = fr[ 9 ]; camera.updateProjectionMatrix(); }
		setLevels( fr[ 11 ] );
		camera.updateMatrixWorld( true );
	}
	function setPose( p ) {
		camera.position.set( p.pos[ 0 ], p.pos[ 1 ], p.pos[ 2 ] );
		camera.rotation.set( THREE.MathUtils.degToRad( p.pitch_deg ), - THREE.MathUtils.degToRad( p.yaw_deg ), 0, 'YXZ' );
		camera.fov = p.fov; camera.updateProjectionMatrix();
		setLevels( track.frames[ 0 ][ 11 ] );
		camera.updateMatrixWorld( true );
	}
	function setSize( w, h ) {
		renderer.setSize( w, h, false );
		camera.aspect = w / h; camera.updateProjectionMatrix();
	}
	function grab( type = 'image/png', q = 0.95 ) {
		return new Promise( ( res ) => renderer.domElement.toBlob( res, type, q ) );
	}

	Object.assign( APP, { setTrackFrame, setPose, setSize, render, grab, renderer, scene, camera, pipeline, exposureU, giK, hazeK, lensK, giPass, resetExposure: () => { expCur = null; } } );

	// warm up compile
	setTrackFrame( 0 );
	updateExposure( 0, true );
	await renderer.compileAsync( scene, camera );
	render();
	await renderer.backend.device?.queue.onSubmittedWorkDone();
	APP.status = 'ready';
}
