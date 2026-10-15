/**
 * 文案海报模板 · 招牌标识组（1.4.7 P2-1 拆分自 CopyPosterPreview）：
 * T7 霓虹灯招牌（1.4.5 P1-5 装饰层/内容层分层样板）/ T10 翻牌显示屏；NeonDecor/NeonContent/FlapModule 为组内局部子构建器。
 */
import { CopyPosterRatio } from '../../../model/CopyPosterModels';
import { PosterRenderCtx } from './PosterRenderCtx';
import { PinyinBody } from './PosterSharedBuilders';
import { PosterTypeset } from '../../../core/cover/PosterTypeset';

// ---------- T7 霓虹灯招牌（夜墙灯管） ----------
// 1.4.5 P1-5 分层样板：本模板是装饰层/内容层拆分的参考实现，其余模板按此结构迁移。
//   装饰层（Decor）：底部光晕、灯管边框、四角铆钉、暗角 —— 跟随 neonSignH() 尺寸
//   内容层（Content）：tag / body / sign 三槽位 —— 只管排版，由 PosterTypeset 决定字号

function neonSignH(c: PosterRenderCtx): number {
  return c.f(c.ratioKind === CopyPosterRatio.SQUARE ? 470 : 620);
}

/** 灯管内容区可用宽（设计稿 px）：外框 800 - 边框 6*2 - padding 30*2 */
const NEON_AVAIL_W: number = 800 - 12 - 60;

/** T7 装饰层：光晕 + 边框 + 铆钉，不含任何文案 */
@Builder
function NeonDecor(c: PosterRenderCtx) {
  Stack() {
    // 底部光晕
    Column()
      .width('86%')
      .height(c.f(180))
      .radialGradient({
        center: ['50%', '100%'],
        radius: '75%',
        colors: [[c.hexA(c.pal().accent, '#2E'), 0], ['#00000000', 0.72]],
      })
      .position({ x: '7%', y: c.h() - c.posY(180) })
      .hitTestBehavior(HitTestMode.None)

    // 灯管框本体（空心，只出边框与外发光）
    Column()
      .width('100%')
      .height(neonSignH(c))
      .border({ width: c.f(6), color: c.pal().block })
      .borderRadius(c.f(34))
      .shadow({ radius: c.f(40), color: c.hexA(c.pal().block, '#66') })
      .hitTestBehavior(HitTestMode.None)

    // 四角铆钉：位置按 neonSignH() 跟随高度，竖版不塌陷（根因 A）
    Circle({ width: c.f(10), height: c.f(10) }).fill('#D8DEE9').position({ x: c.posX(12), y: c.f(12) })
    Circle({ width: c.f(10), height: c.f(10) }).fill('#D8DEE9')
      .position({ x: c.posX(800) - c.posX(22), y: c.f(12) })
    Circle({ width: c.f(10), height: c.f(10) }).fill('#D8DEE9')
      .position({ x: c.posX(12), y: neonSignH(c) - c.f(22) })
    Circle({ width: c.f(10), height: c.f(10) }).fill('#D8DEE9')
      .position({ x: c.posX(800) - c.posX(22), y: neonSignH(c) - c.f(22) })
  }
  .width(c.f(800))
  .height(neonSignH(c))
  .hitTestBehavior(HitTestMode.None)
}

