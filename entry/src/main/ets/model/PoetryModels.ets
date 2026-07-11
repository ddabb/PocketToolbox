export class PoetItem {
  n: string = '';
  d: string = '';
  pc: number = 0;
  i: string = '';
}

export class DynastyItem {
  name: string = '';
}

export class FullTextEntry {
  t: string = '';
  a: string = '';
  d: string = '';
}

export class PoetryIndexData {
  poets: PoetItem[] = [];
  dynasties: DynastyItem[] = [];
  ftEntry: FullTextEntry[] = [];
}

export class PoemItem {
  n: string = '';
  c: string = '';
  f: string = '';
  a: string = '';
  d: string = '';
}

export class PoetDetail {
  name: string = '';
  dynasty: string = '';
  desc: string = '';
  poems: PoemItem[] = [];
  initial: string = '';
}

export class SearchResultItem {
  type: string = '';
  title: string = '';
  subtitle: string = '';
  poetInitial: string = '';
  poetDynasty: string = '';
}
