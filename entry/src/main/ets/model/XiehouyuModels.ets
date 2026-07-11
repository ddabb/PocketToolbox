export class XiehouyuItem {
  riddle: string = '';
  answer: string = '';
}

export class XiehouyuCategory {
  key: string = '';
  label: string = '';
  items: XiehouyuItem[] = [];
}