/** T7 内容层：三个 slot 的排布，字号交由内核按 NEON_AVAIL_W 计算 */
@Builder
function NeonContent(c: PosterRenderCtx) {
  Column({ space: c.f(22) }) {
    if (c.content.tag.trim() !== '') {
      Text('✦ ' + c.content.tag + ' ✦')
        .fontSize(c.f(24))
        .fontColor(c.pal().sub)
        .fontFamily(c.font())
        .letterSpacing(c.f(8))
        .maxLines(1)
        .textShadow([
          { radius: c.f(2), color: c.hexA(c.pal().accent, '#E6'), offsetX: 0, offsetY: 0 },
          { radius: c.f(9), color: c.hexA(c.pal().accent, '#99'), offsetX: 0, offsetY: 0 },
        ])
    }
    if (c.content.body.trim() === '') {
      Text($r('app.string.poster_empty_hint'))
        .fontSize(c.f(32))
        .fontColor(c.pal().sub)
        .fontFamily(c.font())
        .textAlign(TextAlign.Center)
    } else if (c.pyEnabled()) {
      // 行预算 3 与下方渲染 maxLines(3) 对齐：此前内核按 8/12 行算字、渲染只显 3 行，静默吞字
      PinyinBody(c, c.bodyFont(96, false, NEON_AVAIL_W, 3), c.pal().title,
        c.pal().sub, true, true, 'neon', '100%')
    } else {
      Text(c.content.body)
        .fontSize(c.bodyFont(96, false, NEON_AVAIL_W, 3))
        .lineHeight(c.bodyFont(96, false, NEON_AVAIL_W, 3) * 1.35)
        .fontColor(c.pal().title)
        .fontFamily(c.font())
        .fontWeight(FontWeight.Bold)
        .maxLines(3)
        .textAlign(TextAlign.Center)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textShadow([
          { radius: c.f(4), color: '#FFFFFFFF', offsetX: 0, offsetY: 0 },
          { radius: c.f(10), color: c.hexA(c.pal().accent, '#E6'), offsetX: 0, offsetY: 0 },
          { radius: c.f(26), color: c.hexA(c.pal().accent, '#8C'), offsetX: 0, offsetY: 0 },
        ])
      if (c.truncatedHint() > 0 && !c.isThumb) {
        Text($r('app.string.poster_truncated_hint', c.truncatedHint()))
          .fontSize(c.f(20))
          .fontColor(c.pal().sub)
          .fontFamily(c.font())
          .opacity(0.75)
          .textAlign(TextAlign.Center)
          .maxLines(1)
      }
    }
    if (c.content.sign.trim() !== '') {
      Text('—— ' + c.content.sign + ' ——')
        .fontSize(c.f(30))
        .fontColor(c.pal().sub)
        .fontFamily(c.font())
        .letterSpacing(c.f(6))
        .maxLines(1)
        .textShadow([
          { radius: c.f(2), color: '#66FFFFFF', offsetX: 0, offsetY: 0 },
          { radius: c.f(10), color: c.hexA(c.pal().block, '#B3'), offsetX: 0, offsetY: 0 },
        ])
    }
  }
  .width('100%')
  .height('100%')
  .justifyContent(FlexAlign.Center)
  .alignItems(HorizontalAlign.Center)
  .padding({ left: c.f(30), right: c.f(30) })
}

@Builder
export function NeonSign(c: PosterRenderCtx) {
  Stack() {
    NeonDecor(c)
    NeonContent(c)

    Column()
      .width('100%')
      .height('100%')
      .radialGradient({
        center: ['50%', '50%'],
        radius: '85%',
        colors: [['#00000000', 0], ['#00000000', 0.5], ['#A6000000', 1]],
      })
      .hitTestBehavior(HitTestMode.None)
  }
  .width('100%')
  .height('100%')
  .alignContent(Alignment.Center)
}

// ---------- T10 翻牌显示屏（车站翻牌板） ----------

/** 正文去空白后按每行 12 字拆行（最多 6 行） */
/**
 * T10 翻牌屏：把正文拆成每行 12 字的翻牌模块行。
 *
 * 1.4.5 优化：原先固定「12 字/行、最多 6 行」且超出部分**直接丢弃**（用户无感知丢字），
 * 同时底板高度写死导致多行时撑破。现改为：
 *   - 行数与容量由 PosterTypeset 按底板可用宽算出，超出的字截断并由 truncatedHint 提示；
 *   - 底板高度由 flapBoardH() 随实际行数增长，长文案不再溢出。
 */
function flapRows(c: PosterRenderCtx): string[][] {
  let src: string[] = [];
  if (c.content.body.trim() === '') {
    src = ['·', '·', '·'];
  } else {
    src = c.content.body.replace(new RegExp('\\s', 'g'), '').split('');
  }
  // 每行字数按底板可用宽 / 单模块宽推算，替代硬编码 12
  let perRow: number = FLAP_PER_ROW;
  let maxRows: number = flapMaxRows(c);
  let rows: string[][] = [];
  for (let i = 0; i < src.length && rows.length < maxRows; i += perRow) {
    let end: number = Math.min(i + perRow, src.length);
    let r: string[] = [];
    for (let j = i; j < end; j++) {
      r.push(src[j]);
    }
    rows.push(r);
  }
  if (rows.length === 0) {
    rows.push([' ']);
  }
  return rows;
}

/** 翻牌单模块宽（设计稿 px） */
const FLAP_PER_ROW: number = 12;
/** 翻牌最大行数：1:1 保持 6；3:4/9:16 画布越高预算越多，底板随行数增长填满画布 */
function flapMaxRows(c: PosterRenderCtx): number {
  if (c.ratioKind === CopyPosterRatio.SQUARE) {
    return 6;
  }
  return c.ratioKind === CopyPosterRatio.PORTRAIT ? 8 : 10;
}
/** 翻牌模块字高（设计稿 px） */
const FLAP_ROW_H: number = 72;
/** 翻牌模块间距（设计稿 px） */
const FLAP_ROW_GAP: number = 9;

/** 底板高度：随实际行数增长，避免长文案撑破固定底板 */
function flapBoardH(c: PosterRenderCtx): number {
  let rows: number = flapRows(c).length;
  return rows * FLAP_ROW_H +
    (rows - 1) * FLAP_ROW_GAP + c.f(46);
}

