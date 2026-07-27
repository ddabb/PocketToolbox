import { Context } from '@kit.AbilityKit';
import { PoetryViewModel } from '../../viewmodel/PoetryViewModel';
import { IdiomViewModel } from '../../viewmodel/IdiomViewModel';
import { XiehouyuViewModel } from '../../viewmodel/XiehouyuViewModel';
import { PoemItem, PoetDetail, PoetItem } from '../../model/PoetryModels';
import { XiehouyuItem } from '../../model/XiehouyuModels';

export class ChallengeQuestion {
  type: string = '';
  question: string = '';
  options: string[] = [];
  answerIndex: number = 0;
  hint: string = '';

  static create(type: string, question: string, options: string[], answerIndex: number,
    hint: string): ChallengeQuestion {
    let q: ChallengeQuestion = new ChallengeQuestion();
    q.type = type;
    q.question = question;
    q.options = options;
    q.answerIndex = answerIndex;
    q.hint = hint;
    return q;
  }
}

export class DailyChallengeUtil {
  private static readonly QUESTION_COUNT: number = 5;

  static getDailySeed(): number {
    let now: Date = new Date();
    return now.getFullYear() * 10000 + (now.getMonth() + 1) * 100 + now.getDate();
  }

  private static seededRandom(seed: number): number {
    let x: number = Math.sin(seed) * 10000;
    return x - Math.floor(x);
  }

  static generateQuestions(context: Context): ChallengeQuestion[] {
    let seed: number = DailyChallengeUtil.getDailySeed();
    let questions: ChallengeQuestion[] = [];

    let poemQ: ChallengeQuestion | null = DailyChallengeUtil.generatePoemFillBlank(context, seed);
    if (poemQ) {
      questions.push(poemQ);
    }

    let poemQ2: ChallengeQuestion | null = DailyChallengeUtil.generatePoemFillBlank(context, seed + 100);
    if (poemQ2) {
      questions.push(poemQ2);
    }

    let idiomQ: ChallengeQuestion | null = DailyChallengeUtil.generateIdiomQuestion(context, seed + 200);
    if (idiomQ) {
      questions.push(idiomQ);
    }

    let xiehouyuQ: ChallengeQuestion | null = DailyChallengeUtil.generateXiehouyuQuestion(context, seed + 300);
    if (xiehouyuQ) {
      questions.push(xiehouyuQ);
    }

    let idiomQ2: ChallengeQuestion | null = DailyChallengeUtil.generateIdiomQuestion(context, seed + 400);
    if (idiomQ2) {
      questions.push(idiomQ2);
    }

    if (questions.length > DailyChallengeUtil.QUESTION_COUNT) {
      questions = questions.slice(0, DailyChallengeUtil.QUESTION_COUNT);
    }

    return questions;
  }

  private static generatePoemFillBlank(context: Context, seed: number): ChallengeQuestion | null {
    let vm: PoetryViewModel = PoetryViewModel.getInstance();
    if (!vm.isDataLoaded()) {
      let ok: boolean = vm.loadIndex(context);
      if (!ok) {
        return null;
      }
    }
    let poets: PoetItem[] = vm.getFilteredPoets('全部');
    if (poets.length === 0) {
      return null;
    }
    let poetIdx: number = Math.floor(DailyChallengeUtil.seededRandom(seed) * poets.length);
    let poet: PoetItem = poets[poetIdx];
    let detail: PoetDetail = vm.loadPoetDetail(context, poet.n, poet.i, poet.d);
    if (detail.poems.length === 0) {
      return null;
    }
    let poemIdx: number = Math.floor(DailyChallengeUtil.seededRandom(seed + 1) * detail.poems.length);
    let poem: PoemItem = detail.poems[poemIdx];
    let content: string = poem.c;
    if (!content || content.length < 10) {
      return null;
    }
    let sentences: string[] = content.split(/[，。！？；、]/);
    let validSentences: string[] = [];
    for (let i = 0; i < sentences.length; i++) {
      let s: string = sentences[i].trim();
      if (s.length >= 3 && s.length <= 10) {
        validSentences.push(s);
      }
    }
    if (validSentences.length === 0) {
      return null;
    }
    let sentIdx: number = Math.floor(DailyChallengeUtil.seededRandom(seed + 2) * validSentences.length);
    let sentence: string = validSentences[sentIdx];
    let charIdx: number = Math.floor(DailyChallengeUtil.seededRandom(seed + 3) * sentence.length);
    let answer: string = sentence.charAt(charIdx);
    let display: string = sentence.substring(0, charIdx) + '___' + sentence.substring(charIdx + 1);
    let options: string[] = DailyChallengeUtil.buildOptions(answer, seed + 4);
    let answerIdx: number = options.indexOf(answer);
    if (answerIdx < 0) {
      answerIdx = 0;
    }
    return ChallengeQuestion.create('poem', '请填出空缺的字：\n' + display +
      '\n——' + detail.name + '《' + poem.n + '》', options, answerIdx, detail.name + '·' + detail.dynasty);
  }

