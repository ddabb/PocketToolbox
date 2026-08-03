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

  // P1优化: 预分配数组, 避免 push() 的动态扩容开销
  let wordCount: number = input.words.length;
  let weightedItems: WeightedItem[] = new Array(wordCount);
  for (let i: number = 0; i < wordCount; i++) {
    let item: WeightedItem = new WeightedItem();
    item.text = input.words[i].text;
    item.weight = input.words[i].weight;
    item.tag = '';
    weightedItems[i] = item;
  }

  FontScaler.scaleAll(weightedItems, layoutSize, shape.shapeRatio);

  let placer: BitmapPlacer = new BitmapPlacer(layoutSize);
  let sprites: WordSprite[] = new Array(wordCount);
  for (let i: number = 0; i < wordCount; i++) {
    sprites[i] = placer.makeSprite(
      weightedItems[i].text,
      weightedItems[i].fontSize,
      input.fontName,
      weightedItems[i].weight,
      0
    );
  }

  let results: PlacedWord[] = placer.place(sprites, shape);

  // P1优化: 预分配结果数组
  let resultCount: number = results.length;
  let placedData: PlacedData[] = new Array(resultCount);
  for (let i: number = 0; i < resultCount; i++) {
    placedData[i] = {
      text: results[i].text,
      x: results[i].x,
      y: results[i].y,
      size: results[i].size,
      angle: results[i].angle,
      width: results[i].width,
      height: results[i].height,
    };
  }

  return {
    placed: placedData,
    count: resultCount,
  };
}

export async function runPlacementAsync(input: WordCloudInput): Promise<WordCloudResult> {
  let task: taskpool.Task = new taskpool.Task(computePlacement, input);
  return await taskpool.execute(task, taskpool.Priority.HIGH) as WordCloudResult;
}
