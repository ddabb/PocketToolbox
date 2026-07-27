import { ChallengeQuestion, DailyChallengeUtil } from '../common/utils/DailyChallengeUtil';
import { StickinessUtil, ChallengeProgress } from '../common/utils/StickinessUtil';

@Builder
export function DailyChallengePageBuilder() {
  NavDestination() {
    DailyChallengeContent()
  }
  .title('每日挑战')
  .backButtonIcon($r('sys.symbol.chevron_left'))
  .menus([])
}

@Component
struct DailyChallengeContent {
  @State questions: ChallengeQuestion[] = [];
  @State currentIdx: number = 0;
  @State selectedIdx: number = -1;
  @State score: number = 0;
  @State answered: boolean = false;
  @State finished: boolean = false;
  @State progress: ChallengeProgress = new ChallengeProgress();
  @State isLoading: boolean = true;
  private uiContext: UIContext = this.getUIContext();

  aboutToAppear(): void {
    let ctx: Context = this.uiContext.getHostContext() as Context;
    this.progress = StickinessUtil.loadChallengeProgress(ctx);
    let today: string = StickinessUtil.todayStr();
    if (this.progress.date === today && this.progress.completed) {
      this.finished = true;
      this.score = this.progress.score;
      this.isLoading = false;
      return;
    }
    setTimeout(() => {
      this.questions = DailyChallengeUtil.generateQuestions(ctx);
      this.isLoading = false;
    }, 0);
  }

  private onOptionSelect(optIdx: number): void {
    if (this.answered) {
      return;
    }
    this.selectedIdx = optIdx;
    this.answered = true;
    let correct: boolean = optIdx === this.questions[this.currentIdx].answerIndex;
    if (correct) {
      this.score = this.score + 20;
    }
  }

  private nextQuestion(): void {
    this.selectedIdx = -1;
    this.answered = false;
    if (this.currentIdx < this.questions.length - 1) {
      this.currentIdx = this.currentIdx + 1;
    } else {
      this.finished = true;
      let ctx: Context = this.uiContext.getHostContext() as Context;
      StickinessUtil.completeChallenge(ctx, this.score);
      this.progress = StickinessUtil.loadChallengeProgress(ctx);
    }
  }

  private getTypeIcon(type: string): string {
    if (type === 'poem') {
      return '\uD83C\uDF3C';
    } else if (type === 'idiom') {
      return '\uD83D\uDCD6';
    } else if (type === 'xiehouyu') {
      return '\uD83E\uDD14';
    }
    return '\uD83D\uDCDC';
  }

  private getTypeLabel(type: string): string {
    if (type === 'poem') {
      return '诗词填空';
    } else if (type === 'idiom') {
      return '成语填字';
    } else if (type === 'xiehouyu') {
      return '歇后语猜谜';
    }
    return '挑战';
  }

  private getScoreEmoji(): string {
    if (this.score >= 100) {
      return '\uD83C\uDFC6';
    } else if (this.score >= 60) {
      return '\uD83D\uDC4D';
    } else if (this.score >= 40) {
      return '\uD83D\uDE42';
    }
    return '\uD83D\uDE2E';
  }

