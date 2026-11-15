import { useEffect, useRef } from "react";

export default function DotWave() {
  const canvasRef = useRef<HTMLCanvasElement>(null);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;

    const ctx = canvas.getContext("2d");
    if (!ctx) return;

    let animationId: number;
    let dpr = window.devicePixelRatio || 1;

    const resize = () => {
      dpr = window.devicePixelRatio || 1;
      const rect = canvas.getBoundingClientRect();
      canvas.width = rect.width * dpr;
      canvas.height = rect.height * dpr;
      ctx.scale(dpr, dpr);
    };

    resize();
    window.addEventListener("resize", resize);

    const spacing = 28;
    const baseRadius = 1.2;
    const waveAmplitude = 0.8;
    const waveSpeed = 0.006;
    const baseAlpha = 0.12;
    const accentAlpha = 0.3;

    let time = 0;

    const draw = () => {
      const w = canvas.width / dpr;
      const h = canvas.height / dpr;

      ctx.clearRect(0, 0, w, h);

      const cols = Math.ceil(w / spacing) + 1;
      const rows = Math.ceil(h / spacing) + 1;

      const centerX = w / 2;
      const centerY = h / 2;
      const maxDist = Math.sqrt(centerX * centerX + centerY * centerY);

      for (let row = 0; row < rows; row++) {
        for (let col = 0; col < cols; col++) {
          const x = col * spacing;
          const y = row * spacing;

          const dx = x - centerX;
          const dy = y - centerY;
          const dist = Math.sqrt(dx * dx + dy * dy);
          const normDist = dist / maxDist;

          // Two overlapping waves for organic motion
          const wave1 = Math.sin(dist * 0.04 - time * 1.0);
          const wave2 = Math.sin(dist * 0.025 + time * 0.7 + 1.5);
          const combined = (wave1 + wave2) * 0.5;

          const radius = baseRadius + combined * waveAmplitude;
          const alpha =
            baseAlpha + combined * (accentAlpha - baseAlpha) * 0.5;

          // Fade edges
          const edgeFade = 1 - Math.pow(normDist, 2.5);

          // Mix orange accent into wave peaks
          const orangeMix = Math.max(0, combined) * 0.4 * edgeFade;

          const r = Math.round(255 * (1 - orangeMix) + 255 * orangeMix);
          const g = Math.round(255 * (1 - orangeMix) + 107 * orangeMix);
          const b = Math.round(255 * (1 - orangeMix) + 53 * orangeMix);

          ctx.beginPath();
          ctx.arc(x, y, Math.max(0.5, radius), 0, Math.PI * 2);
          ctx.fillStyle = `rgba(${r}, ${g}, ${b}, ${Math.max(0, alpha * edgeFade)})`;
          ctx.fill();
        }
      }

      time += waveSpeed;
    };

    let lastFrame = 0;
    const loop = (timestamp: number) => {
      if (timestamp - lastFrame >= 33) {
        lastFrame = timestamp;
        draw();
      }
      animationId = requestAnimationFrame(loop);
    };
    animationId = requestAnimationFrame(loop);

    return () => {
      window.removeEventListener("resize", resize);
      cancelAnimationFrame(animationId);
    };
  }, []);

  return (
    <canvas
      ref={canvasRef}
      style={{
        position: "absolute",
        inset: 0,
        width: "100%",
        height: "100%",
        pointerEvents: "none",
      }}
    />
  );
}
