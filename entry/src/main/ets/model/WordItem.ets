export class WordItem {
  text: string = '';
  weight: number = 1;
  color: string = '';
  font: string = '';
}

export class PlacedWord {
  text: string = '';
  x: number = 0;
  y: number = 0;
  size: number = 0;
  color: string = '';
  angle: number = 0;
  font: string = '';
  width: number = 0;
  height: number = 0;
}

export class CloudWord {
  text: string = '';
  weight: number = 1;
  fontSize: number = 0;
  custom: boolean = false;

  constructor(text: string, weight: number, custom: boolean) {
    this.text = text;
    this.weight = weight;
    this.custom = custom;
  }
}