  build() {
    Column() {
      if (this.isLoading) {
        Column() {
          LoadingProgress()
            .width(48)
            .height(48)
            .color($r('app.color.poetry_green'))
          Text('题目生成中...')
            .fontSize(16)
            .fontColor($r('app.color.tertiary_text'))
            .margin({ top: 12 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.finished) {
        this.ResultSection()
      } else {
        this.QuestionSection()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }

  @Builder
  QuestionSection() {
    Column() {
      Row() {
        Text('第' + (this.currentIdx + 1).toString() + '/' + this.questions.length.toString() + '题')
          .fontSize(14)
          .fontColor($r('app.color.tertiary_text'))
        Blank()
        Text('得分：' + this.score.toString())
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.poetry_green'))
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 8 })

      Progress({ value: this.currentIdx + 1, total: this.questions.length, type: ProgressType.Linear })
        .width('100%')
        .padding({ left: 16, right: 16 })
        .color($r('app.color.poetry_green'))
        .backgroundColor($r('app.color.border_color'))

      Column() {
        Row() {
          Text(this.getTypeIcon(this.questions[this.currentIdx].type))
            .fontSize(18)
            .margin({ right: 6 })
          Text(this.getTypeLabel(this.questions[this.currentIdx].type))
            .fontSize(13)
            .fontColor($r('app.color.poetry_green'))
            .backgroundColor($r('app.color.poetry_green') + '18')
            .borderRadius(6)
            .padding({ left: 8, right: 8, top: 3, bottom: 3 })
        }
        .margin({ bottom: 12 })

        Text(this.questions[this.currentIdx].question)
          .fontSize(18)
          .fontColor($r('app.color.primary_text'))
          .fontWeight(FontWeight.Medium)
          .lineHeight(28)
          .width('100%')
      }
      .width('100%')
      .padding(20)
      .backgroundColor($r('app.color.card_background'))
      .borderRadius(14)
      .margin({ left: 16, right: 16, top: 12 })

      Column({ space: 10 }) {
        ForEach(this.questions[this.currentIdx].options, (option: string, index: number) => {
          Row() {
            Text(String.fromCharCode(65 + (index as number)))
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.getOptionFontColor(index as number))
              .width(28)
              .height(28)
              .borderRadius(14)
              .backgroundColor(this.getOptionBgColor(index as number))
              .textAlign(TextAlign.Center)
              .margin({ right: 12 })
            Text(option)
              .fontSize(16)
              .fontColor(this.getOptionContentColor(index as number))
              .layoutWeight(1)
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 14, bottom: 14 })
          .backgroundColor(this.getOptionCardBg(index as number))
          .borderRadius(12)
          .border(this.getOptionBorder(index as number))
          .onClick(() => {
            this.onOptionSelect(index as number);
          })
        }, (option: string, index: number) => this.currentIdx.toString() + '_' + index.toString())
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 16 })

      if (this.answered) {
        Column() {
          if (this.selectedIdx === this.questions[this.currentIdx].answerIndex) {
            Row() {
              Text('\u2713')
                .fontSize(16)
                .fontColor('#ffffff')
                .width(24)
                .height(24)
                .borderRadius(12)
                .backgroundColor('#27ae60')
                .textAlign(TextAlign.Center)
                .margin({ right: 8 })
              Text('回答正确！+20分')
                .fontSize(15)
                .fontColor('#27ae60')
                .fontWeight(FontWeight.Bold)
            }
          } else {
            Row() {
              Text('\u2715')
                .fontSize(16)
                .fontColor('#ffffff')
                .width(24)
                .height(24)
                .borderRadius(12)
                .backgroundColor('#e74c3c')
                .textAlign(TextAlign.Center)
                .margin({ right: 8 })
              Text('正确答案：' + this.questions[this.currentIdx].options[this.questions[this.currentIdx].answerIndex])
                .fontSize(15)
                .fontColor('#e74c3c')
                .fontWeight(FontWeight.Bold)
            }
          }

          Text(this.getNextButtonText())
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor('#ffffff')
            .backgroundColor($r('app.color.poetry_green'))
            .borderRadius(22)
            .padding({ left: 36, right: 36, top: 12, bottom: 12 })
            .margin({ top: 16 })
            .onClick(() => {
              this.nextQuestion();
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 8, bottom: 16 })
        .alignItems(HorizontalAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
  }

  private getNextButtonText(): string {
    if (this.currentIdx < this.questions.length - 1) {
      return '下一题';
    }
    return '查看结果';
  }

  private getOptionFontColor(index: number): ResourceColor {
    if (!this.answered) {
      return $r('app.color.poetry_green');
    }
    if (index === this.questions[this.currentIdx].answerIndex) {
      return '#ffffff';
    }
    if (index === this.selectedIdx) {
      return '#e74c3c';
    }
    return $r('app.color.tertiary_text');
  }

  private getOptionBgColor(index: number): ResourceColor {
    if (!this.answered) {
      return $r('app.color.poetry_green') + '18';
    }
    if (index === this.questions[this.currentIdx].answerIndex) {
      return '#27ae60';
    }
    if (index === this.selectedIdx) {
      return '#e74c3c18';
    }
    return $r('app.color.border_color');
  }

  private getOptionContentColor(index: number): ResourceColor {
    if (!this.answered) {
      return $r('app.color.primary_text');
    }
    if (index === this.questions[this.currentIdx].answerIndex) {
      return '#27ae60';
    }
    if (index === this.selectedIdx) {
      return '#e74c3c';
    }
    return $r('app.color.tertiary_text');
  }

  private getOptionCardBg(index: number): ResourceColor {
    if (!this.answered) {
      return $r('app.color.card_background');
    }
    if (index === this.questions[this.currentIdx].answerIndex) {
      return '#27ae6010';
    }
    if (index === this.selectedIdx) {
      return '#e74c3c10';
    }
    return $r('app.color.card_background');
  }

  private getOptionBorder(index: number): BorderOptions | undefined {
    if (!this.answered) {
      return undefined;
    }
    if (index === this.questions[this.currentIdx].answerIndex) {
      return { width: 1.5, color: '#27ae60', style: BorderStyle.Solid };
    }
    if (index === this.selectedIdx) {
      return { width: 1.5, color: '#e74c3c', style: BorderStyle.Solid };
    }
    return undefined;
  }

  @Builder
  ResultSection() {
    Scroll() {
      Column() {
        Text(this.getScoreEmoji())
          .fontSize(64)
          .margin({ top: 32, bottom: 12 })

        Text('今日挑战完成！')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.primary_text'))

        Text('得分：' + this.score.toString() + ' / 100')
          .fontSize(18)
          .fontColor($r('app.color.poetry_green'))
          .fontWeight(FontWeight.Bold)
          .margin({ top: 8 })

        Row() {
          Column() {
            Text(this.progress.totalChallenges.toString())
              .fontSize(22)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.poetry_green'))
            Text('累计挑战')
              .fontSize(11)
              .fontColor($r('app.color.tertiary_text'))
              .margin({ top: 2 })
          }
          .layoutWeight(1)

          Divider()
            .vertical(true)
            .height(30)
            .color($r('app.color.border_color'))

          Column() {
            Text(this.score >= 80 ? '优秀' : this.score >= 60 ? '良好' : this.score >= 40 ? '加油' : '继续努力')
              .fontSize(22)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.idiom_orange'))
            Text('今日评级')
              .fontSize(11)
              .fontColor($r('app.color.tertiary_text'))
              .margin({ top: 2 })
          }
          .layoutWeight(1)
        }
        .width('100%')
        .padding({ top: 16, bottom: 16 })
        .backgroundColor($r('app.color.card_background'))
        .borderRadius(14)
        .margin({ left: 16, right: 16, top: 24 })

        Column() {
          Text('\uD83D\uDCC5 每日挑战每天更新，明天再来！')
            .fontSize(14)
            .fontColor($r('app.color.tertiary_text'))
            .margin({ top: 24 })
        }
        .width('100%')
        .padding({ bottom: 32 })
        .alignItems(HorizontalAlign.Center)
      }
      .width('100%')
    }
    .width('100%')
    .height('100%')
  }
}
