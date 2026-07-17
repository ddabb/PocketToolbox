import { Context } from '@kit.AbilityKit';
import { RawFileUtil } from '../common/utils/RawFileUtil';
import { XiehouyuItem, XiehouyuCategory } from '../model/XiehouyuModels';

class CategoryRule {
  key: string = '';
  label: string = '';
  keywords: string[] = [];
}

export class XiehouyuViewModel {
  private static instance: XiehouyuViewModel | null = null;
  private allItems: XiehouyuItem[] = [];
  private isLoaded: boolean = false;
  private categoryCache: XiehouyuCategory[] = [];
  private categoryMap: Record<string, XiehouyuItem[]> = {};
  private categoryRules: CategoryRule[] = [];

  private constructor() {
    this.initCategoryRules();
  }

  private initCategoryRules(): void {
    this.categoryRules = [
      { key: 'animal', label: '动物', keywords: ['猪', '狗', '猫', '牛', '马', '羊', '鸡', '鸭', '鹅', '鼠', '蛇', '虎', '龙', '兔', '猴', '鱼', '虾', '蟹', '蛙', '蛤蟆', '癞蛤蟆', '蛤蟆', '蜗牛', '蚂蚁', '蜜蜂', '蝴蝶', '蜘蛛', '蜻蜓', '驴', '骡', '骆驼', '鹿', '燕', '雀', '鸦', '鹰', '鹤', '凤', '乌鸦', '喜鹊', '黄鼠狼', '狐狸', '狼', '豹', '象', '狮', '熊', '熊猫', '屎壳郎', '蚯蚓', '蚕', '萤火虫', '壁虎', '蝎子', '蜈蚣', '蝙蝠'] },
      { key: 'person', label: '人物', keywords: ['人', '婆', '公', '娘', '爷', '郎', '哥', '姐', '妹', '弟', '夫', '妻', '母', '父', '子', '女', '童', '叟', '汉', '婶', '嫂', '姑', '舅', '尼姑', '和尚', '道士', '叫花子', '乞丐', '官', '兵', '将', '王', '帝', '后', '诸葛亮', '关公', '张飞', '刘备', '曹操', '孙悟空', '猪八戒', '唐僧', '武大郎', '武松', '林冲', '鲁智深', '阎王', '土地', '菩萨', '神仙', '如来', '观音', '灶神', '玉皇', '财主', '地主', '秀才', '书生', '先生', '瞎子', '聋子', '哑巴', '瘸子', '秃子', '矮子', '胖子', '瘦子'] },
      { key: 'food', label: '食物', keywords: ['饭', '面', '饼', '糕', '糖', '酒', '茶', '肉', '鱼', '蛋', '豆腐', '馒头', '包子', '饺子', '面条', '米饭', '粥', '汤', '菜', '瓜', '果', '桃', '李', '枣', '梨', '橘', '柿', '核桃', '花生', '芝麻', '黄豆', '绿豆', '红豆', '豆腐', '萝卜', '白菜', '韭菜', '葱', '蒜', '姜', '椒', '醋', '盐', '油', '酱'] },
      { key: 'object', label: '器物', keywords: ['锅', '碗', '瓢', '盆', '桶', '缸', '坛', '罐', '瓶', '壶', '杯', '碟', '筷', '勺', '刀', '斧', '锯', '锤', '针', '线', '绳', '索', '网', '篮', '筐', '笼', '箱', '柜', '橱', '桌', '椅', '凳', '床', '席', '枕', '被', '毯', '伞', '扇', '灯', '烛', '镜', '钟', '鼓', '锣', '琴', '笛', '号', '炮', '枪', '剑', '弓', '箭', '车', '船', '桥', '门', '窗', '墙', '梯', '管', '筒'] },
      { key: 'clothing', label: '衣着', keywords: ['衣', '裤', '裙', '袍', '帽', '鞋', '袜', '巾', '带', '领', '袖', '襟', '布', '绸', '缎', '麻', '丝', '棉', '毛', '皮', '袄', '褂', '衫', '背心', '手套', '围巾', '草鞋', '布鞋', '皮鞋', '帽子', '斗笠'] },
      { key: 'nature', label: '自然', keywords: ['天', '地', '日', '月', '星', '云', '雨', '雪', '风', '雷', '电', '霜', '露', '雾', '冰', '山', '水', '河', '海', '湖', '泉', '溪', '江', '浪', '潮', '井', '池', '塘', '泥', '沙', '石', '岩', '洞', '谷', '峰', '坡', '田', '地', '土', '尘', '火', '烟', '炭', '灰', '木', '树', '林', '草', '花', '叶', '枝', '根', '苗'] },
      { key: 'body', label: '身体', keywords: ['头', '脸', '眼', '耳', '鼻', '嘴', '舌', '牙', '唇', '颈', '脖', '肩', '臂', '手', '指', '拳', '掌', '腕', '胸', '背', '腰', '肚', '腹', '腿', '脚', '膝', '骨', '皮', '肉', '血', '汗', '泪', '发', '眉', '须', '胡子'] },
      { key: 'building', label: '建筑', keywords: ['房', '屋', '楼', '阁', '殿', '堂', '庙', '寺', '塔', '墙', '院', '门', '窗', '灶', '厕', '茅', '棚', '窑', '仓', '栏', '圈', '厩', '铺', '店', '馆', '坊', '戏台', '戏台上', '舞台'] },
      { key: 'action', label: '行为', keywords: ['打', '骂', '哭', '笑', '走', '跑', '跳', '飞', '坐', '站', '睡', '吃', '喝', '唱', '说', '看', '听', '写', '画', '算', '偷', '抢', '骗', '借', '还', '买', '卖', '做', '干', '种', '砍', '杀', '烧', '洗', '扫', '挑', '扛', '拉', '推', '抬', '搬', '捧', '抱', '拿', '放', '挂', '贴', '穿', '戴', '梳', '剃', '缝', '补', '修', '盖'] },
      { key: 'trade', label: '行业', keywords: ['木匠', '铁匠', '石匠', '篾匠', '泥瓦匠', '裁缝', '郎中', '大夫', '药铺', '当铺', '钱庄', '掌柜', '伙计', '屠户', '猎户', '渔夫', '农夫', '船夫', '车夫', '轿夫', '挑夫', '卖', '买卖', '生意', '经商', '赶集', '摆摊'] },
      { key: 'other', label: '其他', keywords: [] }
    ];
  }

