import { taskpool } from '@kit.ArkTS';
import { BitmapPlacer, WordSprite } from './BitmapPlacer';
import { ShapeDef } from './ShapeDef';
import { PlacedWord } from '../../model/WordItem';

export interface SpriteData {
  text: string;
  fontSize: number;
  font: string;
  weight: number;
  width: number;
  height: number;
}

export interface PlacedData {
  text: string;
  x: number;
  y: number;
  size: number;
  angle: number;
  width: number;
  height: number;
}

export interface WordCloudInput {
  words: SpriteData[];
  canvasSize: number;
  shapeIndex: number;
  fontName: string;
}

export interface WordCloudResult {
  placed: PlacedData[];
  count: number;
}

@Concurrent
function computePlacement(input: WordCloudInput): WordCloudResult {
  let shape: ShapeDef = ShapeDef.SHAPES[input.shapeIndex];
  let placer: BitmapPlacer = new BitmapPlacer(input.canvasSize);

  let sprites: WordSprite[] = [];
  for (let i: number = 0; i < input.words.length; i++) {
    let sprite: WordSprite = placer.makeSprite(
      input.words[i].text,
      input.words[i].fontSize,
      input.words[i].font,
      input.words[i].weight,
      0
    );
    sprites.push(sprite);
  }

  let results: PlacedWord[] = placer.place(sprites, shape);

  let placedData: PlacedData[] = [];
  for (let i: number = 0; i < results.length; i++) {
    let pd: PlacedData = {
      text: results[i].text,
      x: results[i].x,
      y: results[i].y,
      size: results[i].size,
      angle: results[i].angle,
      width: results[i].width,
      height: results[i].height,
    };
    placedData.push(pd);
  }

  let result: WordCloudResult = {
    placed: placedData,
    count: placedData.length,
  };
  return result;
}

export async function runPlacementAsync(input: WordCloudInput): Promise<WordCloudResult> {
  let task: taskpool.Task = new taskpool.Task(computePlacement, input);
  return await taskpool.execute(task) as WordCloudResult;
}
