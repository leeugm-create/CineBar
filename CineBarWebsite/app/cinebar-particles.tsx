"use client";

import { useEffect, useRef } from "react";

/**
 * CineBar 粒子网背景（对标 particles.js，2026-08-19）：
 * 随机粒子缓慢漂移 + 邻近粒子连线（网）+ 鼠标排斥；
 * 透明背景、主题色（accent）自适应、减动效/不可见时暂停。
 */
type Particle = { x: number; y: number; vx: number; vy: number; r: number };

export default function CinebarParticles() {
  const canvasRef = useRef<HTMLCanvasElement>(null);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext("2d");
    if (!ctx) return;
    let raf = 0;
    let particles: Particle[] = [];
    let w = 0;
    let h = 0;
    const mouse = { x: -9999, y: -9999 };
    const DPR = Math.min(window.devicePixelRatio || 1, 2);
    let running = true;
    const isReduced = matchMedia("(prefers-reduced-motion: reduce)").matches;

    function targetCount(): number {
      const area = w * h;
      return Math.max(52, Math.min(280, Math.round(area / 6900))); // 2026-08-19 用户要求+30%
    }

    function build() {
      particles = [];
      const count = targetCount();
      for (let i = 0; i < count; i++) {
        particles.push({
          x: Math.random() * w,
          y: Math.random() * h,
          vx: (Math.random() - 0.5) * 0.55,
          vy: (Math.random() - 0.5) * 0.55,
          r: Math.random() * 1.6 + 1.2,
        });
      }
    }

    function resize() {
      // 画布固定全视口：粒子无容器边界限制（2026-08-19 用户要求"不要给粒子加范围限制"）
      w = Math.max(200, window.innerWidth);
      h = Math.max(120, window.innerHeight);
      canvas.width = w * DPR;
      canvas.height = h * DPR;
      ctx.setTransform(DPR, 0, 0, DPR, 0, 0);
      build();
    }

    function themeColors(): { particle: string; link: string } {
      const style = getComputedStyle(document.documentElement);
      const accent = (style.getPropertyValue("--accent") || "#f97316").trim();
      const isDark = document.documentElement.dataset.theme === "dark";
      return { particle: accent, link: isDark ? "255,255,255" : "120,120,130" };
    }

    const LINK_DIST = 110;
    const REPULSE = 130;

    function drawStatic() {
      const { particle } = themeColors();
      ctx.clearRect(0, 0, w, h);
      ctx.fillStyle = particle;
      for (const p of particles) ctx.fillRect(p.x, p.y, p.r, p.r);
    }

    function tick() {
      if (!running) return;
      const { particle, link } = themeColors();
      ctx.clearRect(0, 0, w, h);
      const n = particles.length;
      for (const p of particles) {
        p.x += p.vx;
        p.y += p.vy;
        if (p.x < 0 || p.x > w) p.vx *= -1;
        if (p.y < 0 || p.y > h) p.vy *= -1;
        const dx = p.x - mouse.x;
        const dy = p.y - mouse.y;
        const d = Math.hypot(dx, dy);
        if (d < REPULSE && d > 0.01) {
          const f = (REPULSE - d) / REPULSE;
          p.x += (dx / d) * f * 2.2;
          p.y += (dy / d) * f * 2.2;
        }
      }
      ctx.lineWidth = 1;
      const l2 = LINK_DIST * LINK_DIST;
      for (let i = 0; i < n; i++) {
        const a = particles[i];
        for (let j = i + 1; j < n; j++) {
          const b = particles[j];
          const dx = a.x - b.x;
          const dy = a.y - b.y;
          const d2 = dx * dx + dy * dy;
          if (d2 < l2) {
            const alpha = 0.4 * (1 - d2 / l2);
            ctx.strokeStyle = `rgba(${link},${alpha})`;
            ctx.beginPath();
            ctx.moveTo(a.x, a.y);
            ctx.lineTo(b.x, b.y);
            ctx.stroke();
          }
        }
      }
      ctx.fillStyle = particle;
      ctx.globalAlpha = 0.85;
      for (const p of particles) ctx.fillRect(p.x, p.y, p.r, p.r);
      ctx.globalAlpha = 1;
      raf = requestAnimationFrame(tick);
    }

    function onMove(e: MouseEvent) {
      const rect = canvas.getBoundingClientRect();
      mouse.x = e.clientX - rect.left;
      mouse.y = e.clientY - rect.top;
    }
    function onLeave() {
      mouse.x = -9999;
      mouse.y = -9999;
    }
    function onVisibility() {
      running = document.visibilityState === "visible";
      if (running) raf = requestAnimationFrame(tick);
    }

    resize();
    if (isReduced) {
      drawStatic();
    } else {
      raf = requestAnimationFrame(tick);
    }
    window.addEventListener("resize", resize);
    window.addEventListener("mousemove", onMove);
    canvas.addEventListener("mouseleave", onLeave);
    document.addEventListener("visibilitychange", onVisibility);

    return () => {
      cancelAnimationFrame(raf);
      window.removeEventListener("resize", resize);
      window.removeEventListener("mousemove", onMove);
      canvas.removeEventListener("mouseleave", onLeave);
      document.removeEventListener("visibilitychange", onVisibility);
    };
  }, []);

  return <canvas ref={canvasRef} className="cinebar-particles" aria-hidden="true" />;
}
