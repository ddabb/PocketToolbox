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
import sudokuPixelTest from './SudokuPixel.test';
import sudokuGridFixTest from './SudokuGridFix.test';

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
  sudokuPixelTest();
  sudokuGridFixTest();
}
