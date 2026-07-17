export class DecorPatternUtil {
  static draw(ctx: CanvasRenderingContext2D, w: number, h: number, accent: string, pattern: string): void {
    ctx.clearRect(0, 0, w, h);
    if (pattern === 'cloud') {
      DecorPatternUtil.drawCloud(ctx, w, h, accent);
    } else if (pattern === 'bamboo') {
      DecorPatternUtil.drawBamboo(ctx, w, h, accent);
    } else if (pattern === 'lantern') {
      DecorPatternUtil.drawLantern(ctx, w, h, accent);
    } else if (pattern === 'wave') {
      DecorPatternUtil.drawWave(ctx, w, h, accent);
    } else if (pattern === 'leaf') {
      DecorPatternUtil.drawLeaf(ctx, w, h, accent);
    } else if (pattern === 'heart') {
      DecorPatternUtil.drawHeart(ctx, w, h, accent);
    } else if (pattern === 'glitch') {
      DecorPatternUtil.drawGlitch(ctx, w, h, accent);
    } else if (pattern === 'mountain') {
      DecorPatternUtil.drawMountain(ctx, w, h, accent);
    } else if (pattern === 'grid') {
      DecorPatternUtil.drawGrid(ctx, w, h, accent);
    } else if (pattern === 'dot') {
      DecorPatternUtil.drawDot(ctx, w, h, accent);
    } else if (pattern === 'line') {
      DecorPatternUtil.drawLine(ctx, w, h, accent);
    } else if (pattern === 'vine') {
      DecorPatternUtil.drawVine(ctx, w, h, accent);
    } else if (pattern === 'snow') {
      DecorPatternUtil.drawSnow(ctx, w, h, accent);
    }
  }

  static drawCloud(ctx: CanvasRenderingContext2D, w: number, h: number, accent: string): void {
    ctx.globalAlpha = 0.22;
    ctx.fillStyle = accent;
    let positions: number[][] = [
      [0, h * 0.05], [w * 0.6, h * 0.02],
      [w * 0.1, h * 0.92], [w * 0.75, h * 0.88],
      [w * 0.4, h * 0.5]
    ];
    for (let i = 0; i < positions.length; i++) {
      let px: number = positions[i][0];
      let py: number = positions[i][1];
      let s: number = (0.8 + i * 0.3) * 20;
      ctx.beginPath();
      ctx.arc(px, py, s, 0, Math.PI * 2);
      ctx.fill();
      ctx.beginPath();
      ctx.arc(px - s * 0.8, py + s * 0.3, s * 0.7, 0, Math.PI * 2);
      ctx.fill();
      ctx.beginPath();
      ctx.arc(px + s * 0.9, py + s * 0.2, s * 0.75, 0, Math.PI * 2);
      ctx.fill();
      ctx.beginPath();
      ctx.arc(px - s * 0.3, py - s * 0.5, s * 0.6, 0, Math.PI * 2);
      ctx.fill();
      ctx.beginPath();
      ctx.arc(px + s * 0.4, py - s * 0.4, s * 0.65, 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.globalAlpha = 0.15;
    ctx.strokeStyle = accent;
    ctx.lineWidth = 1;
    for (let i = 0; i < 6; i++) {
      let cx: number = Math.floor(w * (0.1 + i * 0.16));
      ctx.beginPath();
      ctx.arc(cx, h * 0.96, 3, 0, Math.PI * 2);
      ctx.stroke();
      ctx.beginPath();
      ctx.arc(cx + 6, h * 0.96, 2, 0, Math.PI * 2);
      ctx.stroke();
    }
    ctx.globalAlpha = 1;
  }

  static drawBamboo(ctx: CanvasRenderingContext2D, w: number, h: number, accent: string): void {
    ctx.globalAlpha = 0.28;
    ctx.strokeStyle = accent;
    ctx.lineWidth = 3;
    let stalks: number[][] = [
      [w * 0.85, h * 0.0, h * 0.55],
      [w * 0.9, h * 0.15, h * 0.7],
      [w * 0.78, h * 0.1, h * 0.65]
    ];
    for (let i = 0; i < stalks.length; i++) {
      let sx: number = stalks[i][0];
      let sy: number = stalks[i][1];
      let ey: number = stalks[i][2];
      ctx.beginPath();
      ctx.moveTo(sx, sy);
      ctx.lineTo(sx, ey);
      ctx.stroke();
      let segments: number = Math.floor((ey - sy) / 50);
      for (let j = 1; j <= segments; j++) {
        let ny: number = sy + j * 50;
        ctx.lineWidth = 1;
        ctx.beginPath();
        ctx.moveTo(sx - 4, ny);
        ctx.lineTo(sx + 4, ny);
        ctx.stroke();
      }
      ctx.lineWidth = 3;
    }
    ctx.globalAlpha = 0.22;
    ctx.fillStyle = accent;
    for (let i = 0; i < 8; i++) {
      let lx: number = w * 0.72 + Math.floor(i % 3) * 20;
      let ly: number = h * 0.08 + Math.floor(i * 45);
      DecorPatternUtil.drawLeafShape(ctx, lx, ly, i % 2 === 0 ? -0.4 : 0.4);
    }
    ctx.globalAlpha = 0.12;
    ctx.fillStyle = accent;
    for (let i = 0; i < 5; i++) {
      let cx: number = w * 0.05 + i * w * 0.18;
      let cy: number = h * 0.9;
      ctx.beginPath();
      ctx.arc(cx, cy, 15, 0, Math.PI * 2);
      ctx.fill();
      ctx.beginPath();
      ctx.arc(cx + 8, cy - 5, 10, 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.globalAlpha = 1;
  }

  static drawLeafShape(ctx: CanvasRenderingContext2D, x: number, y: number, angle: number): void {
    ctx.save();
    ctx.translate(x, y);
    ctx.rotate(angle);
    ctx.beginPath();
    ctx.moveTo(0, 0);
    ctx.quadraticCurveTo(12, -8, 30, 0);
    ctx.quadraticCurveTo(12, 8, 0, 0);
    ctx.fill();
    ctx.restore();
  }

  static drawLantern(ctx: CanvasRenderingContext2D, w: number, h: number, accent: string): void {
    ctx.globalAlpha = 0.22;
    ctx.fillStyle = accent;
    DecorPatternUtil.drawLanternShape(ctx, w * 0.08, h * 0.04, 18);
    DecorPatternUtil.drawLanternShape(ctx, w * 0.88, h * 0.06, 22);
    DecorPatternUtil.drawLanternShape(ctx, w * 0.82, h * 0.82, 16);
    ctx.globalAlpha = 0.15;
    ctx.strokeStyle = accent;
    ctx.lineWidth = 1;
    let ribbonPositions: number[][] = [
      [w * 0.1, h * 0.15], [w * 0.9, h * 0.18],
      [w * 0.05, h * 0.5], [w * 0.95, h * 0.45]
    ];
    for (let i = 0; i < ribbonPositions.length; i++) {
      let rx: number = ribbonPositions[i][0];
      let ry: number = ribbonPositions[i][1];
      ctx.beginPath();
      ctx.moveTo(rx, ry);
      ctx.quadraticCurveTo(rx + 5, ry + 30, rx - 3, ry + 60);
      ctx.stroke();
    }
    ctx.globalAlpha = 0.18;
    ctx.fillStyle = accent;
    let coinY: number = h * 0.92;
    for (let i = 0; i < 4; i++) {
      let cx: number = w * 0.15 + i * w * 0.22;
      ctx.beginPath();
      ctx.arc(cx, coinY, 8, 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.globalAlpha = 0.12;
    ctx.strokeStyle = accent;
    ctx.lineWidth = 2;
    ctx.beginPath();
    ctx.moveTo(0, h * 0.85);
    ctx.quadraticCurveTo(w * 0.5, h * 0.82, w, h * 0.86);
    ctx.stroke();
    ctx.globalAlpha = 1;
  }

  static drawLanternShape(ctx: CanvasRenderingContext2D, x: number, y: number, size: number): void {
    ctx.beginPath();
    ctx.moveTo(x, y - size * 0.3);
    ctx.lineTo(x + size * 0.15, y - size * 0.15);
    ctx.lineTo(x + size * 0.15, y + size * 0.15);
    ctx.lineTo(x - size * 0.15, y + size * 0.15);
    ctx.lineTo(x - size * 0.15, y - size * 0.15);
    ctx.closePath();
    ctx.fill();
    ctx.beginPath();
    ctx.ellipse(x, y + size * 0.6, size * 0.5, size * 0.7, 0, 0, Math.PI * 2);
    ctx.fill();
    ctx.globalAlpha = 0.12;
    ctx.strokeStyle = '#8b4513';
    ctx.lineWidth = 1;
    ctx.beginPath();
    ctx.moveTo(x, y - size * 0.6);
    ctx.lineTo(x, y - size * 0.3);
    ctx.stroke();
    ctx.beginPath();
    ctx.moveTo(x - size * 0.2, y + size * 1.3);
    ctx.lineTo(x + size * 0.2, y + size * 1.3);
    ctx.stroke();
  }

  static drawWave(ctx: CanvasRenderingContext2D, w: number, h: number, accent: string): void {
    ctx.globalAlpha = 0.18;
    ctx.strokeStyle = accent;
    ctx.lineWidth = 2;
    for (let row = 0; row < 5; row++) {
      let yBase: number = h * (0.15 + row * 0.2);
      ctx.beginPath();
      ctx.moveTo(0, yBase);
      for (let x = 0; x <= w; x += 4) {
        let y: number = yBase + Math.sin(x * 0.03 + row * 1.2) * 12;
        ctx.lineTo(x, y);
      }
      ctx.stroke();
    }
    ctx.globalAlpha = 0.12;
    ctx.fillStyle = accent;
    for (let i = 0; i < 8; i++) {
      ctx.beginPath();
      ctx.arc(w * (0.1 + i * 0.1), h * 0.92, 4, 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.globalAlpha = 1;
  }

  static drawLeaf(ctx: CanvasRenderingContext2D, w: number, h: number, accent: string): void {
    ctx.globalAlpha = 0.22;
    ctx.fillStyle = accent;
    for (let i = 0; i < 12; i++) {
      let lx: number = Math.floor(w * (0.05 + (i % 4) * 0.25));
      let ly: number = Math.floor(h * (0.1 + Math.floor(i / 4) * 0.35));
      let angle: number = (i % 2 === 0 ? -1 : 1) * 0.3;
      DecorPatternUtil.drawLeafShape(ctx, lx, ly, angle);
    }
    ctx.globalAlpha = 0.15;
    ctx.strokeStyle = accent;
    ctx.lineWidth = 1;
    for (let i = 0; i < 4; i++) {
      let cx: number = w * (0.2 + i * 0.2);
      ctx.beginPath();
      ctx.arc(cx, h * 0.95, 6, 0, Math.PI * 2);
      ctx.stroke();
      ctx.beginPath();
      ctx.moveTo(cx, h * 0.95);
      ctx.lineTo(cx, h * 0.88);
      ctx.stroke();
    }
    ctx.globalAlpha = 1;
  }

  static drawHeart(ctx: CanvasRenderingContext2D, w: number, h: number, accent: string): void {
    ctx.globalAlpha = 0.22;
    ctx.fillStyle = accent;
    let positions: number[][] = [
      [w * 0.1, h * 0.08], [w * 0.85, h * 0.05],
      [w * 0.05, h * 0.7], [w * 0.9, h * 0.75],
      [w * 0.5, h * 0.45]
    ];
    for (let i = 0; i < positions.length; i++) {
      let hx: number = positions[i][0];
      let hy: number = positions[i][1];
      let s: number = 8 + i * 2;
      ctx.beginPath();
      ctx.moveTo(hx, hy + s * 0.3);
      ctx.bezierCurveTo(hx, hy - s * 0.3, hx - s, hy - s * 0.3, hx - s, hy + s * 0.1);
      ctx.bezierCurveTo(hx - s, hy + s * 0.6, hx, hy + s, hx, hy + s * 1.2);
      ctx.bezierCurveTo(hx, hy + s, hx + s, hy + s * 0.6, hx + s, hy + s * 0.1);
      ctx.bezierCurveTo(hx + s, hy - s * 0.3, hx, hy - s * 0.3, hx, hy + s * 0.3);
      ctx.fill();
    }
    ctx.globalAlpha = 0.12;
    for (let i = 0; i < 20; i++) {
      ctx.beginPath();
      ctx.arc(Math.floor(w * 0.1 + (i % 5) * w * 0.18), Math.floor(h * 0.85 + Math.floor(i / 5) * 15), 2, 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.globalAlpha = 1;
  }

  static drawGlitch(ctx: CanvasRenderingContext2D, w: number, h: number, accent: string): void {
    ctx.globalAlpha = 0.28;
    ctx.fillStyle = accent;
    let bars: number[][] = [
      [0, h * 0.12, w * 0.4, 3],
      [w * 0.6, h * 0.28, w * 0.4, 2],
      [0, h * 0.55, w * 0.3, 4],
      [w * 0.7, h * 0.72, w * 0.3, 2],
      [0, h * 0.9, w * 0.5, 3]
    ];
    for (let i = 0; i < bars.length; i++) {
      ctx.fillRect(bars[i][0], bars[i][1], bars[i][2], bars[i][3]);
    }
    ctx.globalAlpha = 0.15;
    ctx.strokeStyle = '#00ffff';
    ctx.lineWidth = 1;
    for (let i = 0; i < 6; i++) {
      let y: number = h * (0.2 + i * 0.12);
      ctx.beginPath();
      ctx.moveTo(w * 0.7, y);
      ctx.lineTo(w, y);
      ctx.stroke();
    }
    ctx.globalAlpha = 1;
  }

  static drawMountain(ctx: CanvasRenderingContext2D, w: number, h: number, accent: string): void {
    ctx.globalAlpha = 0.22;
    ctx.fillStyle = accent;
    ctx.beginPath();
    ctx.moveTo(0, h * 0.88);
    ctx.lineTo(w * 0.15, h * 0.65);
    ctx.lineTo(w * 0.3, h * 0.8);
    ctx.lineTo(w * 0.5, h * 0.55);
    ctx.lineTo(w * 0.7, h * 0.75);
    ctx.lineTo(w * 0.85, h * 0.6);
    ctx.lineTo(w, h * 0.82);
    ctx.lineTo(w, h);
    ctx.lineTo(0, h);
    ctx.closePath();
    ctx.fill();
    ctx.globalAlpha = 0.15;
    ctx.beginPath();
    ctx.moveTo(0, h * 0.92);
    ctx.lineTo(w * 0.25, h * 0.78);
    ctx.lineTo(w * 0.45, h * 0.88);
    ctx.lineTo(w * 0.65, h * 0.72);
    ctx.lineTo(w * 0.9, h * 0.85);
    ctx.lineTo(w, h * 0.9);
    ctx.lineTo(w, h);
    ctx.lineTo(0, h);
    ctx.closePath();
    ctx.fill();
    ctx.globalAlpha = 0.18;
    ctx.strokeStyle = accent;
    ctx.lineWidth = 1;
    ctx.beginPath();
    ctx.moveTo(w * 0.5, h * 0.55);
    ctx.lineTo(w * 0.5, h * 0.45);
    ctx.stroke();
    ctx.beginPath();
    ctx.arc(w * 0.5, h * 0.42, 4, 0, Math.PI * 2);
    ctx.stroke();
    ctx.globalAlpha = 1;
  }

  static drawGrid(ctx: CanvasRenderingContext2D, w: number, h: number, accent: string): void {
    ctx.globalAlpha = 0.18;
    ctx.strokeStyle = accent;
    ctx.lineWidth = 1;
    let spacing: number = 30;
    for (let x = 0; x <= w; x += spacing) {
      ctx.beginPath();
      ctx.moveTo(x, 0);
      ctx.lineTo(x, h);
      ctx.stroke();
    }
    for (let y = 0; y <= h; y += spacing) {
      ctx.beginPath();
      ctx.moveTo(0, y);
      ctx.lineTo(w, y);
      ctx.stroke();
    }
    ctx.globalAlpha = 0.35;
    ctx.fillStyle = accent;
    let crosses: number[][] = [
      [w * 0.15, h * 0.2], [w * 0.8, h * 0.15],
      [w * 0.5, h * 0.5], [w * 0.2, h * 0.8],
      [w * 0.85, h * 0.75]
    ];
    for (let i = 0; i < crosses.length; i++) {
      let cx: number = crosses[i][0];
      let cy: number = crosses[i][1];
      ctx.beginPath();
      ctx.moveTo(cx - 6, cy);
      ctx.lineTo(cx + 6, cy);
      ctx.stroke();
      ctx.beginPath();
      ctx.moveTo(cx, cy - 6);
      ctx.lineTo(cx, cy + 6);
      ctx.stroke();
    }
    ctx.globalAlpha = 1;
  }

  static drawDot(ctx: CanvasRenderingContext2D, w: number, h: number, accent: string): void {
    ctx.globalAlpha = 0.18;
    ctx.fillStyle = accent;
    let spacing: number = 24;
    for (let x = spacing; x < w; x += spacing) {
      for (let y = spacing; y < h; y += spacing) {
        ctx.beginPath();
        ctx.arc(x, y, 1.5, 0, Math.PI * 2);
        ctx.fill();
      }
    }
    ctx.globalAlpha = 0.28;
    let bigDots: number[][] = [
      [w * 0.1, h * 0.1], [w * 0.9, h * 0.08],
      [w * 0.05, h * 0.9], [w * 0.92, h * 0.88]
    ];
    for (let i = 0; i < bigDots.length; i++) {
      ctx.beginPath();
      ctx.arc(bigDots[i][0], bigDots[i][1], 6, 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.globalAlpha = 1;
  }

  static drawLine(ctx: CanvasRenderingContext2D, w: number, h: number, accent: string): void {
    ctx.globalAlpha = 0.22;
    ctx.strokeStyle = accent;
    ctx.lineWidth = 2;
    let lines: number[][] = [
      [0, h * 0.2, w * 0.6, h * 0.15],
      [w * 0.4, h * 0.4, w, h * 0.35],
      [0, h * 0.6, w * 0.5, h * 0.58],
      [w * 0.5, h * 0.8, w, h * 0.75]
    ];
    for (let i = 0; i < lines.length; i++) {
      ctx.beginPath();
      ctx.moveTo(lines[i][0], lines[i][1]);
      ctx.lineTo(lines[i][2], lines[i][3]);
      ctx.stroke();
    }
    ctx.globalAlpha = 0.15;
    ctx.strokeStyle = '#00ffff';
    ctx.lineWidth = 1;
    let glowLines: number[][] = [
      [w * 0.3, 0, w * 0.35, h * 0.5],
      [w * 0.7, h * 0.5, w * 0.65, h]
    ];
    for (let i = 0; i < glowLines.length; i++) {
      ctx.beginPath();
      ctx.moveTo(glowLines[i][0], glowLines[i][1]);
      ctx.lineTo(glowLines[i][2], glowLines[i][3]);
      ctx.stroke();
    }
    ctx.globalAlpha = 1;
  }

  static drawVine(ctx: CanvasRenderingContext2D, w: number, h: number, accent: string): void {
    ctx.globalAlpha = 0.22;
    ctx.strokeStyle = accent;
    ctx.lineWidth = 2;
    ctx.beginPath();
    ctx.moveTo(w * 0.95, 0);
    let vy: number = 0;
    let vx: number = w * 0.95;
    while (vy < h) {
      vy += 20;
      vx += (vy % 40 === 0 ? -8 : 8);
      ctx.lineTo(vx, vy);
    }
    ctx.stroke();
    ctx.globalAlpha = 0.18;
    ctx.fillStyle = accent;
    for (let i = 0; i < 10; i++) {
      let fx: number = vx + (i % 2 === 0 ? 10 : -10);
      let fy: number = h * (0.1 + i * 0.08);
      DecorPatternUtil.drawLeafShape(ctx, fx, fy, i % 2 === 0 ? 0.3 : -0.3);
    }
    ctx.globalAlpha = 0.15;
    ctx.fillStyle = accent;
    for (let i = 0; i < 6; i++) {
      let bx: number = w * 0.05 + i * w * 0.16;
      let by: number = h * 0.92;
      ctx.beginPath();
      ctx.arc(bx, by, 5, 0, Math.PI * 2);
      ctx.fill();
      ctx.beginPath();
      ctx.arc(bx + 3, by - 4, 3, 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.globalAlpha = 1;
  }

  static drawSnow(ctx: CanvasRenderingContext2D, w: number, h: number, accent: string): void {
    ctx.globalAlpha = 0.18;
    ctx.strokeStyle = accent;
    ctx.lineWidth = 1;
    let flakes: number[][] = [
      [w * 0.1, h * 0.08], [w * 0.3, h * 0.15], [w * 0.6, h * 0.05],
      [w * 0.85, h * 0.12], [w * 0.15, h * 0.35], [w * 0.5, h * 0.3],
      [w * 0.8, h * 0.4], [w * 0.25, h * 0.6], [w * 0.7, h * 0.55],
      [w * 0.4, h * 0.75], [w * 0.9, h * 0.7], [w * 0.1, h * 0.85],
      [w * 0.6, h * 0.9]
    ];
    for (let i = 0; i < flakes.length; i++) {
      let fx: number = flakes[i][0];
      let fy: number = flakes[i][1];
      let s: number = 6 + (i % 3) * 3;
      for (let a = 0; a < 3; a++) {
        let angle: number = a * Math.PI / 3;
        ctx.beginPath();
        ctx.moveTo(fx + Math.cos(angle) * -s, fy + Math.sin(angle) * -s);
        ctx.lineTo(fx + Math.cos(angle) * s, fy + Math.sin(angle) * s);
        ctx.stroke();
      }
    }
    ctx.globalAlpha = 0.12;
    ctx.fillStyle = accent;
    for (let i = 0; i < 8; i++) {
      ctx.beginPath();
      ctx.arc(Math.floor(w * (0.1 + i * 0.1)), Math.floor(h * 0.95), 3, 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.globalAlpha = 1;
  }
}