/** 翻牌放不下的字数：超出 12 字/行 × 6 行容量部分（0 表示全部显示） */
function flapDropped(c: PosterRenderCtx): number {
  if (c.content.body.trim() === '') {
    return 0;
  }
  let chars: number = PosterTypeset.countChars(c.content.body);
  let cap: number = FLAP_PER_ROW * flapMaxRows(c);
  return chars > cap ? chars - cap : 0;
}

@Builder
function FlapModule(c: PosterRenderCtx, ch: string) {
  Stack() {
    Column()
      .width('100%')
      .height('100%')
      .backgroundColor(c.pal().grid)
      .linearGradient({
        angle: 180,
        colors: [['#38FFFFFF', 0], ['#00000000', 0.45], ['#00000000', 0.55], ['#4D000000', 1]],
      })
    Row().width('90%').height(c.f(2.5)).backgroundColor('#A6000000')
    Text(ch === ' ' ? '' : ch)
      .fontSize(c.f(34))
      .fontWeight(FontWeight.Bold)
      .fontColor(c.pal().title)
      .fontFamily(c.font())
      .maxLines(1)
  }
  .width(c.f(50))
  .height(c.f(72))
  .borderRadius(c.f(5))
  .clip(true)
  .shadow({ radius: c.f(4), color: '#55000000', offsetY: c.f(2) })
}

@Builder
export function SplitFlap(c: PosterRenderCtx) {
  Stack() {
    Column({ space: c.f(18) }) {
      Row() {
        Text('QUOTE BOARD · ' + c.content.tag)
          .fontSize(c.f(20))
          .letterSpacing(c.f(4))
          .fontColor(c.pal().accent)
          .fontWeight(FontWeight.Bold)
          .maxLines(1)
        Row({ space: c.f(6) }) {
          Circle({ width: c.f(9), height: c.f(9) })
            .fill('#39D353')
            .shadow({ radius: c.f(5), color: '#8039D353' })
          Circle({ width: c.f(9), height: c.f(9) })
            .fill('#FF5544')
            .shadow({ radius: c.f(5), color: '#80FF5544' })
        }
        .alignItems(VerticalAlign.Center)
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)
      .alignItems(VerticalAlign.Center)

      Column({ space: c.f(9) }) {
        ForEach(flapRows(c), (row: string[], ri: number) => {
          Row({ space: c.f(8) }) {
            ForEach(row, (ch: string, ci: number) => {
              FlapModule(c, ch)
            }, (ch: string, ci: number) => ci.toString() + ch)
          }
        }, (row: string[], ri: number) => ri.toString() + '-' + row.length.toString())
      }

      // 1.4.5 优化：翻牌容量有限（12 字/行 × 6 行），超出部分原本静默丢弃，此处显式提示
      // 1.4.6 根因 C：缩略图（96px）不显示提示，避免挤爆布局
      if (flapDropped(c) > 0 && !c.isThumb) {
        Text($r('app.string.poster_truncated_hint', flapDropped(c)))
          .fontSize(c.f(20))
          .fontColor(c.pal().sub)
          .fontFamily(c.font())
          .opacity(0.75)
          .textAlign(TextAlign.Center)
          .maxLines(1)
      }

      Row({ space: c.f(12) }) {
        Circle({ width: c.f(8), height: c.f(8) })
          .fill('#39D353')
          .shadow({ radius: c.f(4), color: '#8039D353' })
        Text('——')
          .fontSize(c.f(16))
          .fontColor(c.pal().sub)
        if (c.content.sign.trim() !== '') {
          Text(c.content.sign)
            .fontSize(c.f(19))
            .letterSpacing(c.f(4))
            .fontColor(c.pal().accent)
            .maxLines(1)
        }
        Text('——')
          .fontSize(c.f(16))
          .fontColor(c.pal().sub)
        Circle({ width: c.f(8), height: c.f(8) })
          .fill('#39D353')
          .shadow({ radius: c.f(4), color: '#8039D353' })
      }
      .alignItems(VerticalAlign.Center)
    }
    // 高度随翻牌行数增长（1.4.5 优化：原先固定高度，长文案会撑破底板）
    .height(flapBoardH(c))
    .width(c.f(790))
    .padding({ left: c.f(24), right: c.f(24), top: c.f(22), bottom: c.f(24) })
    .backgroundColor(c.pal().block)
    .borderRadius(c.f(14))
    .border({ width: c.f(2), color: c.pal().grid })
    .shadow({ radius: c.f(44), color: '#8C000000', offsetY: c.f(18) })
    .rotate({ angle: -1.5 })
    .alignItems(HorizontalAlign.Center)

    Column()
      .width('100%')
      .height('100%')
      .radialGradient({
        center: ['50%', '50%'],
        radius: '85%',
        colors: [['#00000000', 0], ['#00000000', 0.5], ['#96000000', 1]],
      })
      .hitTestBehavior(HitTestMode.None)
  }
  .width('100%')
  .height('100%')
  .alignContent(Alignment.Center)
}
