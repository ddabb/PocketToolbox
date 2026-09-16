import localUnitTest from './LocalUnit.test';
import sudokuCoreTest from './SudokuCore.test';
import gifEncoderTest from './GifEncoder.test';
import gifParserTest from './GifParser.test';
import gifOverlayModelTest from './GifOverlayModel.test';

export default function testsuite() {
  localUnitTest();
  sudokuCoreTest();
  gifEncoderTest();
  gifParserTest();
  gifOverlayModelTest();
}
