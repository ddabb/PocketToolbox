import { taskpool } from '@kit.ArkTS';
import { BitmapPlacer, WordSprite } from './BitmapPlacer';
import { ShapeDef } from './ShapeDef';
import { PlacedWord } from '../../model/WordItem';
import { FontScaler, WeightedItem } from '../style/FontScaler';

export interface WordInput {
  text: string;
  weight: number;
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
  words: WordInput[];
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
  let layoutSize: number = input.canvasSize;

  let weightedItems: WeightedItem[] = [];
  for (let i: number = 0; i < input.words.length; i++) {
    let item: WeightedItem = new WeightedItem();
    item.text = input.words[i].text;
    item.weight = input.words[i].weight;
    item.tag = '';
    weightedItems.push(item);
  }

  FontScaler.scaleAll(weightedItems, layoutSize, shape.shapeRatio);

  let placer: BitmapPlacer = new BitmapPlacer(layoutSize);
  let sprites: WordSprite[] = [];
  for (let i: number = 0; i < weightedItems.length; i++) {
    let sprite: WordSprite = placer.makeSprite(
      weightedItems[i].text,
      weightedItems[i].fontSize,
      input.fontName,
      weightedItems[i].weight,
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
  return await taskpool.execute(task, taskpool.Priority.HIGH) as WordCloudResult;
}
