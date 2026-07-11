export class IdiomFirstIndex {
  keys: string[] = [];
  values: string[][] = [];
}

export class IdiomLastIndex {
  keys: string[] = [];
  values: string[][] = [];
}

export class IdiomDetailItem {
  word: string = '';
  pinyin: string = '';
  explanation: string = '';
  derivation: string = '';
  example: string = '';
}

export class SolitaireResult {
  candidates: string[] = [];
  error: string = '';
  lastIndexLoading: boolean = false;
}

export class IdiomQueryResultItem {
  leftWord: string = '';
  rightWord: string = '';
  leftClass: string = '';
  rightClass: string = '';
  continueWord: string = '';
  actionText: string = '';
  canContinue: boolean = false;
}