  static getInstance(): XiehouyuViewModel {
    if (!XiehouyuViewModel.instance) {
      XiehouyuViewModel.instance = new XiehouyuViewModel();
    }
    return XiehouyuViewModel.instance;
  }

  isReady(): boolean {
    return this.isLoaded;
  }

  loadData(context: Context): boolean {
    if (this.isLoaded) {
      return true;
    }
    try {
      let raw: Object[] = RawFileUtil.readJson<Object[]>(context, 'xiehouyu/xiehouyu.json');
      this.allItems = [];
      for (let i = 0; i < raw.length; i++) {
        let obj: Record<string, Object> = raw[i] as Record<string, Object>;
        let item: XiehouyuItem = new XiehouyuItem();
        item.riddle = (obj['riddle'] as string) || '';
        item.answer = (obj['answer'] as string) || '';
        if (item.riddle && item.answer) {
          this.allItems.push(item);
        }
      }
      this.isLoaded = true;
      this.buildCategories();
      console.info('[Xiehouyu] loaded, count=' + this.allItems.length.toString());
      return true;
    } catch (e) {
      console.error('[Xiehouyu] loadData failed: ' + (e as Error).message);
      return false;
    }
  }

  private buildCategories(): void {
    this.categoryMap = {};
    for (let i = 0; i < this.allItems.length; i++) {
      let item: XiehouyuItem = this.allItems[i];
      let key: string = this.matchCategory(item.riddle);
      if (!this.categoryMap[key]) {
        this.categoryMap[key] = [];
      }
      this.categoryMap[key].push(item);
    }
    this.categoryCache = [];
    for (let i = 0; i < this.categoryRules.length; i++) {
      let rule: CategoryRule = this.categoryRules[i];
      let items: XiehouyuItem[] = this.categoryMap[rule.key];
      if (items && items.length > 0) {
        let cat: XiehouyuCategory = new XiehouyuCategory();
        cat.key = rule.key;
        cat.label = rule.label + '(' + items.length.toString() + ')';
        cat.items = items;
        this.categoryCache.push(cat);
      }
    }
  }

  private matchCategory(riddle: string): string {
    for (let i = 0; i < this.categoryRules.length - 1; i++) {
      let rule: CategoryRule = this.categoryRules[i];
      for (let j = 0; j < rule.keywords.length; j++) {
        if (riddle.indexOf(rule.keywords[j]) >= 0) {
          return rule.key;
        }
      }
    }
    return 'other';
  }

  getCategoryItems(key: string): XiehouyuItem[] {
    if (this.categoryMap && this.categoryMap[key]) {
      return this.categoryMap[key];
    }
    for (let i = 0; i < this.categoryCache.length; i++) {
      if (this.categoryCache[i].key === key) {
        return this.categoryCache[i].items;
      }
    }
    return [];
  }

  getCategoryItemsPage(key: string, offset: number, limit: number): XiehouyuItem[] {
    let all: XiehouyuItem[] = this.getCategoryItems(key);
    if (offset >= all.length) {
      return [];
    }
    let end: number = offset + limit;
    if (end > all.length) {
      end = all.length;
    }
    return all.slice(offset, end);
  }

  getCategoryTotal(key: string): number {
    let all: XiehouyuItem[] = this.getCategoryItems(key);
    return all.length;
  }

  search(query: string): XiehouyuItem[] {
    if (!query || !this.isLoaded) {
      return [];
    }
    let q: string = query.trim();
    let results: XiehouyuItem[] = [];
    for (let i = 0; i < this.allItems.length; i++) {
      if (this.allItems[i].riddle.indexOf(q) >= 0 || this.allItems[i].answer.indexOf(q) >= 0) {
        results.push(this.allItems[i]);
        if (results.length >= 200) {
          break;
        }
      }
    }
    return results;
  }

  getCategories(): XiehouyuCategory[] {
    return this.categoryCache;
  }

  getRandomItems(count: number): XiehouyuItem[] {
    if (this.allItems.length === 0) {
      return [];
    }
    let results: XiehouyuItem[] = [];
    let used: Set<number> = new Set();
    let attempts: number = 0;
    while (results.length < count && attempts < count * 3) {
      let idx: number = Math.floor(Math.random() * this.allItems.length);
      if (!used.has(idx)) {
        used.add(idx);
        results.push(this.allItems[idx]);
      }
      attempts++;
    }
    return results;
  }

  getDailyItem(seed: number): XiehouyuItem | null {
    if (this.allItems.length === 0) {
      return null;
    }
    let x: number = Math.sin(seed) * 10000;
    let rand: number = x - Math.floor(x);
    let idx: number = Math.floor(rand * this.allItems.length);
    return this.allItems[idx];
  }
}
