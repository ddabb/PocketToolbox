/**
 * ohosTest 套件注册表 —— 运行协议（1.4.9 M5-C1 文档化）：
 *  - 模拟器：仅 class 过滤定向跑「纯逻辑套件」，勿跑 sudokuOcrTest（无 OCR 服务，逐用例 30s 超时，全套 >7min）：
 *      hdc shell aa test -b com.ddabb.toolbox -m entry_test -s unittest OpenHarmonyTestRunner
 *        -s class <套件名> -s timeout 15000
 *  - 真机（Mate 60 Pro）：全套 aa test（含 sudokuOcrTest），1.4.8 M6 与 1.4.9 M5 并轨回归。
 *  - class 过滤模式下 delegator.getAppContext() 为壳 context：preferences 不可用
 *    （getPreferencesSync 报 invalid context），涉及 prefs 的断言一律抽纯函数直测（详见各套件头注）。
 *  - 套件分类：纯逻辑=abilityTest/coverTest/charCardTest/posterTypesetTest/copyPosterTest/
 *    sudokuEngineTest/gifCodecTest/pdfUtilTest/backupUtilTest/reviewStoreTest/sudokuPixelTest/
 *    sudokuGridFixTest/wordSegmentTest；真机专属=sudokuOcrTest。
 */
import abilityTest from './Ability.test';
import sudokuOcrTest from './SudokuOcr.test';
import coverTest from './Cover.test';
import charCardTest from './CharCard.test';
import posterTypesetTest from './PosterTypeset.test';
import copyPosterTest from './CopyPoster.test';
import sudokuEngineTest from './SudokuEngine.test';
import gifCodecTest from './GifCodec.test';
import pdfUtilTest from './PdfUtil.test';
import backupUtilTest from './BackupUtil.test';
import reviewStoreTest from './ReviewStore.test';
import sudokuPixelTest from './SudokuPixel.test';
import sudokuGridFixTest from './SudokuGridFix.test';
import wordSegmentTest from './WordSegment.test';

export default function testsuite() {
  abilityTest();
  sudokuOcrTest();
  coverTest();
  charCardTest();
  posterTypesetTest();
  copyPosterTest();
  sudokuEngineTest();
  gifCodecTest();
  pdfUtilTest();
  backupUtilTest();
  reviewStoreTest();
  sudokuPixelTest();
  sudokuGridFixTest();
  wordSegmentTest();
}
