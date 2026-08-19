"use client";

// Brush Reveal — Originkit PaintText
// 鼠标扫过文字时"刷笔揭示"：ghost 色淡出、paint 色淡入，移开/超时自动复位。
import * as React from "react";
import { useEffect, useMemo, useRef } from "react";

type FontStyle = React.CSSProperties & {
  fontFamily?: string;
  fontWeight?: number | string;
  fontSize?: number | string;
  letterSpacing?: number | string;
  lineHeight?: number | string;
};

type Props = {
  text?: string;
  font?: FontStyle;
  paintColor?: string;
  ghostColor?: string;
  autoReset?: boolean;
  autoResetDelay?: number;
  style?: React.CSSProperties;
};

type Point = { x: number; y: number };
type PointerSegment = { end: Point; eventTime: number; start: Point };
type GlyphGeometry = { paintable: boolean; x: number; y: number };
type LocalSpace = { rect: DOMRect; scaleX: number; scaleY: number };

const DEFAULT_FONT: FontStyle = {
  fontFamily: "Inter, system-ui, sans-serif",
  fontSize: "120px",
  fontWeight: 400,
  letterSpacing: "0em",
  lineHeight: "1.1em",
  textAlign: "left",
};

const PAINT_RESPONSE_MS = 90;
const RESET_FADE_MS = 600;
const BRUSH_TO_FONT_RATIO = 1.5;
const MINIMUM_BRUSH_RADIUS = 12;
const MAX_PENDING_SEGMENTS = 64;
const PROGRESS_EPSILON = 0.0001;

const isSpace = (character: string): boolean =>
  character === " " || character === "\n" || character === "\t";

const prefersReducedMotion = (): boolean =>
  typeof window !== "undefined" &&
  window.matchMedia("(prefers-reduced-motion: reduce)").matches;

const clamp = (value: number, min: number, max: number): number =>
  Math.min(max, Math.max(min, value));

const getDistanceToSegment = (point: Point, start: Point, end: Point): number => {
  const segmentX = end.x - start.x;
  const segmentY = end.y - start.y;
  const lengthSquared = segmentX * segmentX + segmentY * segmentY;
  if (lengthSquared === 0) {
    return Math.hypot(point.x - start.x, point.y - start.y);
  }
  const projection = clamp(
    ((point.x - start.x) * segmentX + (point.y - start.y) * segmentY) / lengthSquared,
    0,
    1
  );
  const nearestX = start.x + segmentX * projection;
  const nearestY = start.y + segmentY * projection;
  return Math.hypot(point.x - nearestX, point.y - nearestY);
};

const getProximityFalloff = (distance: number, radius: number): number => {
  const proximity = clamp(1 - distance / radius, 0, 1);
  return proximity * proximity * (3 - 2 * proximity);
};

const segmentIntersectsExpandedRect = (
  segment: PointerSegment,
  rect: DOMRect,
  padding: number
): boolean => {
  const minX = Math.min(segment.start.x, segment.end.x);
  const maxX = Math.max(segment.start.x, segment.end.x);
  const minY = Math.min(segment.start.y, segment.end.y);
  const maxY = Math.max(segment.start.y, segment.end.y);
  return (
    maxX >= rect.left - padding &&
    minX <= rect.right + padding &&
    maxY >= rect.top - padding &&
    minY <= rect.bottom + padding
  );
};