  private static generateIdiomQuestion(context: Context, seed: number): ChallengeQuestion | null {
    let vm: IdiomViewModel = IdiomViewModel.getInstance();
    if (!vm.isDataLoaded()) {
      let ok: boolean = vm.loadData(context);
      if (!ok) {
        return null;
      }
    }
    let words: string[] = vm.getAllWords();
    if (words.length === 0) {
      return null;
    }
    let idx: number = Math.floor(DailyChallengeUtil.seededRandom(seed) * words.length);
    let word: string = words[idx];
    if (word.length < 4) {
      return null;
    }
    let charIdx: number = Math.floor(DailyChallengeUtil.seededRandom(seed + 1) * word.length);
    let answer: string = word.charAt(charIdx);
    let display: string = word.substring(0, charIdx) + '___' + word.substring(charIdx + 1);
    let options: string[] = DailyChallengeUtil.buildOptions(answer, seed + 2);
    let answerIdx: number = options.indexOf(answer);
    if (answerIdx < 0) {
      answerIdx = 0;
    }
    return ChallengeQuestion.create('idiom', '请填出成语中空缺的字：\n' + display, options, answerIdx, word);
  }

  private static generateXiehouyuQuestion(context: Context, seed: number): ChallengeQuestion | null {
    let vm: XiehouyuViewModel = XiehouyuViewModel.getInstance();
    if (!vm.isReady()) {
      let ok: boolean = vm.loadData(context);
      if (!ok) {
        return null;
      }
    }
    let item: XiehouyuItem | null = vm.getDailyItem(seed);
    if (!item) {
      return null;
    }
    let answer: string = item.answer;
    let options: string[] = DailyChallengeUtil.buildTextOptions(answer, seed + 1);
    let answerIdx: number = options.indexOf(answer);
    if (answerIdx < 0) {
      answerIdx = 0;
    }
    return ChallengeQuestion.create('xiehouyu', '猜猜歇后语的下半句：\n' + item.riddle + '——？',
      options, answerIdx, item.riddle);
  }

  private static buildOptions(answer: string, seed: number): string[] {
    let distractors: string[] = DailyChallengeUtil.getDistractorChars(answer);
    let rand1: number = DailyChallengeUtil.seededRandom(seed);
    let rand2: number = DailyChallengeUtil.seededRandom(seed + 1);
    let opt1: string = distractors.length > 0 ? distractors[Math.floor(rand1 * distractors.length)] : '的';
    let opt2: string = distractors.length > 1 ? distractors[Math.floor(rand2 * distractors.length)] : '了';
    let options: string[] = [answer, opt1, opt2];
    let unique: string[] = [];
    for (let i = 0; i < options.length; i++) {
      if (unique.indexOf(options[i]) < 0) {
        unique.push(options[i]);
      }
    }
    while (unique.length < 3) {
      unique.push('之');
    }
    for (let i: number = unique.length - 1; i > 0; i--) {
      let j: number = Math.floor(DailyChallengeUtil.seededRandom(seed + i + 10) * (i + 1));
      let temp: string = unique[i];
      unique[i] = unique[j];
      unique[j] = temp;
    }
    return unique;
  }

  private static buildTextOptions(answer: string, seed: number): string[] {
    let options: string[] = [answer];
    let commonAnswers: string[] = ['一场空', '白费劲', '自讨苦吃', '有去无回', '两头空',
      '自作自受', '不长记性', '照旧', '装样子', '不识抬举', '出洋相', '假慈悲',
      '胆子大', '一团糟', '不自量力', '走投无路', '各有千秋', '装模作样'];
    let rand1: number = DailyChallengeUtil.seededRandom(seed);
    let rand2: number = DailyChallengeUtil.seededRandom(seed + 1);
    let opt1: string = commonAnswers[Math.floor(rand1 * commonAnswers.length)];
    let opt2: string = commonAnswers[Math.floor(rand2 * commonAnswers.length)];
    if (opt1 !== answer && options.indexOf(opt1) < 0) {
      options.push(opt1);
    }
    if (opt2 !== answer && options.indexOf(opt2) < 0) {
      options.push(opt2);
    }
    while (options.length < 3) {
      let r: number = DailyChallengeUtil.seededRandom(seed + options.length * 7);
      let candidate: string = commonAnswers[Math.floor(r * commonAnswers.length)];
      if (options.indexOf(candidate) < 0) {
        options.push(candidate);
      }
    }
    for (let i: number = options.length - 1; i > 0; i--) {
      let j: number = Math.floor(DailyChallengeUtil.seededRandom(seed + i + 20) * (i + 1));
      let temp: string = options[i];
      options[i] = options[j];
      options[j] = temp;
    }
    return options;
  }

  private static getDistractorChars(answer: string): string[] {
    let pool: string = '的是不了在有人这我他她它们会和地得着过被让把给向从对与以之其而或亦且则虽若如因故遂终将欲';
    let result: string[] = [];
    for (let i = 0; i < pool.length; i++) {
      let ch: string = pool.charAt(i);
      if (ch !== answer) {
        result.push(ch);
      }
    }
    return result;
  }
}
