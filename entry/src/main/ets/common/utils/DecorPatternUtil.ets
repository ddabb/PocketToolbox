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
    } else if (pattern === 'seal') {
      DecorPatternUtil.drawSeal(ctx, w, h, accent);
    }
  }

  static drawCloud(ctx: CanvasRenderingContext2D, w: number, h: number, accent: string): void {
    ctx.globalAlpha = 0.08;
    ctx.fillStyle = accent;
    for (let i = 0; i < 30; i++) {
      let cx: number = Math.floor((i * 37 + 13) % w);
      let cy: number = Math.floor((i * 23 + 7) % h);
      ctx.beginPath();
      ctx.arc(cx, cy, 1, 0, Math.PI * 2);
      ctx.fill();
    }
    let positions: number[][] = [
      [w * 0.12, h * 0.08, 28], [w * 0.65, h * 0.05, 32],
      [w * 0.4, h * 0.22, 20], [w * 0.85, h * 0.18, 24],
      [w * 0.08, h * 0.65, 22], [w * 0.55, h * 0.55, 26],
      [w * 0.78, h * 0.62, 18], [w * 0.3, h * 0.82, 24],
      [w * 0.9, h * 0.85, 20]
    ];
    for (let i = 0; i < positions.length; i++) {
      let px: number = positions[i][0];
      let py: number = positions[i][1];
      let s: number = positions[i][2];
      ctx.globalAlpha = 0.14;
      ctx.fillStyle = accent;
      DecorPatternUtil.drawCloudShape(ctx, px, py, s);
      ctx.globalAlpha = 0.06;
      DecorPatternUtil.drawCloudShape(ctx, px + s * 0.3, py - s * 0.2, s * 0.7);
    }
    ctx.globalAlpha = 0.06;
    ctx.strokeStyle = accent;
    ctx.lineWidth = 1;
    for (let i = 0; i < 4; i++) {
      let yBase: number = h * (0.92 + i * 0.02);
      ctx.beginPath();
      ctx.moveTo(0, yBase);
      for (let x = 0; x <= w; x += 3) {
        let y: number = yBase + Math.sin(x * 0.04 + i * 0.8) * 3;
        ctx.lineTo(x, y);
      }
      ctx.stroke();
    }
    ctx.globalAlpha = 0.1;
    ctx.fillStyle = accent;
    for (let i = 0; i < 8; i++) {
      let bx: number = w * (0.1 + i * 0.1);
      let by: number = h * 0.95 + Math.sin(i * 1.2) * 4;
      ctx.beginPath();
      ctx.arc(bx, by, 2, 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.globalAlpha = 1;
  }

  static drawCloudShape(ctx: CanvasRenderingContext2D, x: number, y: number, s: number): void {
    ctx.beginPath();
    ctx.arc(x, y, s * 0.5, 0, Math.PI * 2);
    ctx.fill();
    ctx.beginPath();
    ctx.arc(x - s * 0.45, y + s * 0.15, s * 0.38, 0, Math.PI * 2);
    ctx.fill();
    ctx.beginPath();
    ctx.arc(x + s * 0.5, y + s * 0.1, s * 0.42, 0, Math.PI * 2);
    ctx.fill();
    ctx.beginPath();
    ctx.arc(x - s * 0.15, y - s * 0.3, s * 0.35, 0, Math.PI * 2);
    ctx.fill();
    ctx.beginPath();
    ctx.arc(x + s * 0.25, y - s * 0.25, s * 0.38, 0, Math.PI * 2);
    ctx.fill();
    ctx.beginPath();
    ctx.arc(x - s * 0.6, y + s * 0.3, s * 0.25, 0, Math.PI * 2);
    ctx.fill();
    ctx.beginPath();
    ctx.arc(x + s * 0.65, y + s * 0.25, s * 0.28, 0, Math.PI * 2);
    ctx.fill();
  }

  static drawBamboo(ctx: CanvasRenderingContext2D, w: number, h: number, accent: string): void {
    ctx.globalAlpha = 0.05;
    ctx.fillStyle = accent;
    for (let i = 0; i < 20; i++) {
      let mx: number = Math.floor((i * 53 + 11) % w);
      let my: number = Math.floor((i * 31 + 17) % h);
      ctx.beginPath();
      ctx.ellipse(mx, my, 2, 1, i * 0.5, 0, Math.PI * 2);
      ctx.fill();
    }
    let stalks: number[][] = [
      [w * 0.82, h * 0.0, h * 0.55, 4],
      [w * 0.88, h * 0.12, h * 0.72, 5],
      [w * 0.76, h * 0.08, h * 0.62, 3],
      [w * 0.92, h * 0.25, h * 0.85, 3],
      [w * 0.73, h * 0.3, h * 0.9, 3]
    ];
    for (let i = 0; i < stalks.length; i++) {
      let sx: number = stalks[i][0];
      let sy: number = stalks[i][1];
      let ey: number = stalks[i][2];
      let lw: number = stalks[i][3];
      ctx.globalAlpha = 0.2;
      ctx.strokeStyle = accent;
      ctx.lineWidth = lw;
      ctx.beginPath();
      ctx.moveTo(sx, sy);
      ctx.lineTo(sx, ey);
      ctx.stroke();
      ctx.lineWidth = lw - 1;
      ctx.globalAlpha = 0.1;
      ctx.beginPath();
      ctx.moveTo(sx + 2, sy);
      ctx.lineTo(sx + 2, ey);
      ctx.stroke();
      let segments: number = Math.floor((ey - sy) / 45);
      for (let j = 1; j <= segments; j++) {
        let ny: number = sy + j * 45;
        ctx.globalAlpha = 0.25;
        ctx.strokeStyle = accent;
        ctx.lineWidth = 1;
        ctx.beginPath();
        ctx.moveTo(sx - 5, ny);
        ctx.lineTo(sx + 5, ny);
        ctx.stroke();
        if (j % 2 === 0 && ny < ey - 30) {
          ctx.globalAlpha = 0.16;
          ctx.fillStyle = accent;
          DecorPatternUtil.drawLeafShape(ctx, sx - 8, ny + 5, -0.5);
          DecorPatternUtil.drawLeafShape(ctx, sx + 8, ny + 5, 0.5);
        }
      }
    }
    ctx.globalAlpha = 0.18;
    ctx.fillStyle = accent;
    for (let i = 0; i < 10; i++) {
      let lx: number = w * 0.6 + (i % 3) * 25;
      let ly: number = h * 0.05 + i * 42;
      DecorPatternUtil.drawLeafShape(ctx, lx, ly, i % 2 === 0 ? -0.5 : 0.5);
    }
    ctx.globalAlpha = 0.06;
    ctx.fillStyle = accent;
    for (let i = 0; i < 6; i++) {
      let cx: number = w * 0.05 + i * w * 0.16;
      let cy: number = h * 0.92;
      ctx.beginPath();
      ctx.arc(cx, cy, 12, 0, Math.PI * 2);
      ctx.fill();
      ctx.beginPath();
      ctx.arc(cx + 6, cy - 6, 8, 0, Math.PI * 2);
      ctx.fill();
      ctx.beginPath();
      ctx.arc(cx - 4, cy - 8, 6, 0, Math.PI * 2);
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
    ctx.quadraticCurveTo(14, -10, 36, 0);
    ctx.quadraticCurveTo(14, 10, 0, 0);
    ctx.fill();
    ctx.globalAlpha = Math.floor(ctx.globalAlpha * 0.5 * 100) / 100;
    ctx.strokeStyle = ctx.fillStyle as string;
    ctx.lineWidth = 0.5;
    ctx.beginPath();
    ctx.moveTo(2, 0);
    ctx.lineTo(30, 0);
    ctx.stroke();
    ctx.restore();
  }

  static drawLantern(ctx: CanvasRenderingContext2D, w: number, h: number, accent: string): void {
    ctx.globalAlpha = 0.06;
    ctx.fillStyle = accent;
    for (let i = 0; i < 25; i++) {
      let px: number = Math.floor((i * 41 + 7) % w);
      let py: number = Math.floor((i * 29 + 13) % h);
      ctx.beginPath();
      ctx.arc(px, py, 1.5, 0, Math.PI * 2);
      ctx.fill();
    }
    let lanternData: number[][] = [
      [w * 0.08, h * 0.04, 20],
      [w * 0.88, h * 0.06, 24],
      [w * 0.5, h * 0.02, 18],
      [w * 0.82, h * 0.82, 16],
      [w * 0.15, h * 0.78, 14]
    ];
    for (let i = 0; i < lanternData.length; i++) {
      ctx.globalAlpha = 0.2;
      ctx.fillStyle = accent;
      DecorPatternUtil.drawLanternShape(ctx, lanternData[i][0], lanternData[i][1], lanternData[i][2]);
    }
    ctx.globalAlpha = 0.12;
    ctx.strokeStyle = accent;
    ctx.lineWidth = 1;
    let ribbonPositions: number[][] = [
      [w * 0.1, h * 0.15], [w * 0.9, h * 0.18],
      [w * 0.05, h * 0.5], [w * 0.95, h * 0.45],
      [w * 0.5, h * 0.1]
    ];
    for (let i = 0; i < ribbonPositions.length; i++) {
      let rx: number = ribbonPositions[i][0];
      let ry: number = ribbonPositions[i][1];
      ctx.beginPath();
      ctx.moveTo(rx, ry);
      ctx.quadraticCurveTo(rx + 8, ry + 20, rx - 2, ry + 50);
      ctx.stroke();
      ctx.beginPath();
      ctx.moveTo(rx - 3, ry + 50);
      ctx.quadraticCurveTo(rx - 8, ry + 60, rx + 2, ry + 75);
      ctx.stroke();
    }
    ctx.globalAlpha = 0.15;
    ctx.fillStyle = accent;
    let coinY: number = h * 0.92;
    for (let i = 0; i < 5; i++) {
      let cx: number = w * 0.1 + i * w * 0.2;
      ctx.beginPath();
      ctx.arc(cx, coinY, 8, 0, Math.PI * 2);
      ctx.fill();
      ctx.globalAlpha = 0.08;
      ctx.beginPath();
      ctx.arc(cx, coinY, 4, 0, Math.PI * 2);
      ctx.fill();
      ctx.globalAlpha = 0.15;
    }
    ctx.globalAlpha = 0.1;
    ctx.strokeStyle = accent;
    ctx.lineWidth = 1.5;
    ctx.beginPath();
    ctx.moveTo(0, h * 0.85);
    ctx.quadraticCurveTo(w * 0.3, h * 0.82, w * 0.5, h * 0.84);
    ctx.quadraticCurveTo(w * 0.7, h * 0.86, w, h * 0.83);
    ctx.stroke();
    ctx.globalAlpha = 1;
  }

  static drawLanternShape(ctx: CanvasRenderingContext2D, x: number, y: number, size: number): void {
    ctx.beginPath();
    ctx.moveTo(x, y - size * 0.3);
    ctx.lineTo(x + size * 0.18, y - size * 0.15);
    ctx.lineTo(x + size * 0.18, y + size * 0.15);
    ctx.lineTo(x - size * 0.18, y + size * 0.15);
    ctx.lineTo(x - size * 0.18, y - size * 0.15);
    ctx.closePath();
    ctx.fill();
    ctx.beginPath();
    ctx.ellipse(x, y + size * 0.6, size * 0.5, size * 0.7, 0, 0, Math.PI * 2);
    ctx.fill();
    ctx.globalAlpha = 0.1;
    ctx.beginPath();
    ctx.ellipse(x, y + size * 0.6, size * 0.3, size * 0.5, 0, 0, Math.PI * 2);
    ctx.fill();
    ctx.globalAlpha = 0.12;
    ctx.strokeStyle = '#8b4513';
    ctx.lineWidth = 1;
    ctx.beginPath();
    ctx.moveTo(x, y - size * 0.6);
    ctx.lineTo(x, y - size * 0.3);
    ctx.stroke();
    ctx.beginPath();
    ctx.moveTo(x - size * 0.25, y + size * 1.3);
    ctx.lineTo(x + size * 0.25, y + size * 1.3);
    ctx.stroke();
  }

  static drawWave(ctx: CanvasRenderingContext2D, w: number, h: number, accent: string): void {
    ctx.globalAlpha = 0.05;
    ctx.fillStyle = accent;
    for (let i = 0; i < 40; i++) {
      let px: number = Math.floor((i * 31 + 19) % w);
      let py: number = Math.floor((i * 23 + 11) % h);
      ctx.beginPath();
      ctx.arc(px, py, 1, 0, Math.PI * 2);
      ctx.fill();
    }
    for (let row = 0; row < 7; row++) {
      let yBase: number = h * (0.1 + row * 0.13);
      let alpha: number = 0.06 + row * 0.02;
      ctx.globalAlpha = alpha;
      ctx.strokeStyle = accent;
      ctx.lineWidth = 1.5;
      ctx.beginPath();
      ctx.moveTo(0, yBase);
      for (let x = 0; x <= w; x += 3) {
        let y: number = yBase + Math.sin(x * 0.025 + row * 1.5) * (8 + row * 3);
        ctx.lineTo(x, y);
      }
      ctx.stroke();
    }
    ctx.globalAlpha = 0.05;
    ctx.fillStyle = accent;
    for (let row = 0; row < 3; row++) {
      let yFill: number = h * (0.85 + row * 0.05);
      ctx.beginPath();
      ctx.moveTo(0, yFill);
      for (let x = 0; x <= w; x += 3) {
        let y: number = yFill + Math.sin(x * 0.03 + row * 2) * 5;
        ctx.lineTo(x, y);
      }
      ctx.lineTo(w, h);
      ctx.lineTo(0, h);
      ctx.closePath();
      ctx.fill();
    }
    ctx.globalAlpha = 0.1;
    ctx.fillStyle = accent;
    for (let i = 0; i < 10; i++) {
      let bx: number = w * (0.08 + i * 0.09);
      let by: number = h * 0.94 + Math.sin(i * 0.9) * 3;
      ctx.beginPath();
      ctx.arc(bx, by, 3, 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.globalAlpha = 1;
  }

  static drawLeaf(ctx: CanvasRenderingContext2D, w: number, h: number, accent: string): void {
    ctx.globalAlpha = 0.04;
    ctx.fillStyle = accent;
    for (let i = 0; i < 30; i++) {
      let px: number = Math.floor((i * 43 + 17) % w);
      let py: number = Math.floor((i * 27 + 13) % h);
      ctx.beginPath();
      ctx.arc(px, py, 1.2, 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.globalAlpha = 0.18;
    ctx.fillStyle = accent;
    let leafPositions: number[][] = [
      [w * 0.08, h * 0.1, -0.4, 1.0], [w * 0.3, h * 0.08, 0.35, 0.9],
      [w * 0.55, h * 0.12, -0.3, 1.1], [w * 0.8, h * 0.06, 0.5, 0.8],
      [w * 0.15, h * 0.35, 0.3, 1.0], [w * 0.45, h * 0.32, -0.5, 1.1],
      [w * 0.72, h * 0.38, 0.4, 0.9], [w * 0.9, h * 0.3, -0.35, 1.0],
      [w * 0.05, h * 0.6, -0.4, 1.0], [w * 0.35, h * 0.58, 0.45, 0.8],
      [w * 0.6, h * 0.65, -0.3, 1.1], [w * 0.85, h * 0.55, 0.5, 0.9],
      [w * 0.2, h * 0.82, 0.35, 1.0], [w * 0.5, h * 0.78, -0.4, 0.9],
      [w * 0.75, h * 0.85, 0.3, 1.0]
    ];
    for (let i = 0; i < leafPositions.length; i++) {
      ctx.globalAlpha = 0.12 + (i % 3) * 0.04;
      DecorPatternUtil.drawLeafShape(ctx, leafPositions[i][0], leafPositions[i][1], leafPositions[i][2]);
    }
    ctx.globalAlpha = 0.08;
    ctx.strokeStyle = accent;
    ctx.lineWidth = 0.5;
    for (let i = 0; i < 5; i++) {
      let cx: number = w * (0.15 + i * 0.18);
      ctx.beginPath();
      ctx.moveTo(cx, h * 0.96);
      ctx.quadraticCurveTo(cx + 3, h * 0.92, cx, h * 0.88);
      ctx.stroke();
      ctx.beginPath();
      ctx.arc(cx, h * 0.96, 2, 0, Math.PI * 2);
      ctx.stroke();
    }
    ctx.globalAlpha = 1;
  }

  static drawHeart(ctx: CanvasRenderingContext2D, w: number, h: number, accent: string): void {
    ctx.globalAlpha = 0.04;
    ctx.fillStyle = accent;
    for (let i = 0; i < 25; i++) {
      let px: number = Math.floor((i * 37 + 11) % w);
      let py: number = Math.floor((i * 23 + 7) % h);
      ctx.beginPath();
      ctx.arc(px, py, 1, 0, Math.PI * 2);
      ctx.fill();
    }
    let heartPositions: number[][] = [
      [w * 0.1, h * 0.08, 10], [w * 0.85, h * 0.05, 12],
      [w * 0.5, h * 0.02, 8], [w * 0.3, h * 0.18, 6],
      [w * 0.7, h * 0.15, 7],
      [w * 0.05, h * 0.55, 9], [w * 0.9, h * 0.6, 11],
      [w * 0.5, h * 0.45, 14], [w * 0.2, h * 0.75, 8],
      [w * 0.75, h * 0.8, 7], [w * 0.45, h * 0.7, 6]
    ];
    for (let i = 0; i < heartPositions.length; i++) {
      let hx: number = heartPositions[i][0];
      let hy: number = heartPositions[i][1];
      let s: number = heartPositions[i][2];
      ctx.globalAlpha = 0.12 + (i % 3) * 0.05;
      ctx.fillStyle = accent;
      ctx.beginPath();
      ctx.moveTo(hx, hy + s * 0.3);
      ctx.bezierCurveTo(hx, hy - s * 0.3, hx - s, hy - s * 0.3, hx - s, hy + s * 0.1);
      ctx.bezierCurveTo(hx - s, hy + s * 0.6, hx, hy + s, hx, hy + s * 1.2);
      ctx.bezierCurveTo(hx, hy + s, hx + s, hy + s * 0.6, hx + s, hy + s * 0.1);
      ctx.bezierCurveTo(hx + s, hy - s * 0.3, hx, hy - s * 0.3, hx, hy + s * 0.3);
      ctx.fill();
    }
    ctx.globalAlpha = 0.06;
    ctx.fillStyle = accent;
    for (let i = 0; i < 30; i++) {
      let dx: number = Math.floor(w * 0.05 + (i % 6) * w * 0.15);
      let dy: number = Math.floor(h * 0.88 + Math.floor(i / 6) * 12);
      ctx.beginPath();
      ctx.arc(dx, dy, 2, 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.globalAlpha = 1;
  }

  static drawGlitch(ctx: CanvasRenderingContext2D, w: number, h: number, accent: string): void {
    ctx.globalAlpha = 0.04;
    ctx.fillStyle = accent;
    for (let i = 0; i < 40; i++) {
      let px: number = Math.floor((i * 29 + 13) % w);
      let py: number = Math.floor((i * 19 + 7) % h);
      ctx.fillRect(px, py, 2, 1);
    }
    let bars: number[][] = [
      [0, h * 0.05, w * 0.35, 4], [w * 0.65, h * 0.12, w * 0.35, 2],
      [0, h * 0.25, w * 0.2, 3], [w * 0.5, h * 0.28, w * 0.5, 2],
      [0, h * 0.42, w * 0.15, 3], [w * 0.3, h * 0.45, w * 0.3, 2],
      [w * 0.7, h * 0.5, w * 0.3, 4],
      [0, h * 0.65, w * 0.4, 2], [w * 0.6, h * 0.7, w * 0.4, 3],
      [0, h * 0.82, w * 0.25, 2], [w * 0.4, h * 0.88, w * 0.6, 3]
    ];
    for (let i = 0; i < bars.length; i++) {
      ctx.globalAlpha = 0.15 + (i % 3) * 0.06;
      ctx.fillStyle = accent;
      ctx.fillRect(bars[i][0], bars[i][1], bars[i][2], bars[i][3]);
      ctx.globalAlpha = 0.05;
      ctx.fillRect(bars[i][0] + 3, bars[i][1] + 2, bars[i][2], bars[i][3]);
    }
    ctx.globalAlpha = 0.08;
    ctx.strokeStyle = '#00ffff';
    ctx.lineWidth = 1;
    for (let i = 0; i < 8; i++) {
      let y: number = h * (0.15 + i * 0.1);
      let xStart: number = w * (0.6 + (i % 3) * 0.1);
      ctx.beginPath();
      ctx.moveTo(xStart, y);
      ctx.lineTo(w, y);
      ctx.stroke();
    }
    ctx.globalAlpha = 0.06;
    ctx.strokeStyle = '#ff0066';
    ctx.lineWidth = 1;
    for (let i = 0; i < 5; i++) {
      let y: number = h * (0.2 + i * 0.15);
      ctx.beginPath();
      ctx.moveTo(0, y);
      ctx.lineTo(w * 0.3, y);
      ctx.stroke();
    }
    ctx.globalAlpha = 0.12;
    ctx.fillStyle = accent;
    let blocks: number[][] = [
      [w * 0.1, h * 0.18, 8, 8], [w * 0.45, h * 0.55, 6, 6],
      [w * 0.8, h * 0.35, 10, 4], [w * 0.25, h * 0.75, 5, 5]
    ];
    for (let i = 0; i < blocks.length; i++) {
      ctx.fillRect(blocks[i][0], blocks[i][1], blocks[i][2], blocks[i][3]);
    }
    ctx.globalAlpha = 1;
  }

  static drawMountain(ctx: CanvasRenderingContext2D, w: number, h: number, accent: string): void {
    ctx.globalAlpha = 0.04;
    ctx.fillStyle = accent;
    for (let i = 0; i < 25; i++) {
      let px: number = Math.floor((i * 37 + 11) % w);
      let py: number = Math.floor(h * 0.3 + (i * 19) % Math.floor(h * 0.5));
      ctx.beginPath();
      ctx.arc(px, py, 1, 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.globalAlpha = 0.06;
    ctx.fillStyle = accent;
    ctx.beginPath();
    ctx.moveTo(0, h * 0.95);
    ctx.lineTo(w * 0.1, h * 0.75);
    ctx.lineTo(w * 0.2, h * 0.85);
    ctx.lineTo(w * 0.35, h * 0.65);
    ctx.lineTo(w * 0.5, h * 0.8);
    ctx.lineTo(w * 0.6, h * 0.6);
    ctx.lineTo(w * 0.75, h * 0.78);
    ctx.lineTo(w * 0.85, h * 0.55);
    ctx.lineTo(w, h * 0.75);
    ctx.lineTo(w, h);
    ctx.lineTo(0, h);
    ctx.closePath();
    ctx.fill();
    ctx.globalAlpha = 0.12;
    ctx.fillStyle = accent;
    ctx.beginPath();
    ctx.moveTo(0, h * 0.88);
    ctx.lineTo(w * 0.15, h * 0.68);
    ctx.lineTo(w * 0.3, h * 0.82);
    ctx.lineTo(w * 0.5, h * 0.58);
    ctx.lineTo(w * 0.65, h * 0.75);
    ctx.lineTo(w * 0.8, h * 0.62);
    ctx.lineTo(w * 0.9, h * 0.7);
    ctx.lineTo(w, h * 0.82);
    ctx.lineTo(w, h);
    ctx.lineTo(0, h);
    ctx.closePath();
    ctx.fill();
    ctx.globalAlpha = 0.18;
    ctx.fillStyle = accent;
    ctx.beginPath();
    ctx.moveTo(0, h * 0.92);
    ctx.lineTo(w * 0.2, h * 0.82);
    ctx.lineTo(w * 0.4, h * 0.9);
    ctx.lineTo(w * 0.55, h * 0.78);
    ctx.lineTo(w * 0.75, h * 0.88);
    ctx.lineTo(w * 0.9, h * 0.8);
    ctx.lineTo(w, h * 0.88);
    ctx.lineTo(w, h);
    ctx.lineTo(0, h);
    ctx.closePath();
    ctx.fill();
    ctx.globalAlpha = 0.1;
    ctx.strokeStyle = accent;
    ctx.lineWidth = 1;
    ctx.beginPath();
    ctx.moveTo(w * 0.5, h * 0.58);
    ctx.lineTo(w * 0.5, h * 0.48);
    ctx.stroke();
    ctx.beginPath();
    ctx.moveTo(w * 0.5, h * 0.48);
    ctx.lineTo(w * 0.52, h * 0.44);
    ctx.stroke();
    ctx.beginPath();
    ctx.moveTo(w * 0.5, h * 0.48);
    ctx.lineTo(w * 0.48, h * 0.44);
    ctx.stroke();
    ctx.globalAlpha = 0.08;
    ctx.fillStyle = accent;
    ctx.beginPath();
    ctx.arc(w * 0.5, h * 0.44, 4, 0, Math.PI * 2);
    ctx.fill();
    ctx.globalAlpha = 0.06;
    ctx.beginPath();
    ctx.arc(w * 0.82, h * 0.58, 3, 0, Math.PI * 2);
    ctx.fill();
    ctx.globalAlpha = 1;
  }

  static drawGrid(ctx: CanvasRenderingContext2D, w: number, h: number, accent: string): void {
    let spacing: number = 28;
    ctx.globalAlpha = 0.06;
    ctx.strokeStyle = accent;
    ctx.lineWidth = 0.5;
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
    ctx.globalAlpha = 0.12;
    ctx.strokeStyle = accent;
    ctx.lineWidth = 1;
    for (let x = 0; x <= w; x += spacing * 4) {
      ctx.beginPath();
      ctx.moveTo(x, 0);
      ctx.lineTo(x, h);
      ctx.stroke();
    }
    for (let y = 0; y <= h; y += spacing * 4) {
      ctx.beginPath();
      ctx.moveTo(0, y);
      ctx.lineTo(w, y);
      ctx.stroke();
    }
    ctx.globalAlpha = 0.2;
    ctx.strokeStyle = accent;
    ctx.lineWidth = 1.5;
    let crosses: number[][] = [
      [w * 0.15, h * 0.2], [w * 0.8, h * 0.15],
      [w * 0.5, h * 0.5], [w * 0.2, h * 0.8],
      [w * 0.85, h * 0.75], [w * 0.5, h * 0.15],
      [w * 0.35, h * 0.65], [w * 0.7, h * 0.4]
    ];
    for (let i = 0; i < crosses.length; i++) {
      let cx: number = crosses[i][0];
      let cy: number = crosses[i][1];
      ctx.beginPath();
      ctx.moveTo(cx - 7, cy);
      ctx.lineTo(cx + 7, cy);
      ctx.stroke();
      ctx.beginPath();
      ctx.moveTo(cx, cy - 7);
      ctx.lineTo(cx, cy + 7);
      ctx.stroke();
      ctx.globalAlpha = 0.08;
      ctx.fillStyle = accent;
      ctx.beginPath();
      ctx.arc(cx, cy, 3, 0, Math.PI * 2);
      ctx.fill();
      ctx.globalAlpha = 0.2;
    }
    ctx.globalAlpha = 0.08;
    ctx.fillStyle = accent;
    let dots: number[][] = [
      [spacing, spacing], [w - spacing, spacing],
      [spacing, h - spacing], [w - spacing, h - spacing]
    ];
    for (let i = 0; i < dots.length; i++) {
      ctx.beginPath();
      ctx.arc(dots[i][0], dots[i][1], 4, 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.globalAlpha = 1;
  }

  static drawDot(ctx: CanvasRenderingContext2D, w: number, h: number, accent: string): void {
    let spacing: number = 22;
    ctx.globalAlpha = 0.1;
    ctx.fillStyle = accent;
    for (let x = spacing; x < w; x += spacing) {
      for (let y = spacing; y < h; y += spacing) {
        ctx.beginPath();
        ctx.arc(x, y, 1.5, 0, Math.PI * 2);
        ctx.fill();
      }
    }
    ctx.globalAlpha = 0.04;
    ctx.fillStyle = accent;
    for (let x = spacing / 2; x < w; x += spacing) {
      for (let y = spacing / 2; y < h; y += spacing) {
        ctx.beginPath();
        ctx.arc(x, y, 1, 0, Math.PI * 2);
        ctx.fill();
      }
    }
    let bigDots: number[][] = [
      [w * 0.1, h * 0.1, 8], [w * 0.9, h * 0.08, 10],
      [w * 0.05, h * 0.9, 7], [w * 0.92, h * 0.88, 9],
      [w * 0.5, h * 0.5, 6], [w * 0.3, h * 0.3, 5],
      [w * 0.7, h * 0.7, 5]
    ];
    for (let i = 0; i < bigDots.length; i++) {
      ctx.globalAlpha = 0.18;
      ctx.fillStyle = accent;
      ctx.beginPath();
      ctx.arc(bigDots[i][0], bigDots[i][1], bigDots[i][2], 0, Math.PI * 2);
      ctx.fill();
      ctx.globalAlpha = 0.06;
      ctx.beginPath();
      ctx.arc(bigDots[i][0], bigDots[i][1], bigDots[i][2] + 4, 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.globalAlpha = 0.08;
    ctx.fillStyle = accent;
    for (let i = 0; i < 15; i++) {
      let mx: number = Math.floor((i * 47 + 23) % w);
      let my: number = Math.floor((i * 31 + 17) % h);
      ctx.beginPath();
      ctx.arc(mx, my, 3, 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.globalAlpha = 1;
  }

  static drawLine(ctx: CanvasRenderingContext2D, w: number, h: number, accent: string): void {
    ctx.globalAlpha = 0.04;
    ctx.fillStyle = accent;
    for (let i = 0; i < 30; i++) {
      let px: number = Math.floor((i * 37 + 13) % w);
      let py: number = Math.floor((i * 23 + 7) % h);
      ctx.fillRect(px, py, 1, 1);
    }
    let lines: number[][] = [
      [0, h * 0.15, w * 0.7, h * 0.1, 2.5],
      [w * 0.3, h * 0.28, w, h * 0.22, 1.5],
      [0, h * 0.42, w * 0.5, h * 0.38, 2],
      [w * 0.5, h * 0.45, w, h * 0.4, 1],
      [0, h * 0.6, w * 0.6, h * 0.55, 2],
      [w * 0.4, h * 0.65, w, h * 0.58, 1.5],
      [0, h * 0.78, w * 0.4, h * 0.75, 1],
      [w * 0.6, h * 0.8, w, h * 0.72, 2]
    ];
    for (let i = 0; i < lines.length; i++) {
      ctx.globalAlpha = 0.12 + (i % 3) * 0.04;
      ctx.strokeStyle = accent;
      ctx.lineWidth = lines[i][4];
      ctx.beginPath();
      ctx.moveTo(lines[i][0], lines[i][1]);
      ctx.lineTo(lines[i][2], lines[i][3]);
      ctx.stroke();
    }
    ctx.globalAlpha = 0.06;
    ctx.strokeStyle = '#00ffff';
    ctx.lineWidth = 1;
    let glowLines: number[][] = [
      [w * 0.3, 0, w * 0.32, h * 0.5],
      [w * 0.7, h * 0.5, w * 0.68, h],
      [0, h * 0.35, w * 0.6, h * 0.33],
      [w * 0.4, h * 0.7, w, h * 0.68]
    ];
    for (let i = 0; i < glowLines.length; i++) {
      ctx.beginPath();
      ctx.moveTo(glowLines[i][0], glowLines[i][1]);
      ctx.lineTo(glowLines[i][2], glowLines[i][3]);
      ctx.stroke();
    }
    ctx.globalAlpha = 0.15;
    ctx.fillStyle = accent;
    let nodes: number[][] = [
      [w * 0.3, h * 0.15], [w * 0.7, h * 0.28],
      [w * 0.5, h * 0.42], [w * 0.2, h * 0.6],
      [w * 0.8, h * 0.65], [w * 0.5, h * 0.78]
    ];
    for (let i = 0; i < nodes.length; i++) {
      ctx.beginPath();
      ctx.arc(nodes[i][0], nodes[i][1], 4, 0, Math.PI * 2);
      ctx.fill();
      ctx.globalAlpha = 0.06;
      ctx.beginPath();
      ctx.arc(nodes[i][0], nodes[i][1], 8, 0, Math.PI * 2);
      ctx.fill();
      ctx.globalAlpha = 0.15;
    }
    ctx.globalAlpha = 1;
  }

  static drawVine(ctx: CanvasRenderingContext2D, w: number, h: number, accent: string): void {
    ctx.globalAlpha = 0.04;
    ctx.fillStyle = accent;
    for (let i = 0; i < 25; i++) {
      let px: number = Math.floor((i * 37 + 11) % w);
      let py: number = Math.floor((i * 23 + 7) % h);
      ctx.beginPath();
      ctx.arc(px, py, 1, 0, Math.PI * 2);
      ctx.fill();
    }
    let vines: number[][] = [
      [w * 0.92, 0, -1, 3],
      [w * 0.08, 0, 1, 2],
      [w * 0.5, h * 0.6, -1, 1.5]
    ];
    for (let v = 0; v < vines.length; v++) {
      let vx: number = vines[v][0];
      let vy: number = vines[v][1];
      let dir: number = vines[v][2];
      let lw: number = vines[v][3];
      ctx.globalAlpha = 0.16;
      ctx.strokeStyle = accent;
      ctx.lineWidth = lw;
      ctx.beginPath();
      ctx.moveTo(vx, vy);
      let step: number = 15;
      while (vy < h) {
        vy += step;
        vx += dir * (8 + Math.sin(vy * 0.05) * 6);
        ctx.lineTo(vx, vy);
      }
      ctx.stroke();
      ctx.globalAlpha = 0.12;
      ctx.fillStyle = accent;
      let leafY: number = 0;
      let leafX: number = vines[v][0];
      let leafDir: number = vines[v][2];
      while (leafY < h - 20) {
        leafY += 50;
        leafX += leafDir * (8 + Math.sin(leafY * 0.05) * 6);
        DecorPatternUtil.drawLeafShape(ctx, leafX + leafDir * 12, leafY, leafDir * 0.5);
        DecorPatternUtil.drawLeafShape(ctx, leafX - leafDir * 8, leafY + 15, -leafDir * 0.4);
      }
    }
    ctx.globalAlpha = 0.08;
    ctx.fillStyle = accent;
    for (let i = 0; i < 8; i++) {
      let bx: number = w * 0.1 + i * w * 0.11;
      let by: number = h * 0.94;
      ctx.beginPath();
      ctx.arc(bx, by, 5, 0, Math.PI * 2);
      ctx.fill();
      ctx.beginPath();
      ctx.arc(bx + 4, by - 5, 3, 0, Math.PI * 2);
      ctx.fill();
      ctx.beginPath();
      ctx.arc(bx - 3, by - 4, 2.5, 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.globalAlpha = 1;
  }

  static drawSnow(ctx: CanvasRenderingContext2D, w: number, h: number, accent: string): void {
    ctx.globalAlpha = 0.04;
    ctx.fillStyle = accent;
    for (let i = 0; i < 30; i++) {
      let px: number = Math.floor((i * 37 + 11) % w);
      let py: number = Math.floor((i * 23 + 7) % h);
      ctx.beginPath();
      ctx.arc(px, py, 1, 0, Math.PI * 2);
      ctx.fill();
    }
    let flakes: number[][] = [
      [w * 0.1, h * 0.08, 8], [w * 0.3, h * 0.15, 10], [w * 0.6, h * 0.05, 7],
      [w * 0.85, h * 0.12, 9], [w * 0.15, h * 0.32, 6], [w * 0.5, h * 0.28, 11],
      [w * 0.8, h * 0.38, 8], [w * 0.25, h * 0.55, 7], [w * 0.7, h * 0.5, 9],
      [w * 0.4, h * 0.72, 10], [w * 0.9, h * 0.68, 6], [w * 0.1, h * 0.82, 8],
      [w * 0.6, h * 0.88, 7], [w * 0.35, h * 0.45, 5], [w * 0.75, h * 0.22, 6]
    ];
    for (let i = 0; i < flakes.length; i++) {
      let fx: number = flakes[i][0];
      let fy: number = flakes[i][1];
      let s: number = flakes[i][2];
      ctx.globalAlpha = 0.12 + (i % 3) * 0.04;
      ctx.strokeStyle = accent;
      ctx.lineWidth = 1;
      for (let a = 0; a < 3; a++) {
        let angle: number = a * Math.PI / 3;
        ctx.beginPath();
        ctx.moveTo(fx + Math.cos(angle) * -s, fy + Math.sin(angle) * -s);
        ctx.lineTo(fx + Math.cos(angle) * s, fy + Math.sin(angle) * s);
        ctx.stroke();
        let bx: number = fx + Math.cos(angle) * s * 0.6;
        let by: number = fy + Math.sin(angle) * s * 0.6;
        ctx.beginPath();
        ctx.moveTo(bx, by);
        ctx.lineTo(bx + Math.cos(angle + 0.5) * s * 0.3, by + Math.sin(angle + 0.5) * s * 0.3);
        ctx.stroke();
        ctx.beginPath();
        ctx.moveTo(bx, by);
        ctx.lineTo(bx + Math.cos(angle - 0.5) * s * 0.3, by + Math.sin(angle - 0.5) * s * 0.3);
        ctx.stroke();
      }
      ctx.globalAlpha = 0.06;
      ctx.fillStyle = accent;
      ctx.beginPath();
      ctx.arc(fx, fy, 2, 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.globalAlpha = 0.06;
    ctx.fillStyle = accent;
    for (let i = 0; i < 12; i++) {
      let dx: number = Math.floor(w * (0.08 + i * 0.08));
      let dy: number = Math.floor(h * 0.96 + Math.sin(i) * 2);
      ctx.beginPath();
      ctx.arc(dx, dy, 2, 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.globalAlpha = 1;
  }

  static drawSeal(ctx: CanvasRenderingContext2D, w: number, h: number, accent: string): void {
    let m: number = 14;
    ctx.globalAlpha = 0.3;
    ctx.strokeStyle = accent;
    ctx.lineWidth = 1.5;
    ctx.strokeRect(m, m, w - 2 * m, h - 2 * m);
    ctx.globalAlpha = 0.12;
    ctx.lineWidth = 0.5;
    ctx.strokeRect(m + 5, m + 5, w - 2 * (m + 5), h - 2 * (m + 5));
    ctx.strokeRect(m + 8, m + 8, w - 2 * (m + 8), h - 2 * (m + 8));
    ctx.globalAlpha = 0.4;
    DecorPatternUtil.drawPlum(ctx, m + 7, m + 7, accent);
    DecorPatternUtil.drawPlum(ctx, w - m - 7, m + 7, accent);
    DecorPatternUtil.drawPlum(ctx, m + 7, h - m - 7, accent);
    DecorPatternUtil.drawPlum(ctx, w - m - 7, h - m - 7, accent);
    ctx.globalAlpha = 0.2;
    DecorPatternUtil.drawPlum(ctx, w * 0.5, m + 7, accent);
    DecorPatternUtil.drawPlum(ctx, w * 0.5, h - m - 7, accent);
    DecorPatternUtil.drawPlum(ctx, m + 7, h * 0.5, accent);
    DecorPatternUtil.drawPlum(ctx, w - m - 7, h * 0.5, accent);
    ctx.globalAlpha = 0.08;
    ctx.fillStyle = accent;
    let innerM: number = m + 10;
    for (let x = innerM; x < w - innerM; x += 20) {
      ctx.beginPath();
      ctx.arc(x, innerM, 1, 0, Math.PI * 2);
      ctx.fill();
      ctx.beginPath();
      ctx.arc(x, h - innerM, 1, 0, Math.PI * 2);
      ctx.fill();
    }
    DecorPatternUtil.drawSealStamp(ctx, w - 72, 40, 48, accent);
    ctx.globalAlpha = 1;
  }

  static drawPlum(ctx: CanvasRenderingContext2D, x: number, y: number, accent: string): void {
    ctx.save();
    ctx.globalAlpha = 0.45;
    ctx.fillStyle = accent;
    let r: number = 3.0;
    let petals: number = 5;
    for (let i = 0; i < petals; i++) {
      let ang: number = (Math.PI * 2 / petals) * i - Math.PI / 2;
      let px: number = x + Math.cos(ang) * r * 1.8;
      let py: number = y + Math.sin(ang) * r * 1.8;
      ctx.beginPath();
      ctx.arc(px, py, r, 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.globalAlpha = 0.6;
    ctx.beginPath();
    ctx.arc(x, y, r * 0.6, 0, Math.PI * 2);
    ctx.fill();
    ctx.globalAlpha = 0.15;
    ctx.strokeStyle = accent;
    ctx.lineWidth = 0.5;
    for (let i = 0; i < petals; i++) {
      let ang: number = (Math.PI * 2 / petals) * i - Math.PI / 2;
      ctx.beginPath();
      ctx.moveTo(x, y);
      ctx.lineTo(x + Math.cos(ang) * r * 1.5, y + Math.sin(ang) * r * 1.5);
      ctx.stroke();
    }
    ctx.restore();
  }

  static drawSealStamp(ctx: CanvasRenderingContext2D, x: number, y: number, size: number, accent: string): void {
    ctx.save();
    ctx.globalAlpha = 0.85;
    ctx.fillStyle = accent;
    let r: number = 6;
    ctx.beginPath();
    ctx.moveTo(x + r, y);
    ctx.arcTo(x + size, y, x + size, y + size, r);
    ctx.arcTo(x + size, y + size, x, y + size, r);
    ctx.arcTo(x, y + size, x, y, r);
    ctx.arcTo(x, y, x + size, y, r);
    ctx.closePath();
    ctx.fill();
    ctx.globalAlpha = 0.75;
    ctx.strokeStyle = '#ffffff';
    ctx.lineWidth = 1.5;
    ctx.strokeRect(x + 5, y + 5, size - 10, size - 10);
    ctx.fillStyle = '#ffffff';
    ctx.font = 'bold 18px sans-serif';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    let cx: number = x + size / 2;
    ctx.fillText('解', cx, y + size * 0.3);
    ctx.fillText('语', cx, y + size * 0.72);
    ctx.restore();
  }
}