function PaintTextBase({
  text = "Brush Reveal",
  font = DEFAULT_FONT,
  paintColor = "#ffffff",
  ghostColor = "rgba(127, 127, 127, 0.22)",
  autoReset = true,
  autoResetDelay = 2.8,
  style,
}: Props) {
  const characters = useMemo(() => Array.from(text), [text]);
  const wrapperRef = useRef<HTMLParagraphElement>(null);
  const glyphRefs = useRef<(HTMLSpanElement | null)[]>([]);
  const ghostRefs = useRef<(HTMLSpanElement | null)[]>([]);
  const paintRefs = useRef<(HTMLSpanElement | null)[]>([]);

  const autoResetMs = autoReset ? Math.max(0, autoResetDelay) * 1000 : 0;

  useEffect(() => {
    const wrapper = wrapperRef.current;
    if (!wrapper) return;

    let cancelled = false;
    let frameId: number | null = null;
    let resetTimer: ReturnType<typeof setTimeout> | null = null;
    let previousFrameTime = performance.now();
    let previousPointer: Point | null = null;
    let currentPointer: Point | null = null;
    let lastPointerMoveTime = 0;
    let brushRadius = 108;
    let glyphGeometry: GlyphGeometry[] = [];
    let pendingSegments: PointerSegment[] = [];
    const paintProgress = characters.map(() => 0);
    const lastContactTimes = characters.map(() => 0);
    const reducedMotion = prefersReducedMotion();

    const applyProgress = (index: number, progress: number) => {
      const ghost = ghostRefs.current[index];
      const paint = paintRefs.current[index];
      if (!ghost || !paint) return;
      const previousProgress = paintProgress[index] ?? 0;
      if (Math.abs(previousProgress - progress) < PROGRESS_EPSILON) return;
      paintProgress[index] = progress;
      paint.style.opacity = String(progress);
      ghost.style.opacity = String(1 - progress);
    };

    const resetAllGlyphs = () => {
      for (let index = 0; index < characters.length; index += 1) {
        paintProgress[index] = 0;
        lastContactTimes[index] = 0;
        const ghost = ghostRefs.current[index];
        const paint = paintRefs.current[index];
        if (ghost) ghost.style.opacity = "1";
        if (paint) paint.style.opacity = "0";
      }
    };

    const getLocalSpace = (): LocalSpace => {
      const rect = wrapper.getBoundingClientRect();
      return {
        rect,
        scaleX: rect.width / Math.max(1, wrapper.clientWidth) || 1,
        scaleY: rect.height / Math.max(1, wrapper.clientHeight) || 1,
      };
    };

    const measureGeometry = () => {
      const { rect: wrapperRect, scaleX, scaleY } = getLocalSpace();
      const computedFontSize = Number.parseFloat(
        window.getComputedStyle(wrapper).fontSize
      );
      if (Number.isFinite(computedFontSize)) {
        brushRadius = Math.max(MINIMUM_BRUSH_RADIUS, computedFontSize * BRUSH_TO_FONT_RATIO);
      }
      glyphGeometry = characters.map((character, index) => {
        const glyph = glyphRefs.current[index];
        if (!glyph || isSpace(character)) {
          return { paintable: false, x: 0, y: 0 };
        }
        const rect = glyph.getBoundingClientRect();
        return {
          paintable: true,
          x: (rect.left - wrapperRect.left + rect.width / 2) / scaleX,
          y: (rect.top - wrapperRect.top + rect.height / 2) / scaleY,
        };
      });
      previousPointer = currentPointer;
      pendingSegments = [];
    };

    const toLocalPoint = (point: Point, localSpace: LocalSpace): Point => {
      const { rect, scaleX, scaleY } = localSpace;
      return {
        x: (point.x - rect.left) / scaleX,
        y: (point.y - rect.top) / scaleY,
      };
    };

    const clearResetTimer = () => {
      if (!resetTimer) return;
      clearTimeout(resetTimer);
      resetTimer = null;
    };

    const ensureAnimation = () => {
      if (frameId !== null || cancelled) return;
      clearResetTimer();
      previousFrameTime = performance.now();
      frameId = requestAnimationFrame(runFrame);
    };

    const scheduleNextReset = (currentTime: number) => {
      if (autoResetMs <= 0 || resetTimer || cancelled) return;
      let earliestResetTime = Number.POSITIVE_INFINITY;
      for (let index = 0; index < paintProgress.length; index += 1) {
        if ((paintProgress[index] ?? 0) <= PROGRESS_EPSILON) continue;
        const lastContactTime = lastContactTimes[index] ?? 0;
        if (lastContactTime <= 0) continue;
        earliestResetTime = Math.min(earliestResetTime, lastContactTime + autoResetMs);
      }
      if (!Number.isFinite(earliestResetTime)) return;
      const delay = Math.max(0, earliestResetTime - currentTime);
      resetTimer = setTimeout(() => {
        resetTimer = null;
        ensureAnimation();
      }, delay);
    };

    const runFrame: FrameRequestCallback = (currentTime) => {
      frameId = null;
      const elapsed = Math.max(1, currentTime - previousFrameTime);
      previousFrameTime = currentTime;
      const pointerIsFresh =
        currentPointer !== null &&
        (autoResetMs <= 0 || currentTime - lastPointerMoveTime < autoResetMs);
      const segments = pendingSegments;
      pendingSegments = [];
      const localSpace = pointerIsFresh || segments.length > 0 ? getLocalSpace() : null;
      const localSegments = localSpace
        ? segments.map((segment) => ({
            end: toLocalPoint(segment.end, localSpace),
            eventTime: segment.eventTime,
            start: toLocalPoint(segment.start, localSpace),
          }))
        : [];
      const localPointer =
        currentPointer && localSpace ? toLocalPoint(currentPointer, localSpace) : null;
      let needsNextFrame = false;

      for (let index = 0; index < glyphGeometry.length; index += 1) {
        const geometry = glyphGeometry[index];
        if (!geometry?.paintable) continue;

        let progress = paintProgress[index] ?? 0;
        const pointerDistance = localPointer
          ? Math.hypot(geometry.x - localPointer.x, geometry.y - localPointer.y)
          : Number.POSITIVE_INFINITY;
        let minimumDistance = pointerDistance;
        let latestContactTime = 0;

        for (const segment of localSegments) {
          const distance = getDistanceToSegment(geometry, segment.start, segment.end);
          if (distance < minimumDistance) minimumDistance = distance;
          if (distance < brushRadius) {
            latestContactTime = Math.max(latestContactTime, segment.eventTime);
          }
        }

        const falloff = getProximityFalloff(minimumDistance, brushRadius);
        if (pointerIsFresh && falloff > 0) {
          lastContactTimes[index] = Math.max(latestContactTime, currentTime);
          const response = reducedMotion ? 1 : 1 - Math.exp(-(elapsed * falloff) / PAINT_RESPONSE_MS);
          const nextProgress = reducedMotion ? 1 : progress + (1 - progress) * response;
          applyProgress(index, nextProgress);
          progress = nextProgress;
          const pointerFalloff = getProximityFalloff(pointerDistance, brushRadius);
          if (!reducedMotion && pointerFalloff > 0 && progress < 1 - PROGRESS_EPSILON) {
            needsNextFrame = true;
          }
          continue;
        }

        const lastContactTime = lastContactTimes[index] ?? 0;
        const resetDue =
          autoResetMs > 0 &&
          lastContactTime > 0 &&
          currentTime >= lastContactTime + autoResetMs;
        if (!resetDue) continue;

        const nextProgress = reducedMotion ? 0 : Math.max(0, progress - elapsed / RESET_FADE_MS);
        applyProgress(index, nextProgress);
        progress = nextProgress;
        if (progress > PROGRESS_EPSILON) needsNextFrame = true;
      }

      previousPointer = currentPointer;
      if (needsNextFrame || pendingSegments.length > 0) {
        frameId = requestAnimationFrame(runFrame);
        return;
      }
      scheduleNextReset(currentTime);
    };

    const handlePointerMove = (event: PointerEvent) => {
      const point = { x: event.clientX, y: event.clientY };
      const eventTime = performance.now();
      const segment: PointerSegment = {
        end: point,
        eventTime,
        start: previousPointer ?? point,
      };
      previousPointer = point;
      currentPointer = point;
      lastPointerMoveTime = eventTime;

      const localSpace = getLocalSpace();
      if (
        !segmentIntersectsExpandedRect(
          segment,
          localSpace.rect,
          brushRadius * Math.max(localSpace.scaleX, localSpace.scaleY)
        )
      ) {
        return;
      }

      pendingSegments.push(segment);
      if (pendingSegments.length > MAX_PENDING_SEGMENTS) {
        pendingSegments.splice(0, pendingSegments.length - MAX_PENDING_SEGMENTS);
      }
      ensureAnimation();
    };

    resetAllGlyphs();
    measureGeometry();

    const resizeObserver = new ResizeObserver(measureGeometry);
    resizeObserver.observe(wrapper);
    window.addEventListener("pointermove", handlePointerMove, { passive: true });
    void document.fonts?.ready.then(() => {
      if (!cancelled) measureGeometry();
    });

    return () => {
      cancelled = true;
      resizeObserver.disconnect();
      window.removeEventListener("pointermove", handlePointerMove);
      clearResetTimer();
      if (frameId !== null) cancelAnimationFrame(frameId);
    };
  }, [
    autoResetMs,
    characters,
    font.fontFamily,
    font.fontSize,
    font.fontWeight,
    font.letterSpacing,
    font.lineHeight,
    ghostColor,
    paintColor,
  ]);

  const textAlign = (font.textAlign as React.CSSProperties["textAlign"]) ?? "left";
  const alignItems =
    textAlign === "left" || textAlign === "start"
      ? "flex-start"
      : textAlign === "right" || textAlign === "end"
        ? "flex-end"
        : "center";

  return (
    <div
      style={{
        position: "relative",
        display: "flex",
        flexDirection: "column",
        alignItems,
        justifyContent: "center",
        width: "100%",
        height: "100%",
        ...style,
      }}
    >
      <p
        ref={wrapperRef}
        aria-label={text}
        style={{
          ...font,
          margin: 0,
          textAlign,
          whiteSpace: "pre-wrap",
          cursor: "crosshair",
          touchAction: "none",
          userSelect: "none",
          WebkitUserSelect: "none",
        }}
      >
        {characters.map((character, index) => {
          if (isSpace(character)) {
            return (
              <span
                key={`space-${index}`}
                style={{ display: "inline-block", whiteSpace: "pre" }}
              >
                {character === " " ? "\u00A0" : character}
              </span>
            );
          }
          return (
            <span
              key={`${character}-${index}`}
              ref={(element) => {
                glyphRefs.current[index] = element;
              }}
              style={{ position: "relative", display: "inline-block", whiteSpace: "pre" }}
            >
              <span
                ref={(element) => {
                  ghostRefs.current[index] = element;
                }}
                aria-hidden="true"
                style={{
                  display: "inline-block",
                  color: ghostColor,
                  opacity: 1,
                  whiteSpace: "pre",
                  willChange: "opacity",
                }}
              >
                {character}
              </span>
              <span
                ref={(element) => {
                  paintRefs.current[index] = element;
                }}
                aria-hidden="true"
                style={{
                  position: "absolute",
                  inset: 0,
                  display: "inline-block",
                  color: paintColor,
                  opacity: 0,
                  whiteSpace: "pre",
                  willChange: "opacity",
                }}
              >
                {character}
              </span>
            </span>
          );
        })}
      </p>
    </div>
  );
}

export default function PaintText({
  text = "找到\n下一部好片",
  font = {
    fontFamily: 'Inter, "PingFang SC", "Hiragino Sans GB", sans-serif',
    fontSize: "clamp(64px, 9vw, 120px)",
    fontWeight: 700,
    lineHeight: "1.05em",
    letterSpacing: "-0.04em",
    textAlign: "left",
  },
  paintColor = "var(--foreground)",
  ghostColor = "rgba(120, 120, 130, 0.28)",
  autoReset = true,
  autoResetDelay = 3,
  ...rest
}: Props) {
  return (
    <PaintTextBase
      text={text}
      font={font}
      paintColor={paintColor}
      ghostColor={ghostColor}
      autoReset={autoReset}
      autoResetDelay={autoResetDelay}
      {...rest}
    />
  );
}
