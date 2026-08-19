"use client";

/**
 * 可复用思考球体（对标 orbs.jakubantalik.com ThinkingOrb）：
 * 透明背景，三条 3D 轨道粒子旋转 + 中心核脉动，用于各类"加载中"场景
 * （影视库搜索、播放页换源、线路加载等）。
 */
export default function ThinkingOrb({ size = 40 }: { size?: number }) {
  return (
    <span
      className="thinking-orb"
      style={{ width: size, height: size }}
      aria-hidden="true"
    >
      <span className="orb-track orb-track-1" />
      <span className="orb-track orb-track-2" />
      <span className="orb-track orb-track-3" />
      <span className="orb-core" />
    </span>
  );
}
