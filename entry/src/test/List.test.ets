import localUnitTest from './LocalUnit.test';
import sudokuCoreTest from './SudokuCore.test';

export default function testsuite() {
  localUnitTest();
  sudokuCoreTest();
}