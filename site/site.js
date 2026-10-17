// NOCLIP landing page: clips play while on screen, the camcorder clock ticks, the bar turns solid past the hero.
// Everything works without this script except the motion.
(function () {
  'use strict';
  const reduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  const conn = navigator.connection;
  // data saver only on real slow links (a "3g" label is common on fine connections)
  const saveData = !!(conn && (conn.saveData || /(^|-)2g$/.test(conn.effectiveType || '')));

  const bar = document.querySelector('.bar');
  const hero = document.querySelector('.hero');
  const onBar = () => bar.classList.toggle('solid', window.scrollY > hero.offsetHeight - 80);
  window.addEventListener('scroll', onBar, { passive: true });
  onBar();

  const heroVideo = document.querySelector('.hero-video');
  if (reduced || saveData) {
    heroVideo.removeAttribute('autoplay');
    heroVideo.pause();
  }

  // the viewfinder clock counts up from the moment the tape starts
  const clock = document.getElementById('clock');
  if (clock && !reduced) {
    const t0 = Date.now();
    const base = 23 * 3600 + 49 * 60 + 7;
    const pad = (n) => String(n).padStart(2, '0');
    setInterval(() => {
      const s = (base + Math.floor((Date.now() - t0) / 1000)) % 86400;
      const h = Math.floor(s / 3600);
      clock.textContent = `${h >= 12 ? 'PM' : 'AM'} ${pad(h % 12 || 12)}:${pad(Math.floor(s / 60) % 60)}:${pad(s % 60)}`;
    }, 1000);
  }

  const play = (v) => {
    if (saveData || reduced) {
      v.controls = true;
      return;
    }
    if (v.preload === 'none') v.preload = 'auto';
    v.play().catch(() => (v.controls = true));
  };

  const inview = [...document.querySelectorAll('video[data-inview]')];
  if ('IntersectionObserver' in window) {
    const io = new IntersectionObserver(
      (es) => {
        for (const e of es) {
          if (e.isIntersecting) play(e.target);
          else e.target.pause();
        }
      },
      { threshold: 0.45 },
    );
    inview.forEach((v) => io.observe(v));
  } else {
    inview.forEach((v) => (v.controls = true));
  }
})();
