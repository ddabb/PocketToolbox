import abilityTest from './Ability.test';
import sudokuOcrTest from './SudokuOcr.test';
import coverTest from './Cover.test';
import charCardTest from './CharCard.test';

export default function testsuite() {
  abilityTest();
  sudokuOcrTest();
  coverTest();
  charCardTest();
}