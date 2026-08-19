"use client";

import { useEffect, useRef } from "react";

/**
 * CineBar 粒子文字背景（2026-08-19）：
 * 粒子采样 "CineBar" 字形 → 鼠标移过时粒子被推开、松手弹性回弹；
 * 邻近粒子画连线（线条穿插文字）；透明背景、主题色（accent）自适应、减动效/不可见时暂停。
 */
type Particle = { tx: number; ty: number; x: number; y: number; vx: number; vy: number };

export default function CinebarParticles({ text = "CineBar" }: { text?: string }) {
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

    function build() {
      const off = document.createElement("canvas");
      off.width = w;
      off.height = h;
      const octx = off.getContext("2d");
      if (!octx) return;
      octx.font = `900 ${Math.min(h * 0.34, w * 0.17)}px Inter, -apple-system, "SF Pro Display", sans-serif`;
      octx.textAlign = "center";
      octx.textBaseline = "middle";
      octx.fillStyle = "#fff";
      octx.fillText(text, w / 2, h / 2);
      const img = octx.getImageData(0, 0, w, h);
      particles = [];
      const step = Math.max(5, Math.round(w / 170));
      for (let y = 0; y < h; y += step) {
        for (let x = 0; x < w; x += step) {
          if (img.data[(y * w + x) * 4 + 3] > 128) {
            particles.push({
              tx: x,
              ty: y,
              x: x + (Math.random() - 0.5) * 50,
              y: y + (Math.random() - 0.5) * 50,
              vx: 0,
              vy: 0,
            });
          }
        }
      }
    }

    function resize() {
      const parent = canvas.parentElement;
      if (!parent) return;
      const rect = parent.getBoundingClientRect();
      w = Math.max(200, rect.width);
      h = Math.max(120, rect.height);
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

    function tick() {
      if (!running) return;
      const { particle, link } = themeColors();
      ctx.clearRect(0, 0, w, h);
      const n = particles.length;
      // 物理：弹性回弹 + 鼠标排斥
      for (const p of particles) {
        p.vx += (p.tx - p.x) * 0.045;
        p.vy += (p.ty - p.y) * 0.045;
        const mx = p.x - mouse.x;
        const my = p.y - mouse.y;
        const md = Math.hypot(mx, my);
        if (md < 90 && md > 0.01) {
          p.vx += (mx / md) * 2.4;
          p.vy += (my / md) * 2.4;
        }
        p.vx *= 0.85;
        p.vy *= 0.85;
        p.x += p.vx;
        p.y += p.vy;
      }
      // 邻近连线（每粒子只向后查，阈值 36px，控制绘制量）
      ctx.lineWidth = 1;
      const linkThreshold2 = 36 * 36;
      for (let i = 0; i < n; i++) {
        const a = particles[i];
        for (let j = i + 1; j < n; j++) {
          const b = particles[j];
          const dx = a.x - b.x;
          const dy = a.y - b.y;
          const d2 = dx * dx + dy * dy;
          if (d2 < linkThreshold2) {
            const alpha = 0.32 * (1 - d2 / linkThreshold2);
            ctx.strokeStyle = `rgba(${link},${alpha})`;
            ctx.beginPath();
            ctx.moveTo(a.x, a.y);
            ctx.lineTo(b.x, b.y);
            ctx.stroke();
          }
        }
      }
      // 粒子
      ctx.fillStyle = particle;
      ctx.globalAlpha = 0.85;
      const s = Math.max(1.6, Math.min(2.4, w / 500));
      for (const p of particles) {
        ctx.fillRect(p.x, p.y, s, s);
      }
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
      if (running) {
        cancelAnimationFrame(raf);
        raf = requestAnimationFrame(tick);
      }
    }
    function onReduced() {
      // prefers-reduced-motion：静止显示粒子（不动画）
      if (matchMedia("(prefers-reduced-motion: reduce)").matches) {
        cancelAnimationFrame(raf);
        running = false;
        // 直接绘制一次静态字形
        build();
        for (const p of particles) { p.x = p.tx; p.y = p.ty; }
        ctx.clearRect(0, 0, w, h);
        const { particle } = themeColors();
        ctx.fillStyle = particle;
        for (const p of particles) ctx.fillRect(p.x, p.y, 2, 2);
      }
    }

    resize();
    raf = requestAnimationFrame(tick);
    window.addEventListener("resize", resize);
    window.addEventListener("mousemove", onMove);
    canvas.addEventListener("mouseleave", onLeave);
    document.addEventListener("visibilitychange", onVisibility);
    onReduced();

    return () => {
      cancelAnimationFrame(raf);
      window.removeEventListener("resize", resize);
      window.removeEventListener("mousemove", onMove);
      canvas.removeEventListener("mouseleave", onLeave);
      document.removeEventListener("visibilitychange", onVisibility);
    };
  }, [text]);

  return <canvas ref={canvasRef} className="cinebar-particles" aria-hidden="true" />;
}
