import abilityTest from './Ability.test';
import sudokuOcrTest from './SudokuOcr.test';
import coverTest from './Cover.test';
import charCardTest from './CharCard.test';
import posterTypesetTest from './PosterTypeset.test';
import sudokuEngineTest from './SudokuEngine.test';
import gifCodecTest from './GifCodec.test';
import pdfUtilTest from './PdfUtil.test';
import backupUtilTest from './BackupUtil.test';
import sudokuPixelTest from './SudokuPixel.test';

export default function testsuite() {
  abilityTest();
  sudokuOcrTest();
  coverTest();
  charCardTest();
  posterTypesetTest();
  sudokuEngineTest();
  gifCodecTest();
  pdfUtilTest();
  backupUtilTest();
  sudokuPixelTest();
}
