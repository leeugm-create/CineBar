"use client";

import { useEffect, useRef } from "react";

/**
 * 主标题粒子文字（2026-08-19）：
 * 标题逐字采样成密集粒子（"找到 / 下一部好片"），粒子缓慢回弹归位，
 * 鼠标移过时局部推开；密集采样保证标题清晰可读。
 */
type P = { tx: number; ty: number; x: number; y: number; vx: number; vy: number };

export default function CinebarTitleParticles({
  lines,
}: {
  lines: string[];
}) {
  const canvasRef = useRef<HTMLCanvasElement>(null);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext("2d");
    if (!ctx) return;
    let raf = 0;
    let particles: P[] = [];
    let w = 0;
    let h = 0;
    const mouse = { x: -9999, y: -9999 };
    const DPR = Math.min(window.devicePixelRatio || 1, 2);
    let running = true;
    const isReduced = matchMedia("(prefers-reduced-motion: reduce)").matches;

    function build() {
      const off = document.createElement("canvas");
      off.width = w;
      off.height = h;
      const octx = off.getContext("2d");
      if (!octx) return;
      // 大字号 + 左对齐（2026-08-19 用户要求主标放左侧红框位置，不居中偏右）
      const fontSize = Math.min(h * 0.42, (w / Math.max(...lines.map((l) => l.length))) * 1.6);
      octx.font = `900 ${fontSize}px Inter, -apple-system, "PingFang SC", "Hiragino Sans GB", "Microsoft YaHei", sans-serif`;
      octx.textAlign = "left";
      octx.textBaseline = "middle";
      octx.fillStyle = "#fff";
      const padX = w * 0.02;
      const lineH = fontSize * 1.3;
      const startY = h / 2 - ((lines.length - 1) * lineH) / 2;
      lines.forEach((line, i) => {
        octx.fillText(line, padX, startY + i * lineH);
      });
      const img = octx.getImageData(0, 0, w, h);
      particles = [];
      // 密集采样：步长随容器自适应（w/260 左右 → 标题可见且粒子密）
      const step = Math.max(3, Math.round(w / 260));
      for (let y = 0; y < h; y += step) {
        for (let x = 0; x < w; x += step) {
          if (img.data[(y * w + x) * 4 + 3] > 128) {
            particles.push({
              tx: x,
              ty: y,
              x: x + (Math.random() - 0.5) * 36,
              y: y + (Math.random() - 0.5) * 36,
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
      h = Math.max(80, rect.height);
      canvas.width = w * DPR;
      canvas.height = h * DPR;
      ctx.setTransform(DPR, 0, 0, DPR, 0, 0);
      build();
    }

    function color(): string {
      const style = getComputedStyle(document.documentElement);
      return (style.getPropertyValue("--foreground") || "#111827").trim();
    }

    function drawStatic() {
      ctx.clearRect(0, 0, w, h);
      ctx.fillStyle = color();
      for (const p of particles) ctx.fillRect(p.x, p.y, 2.2, 2.2);
    }

    function tick() {
      if (!running) return;
      ctx.clearRect(0, 0, w, h);
      ctx.fillStyle = color();
      const dot = Math.max(1.8, Math.min(2.6, w / 320));
      for (const p of particles) {
        // 弹簧回弹归位
        p.vx += (p.tx - p.x) * 0.06;
        p.vy += (p.ty - p.y) * 0.06;
        // 鼠标局部排斥（半径小，保持标题整体可读）
        const dx = p.x - mouse.x;
        const dy = p.y - mouse.y;
        const d = Math.hypot(dx, dy);
        if (d < 34 && d > 0.01) {
          const f = (34 - d) / 34;
          p.vx += (dx / d) * f * 1.6;
          p.vy += (dy / d) * f * 1.6;
        }
        p.vx *= 0.82;
        p.vy *= 0.82;
        p.x += p.vx;
        p.y += p.vy;
        ctx.fillRect(p.x, p.y, dot, dot);
      }
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
  }, [lines.join("|")]);

  return <canvas ref={canvasRef} className="cinebar-title-particles" aria-hidden="true" />;
}
