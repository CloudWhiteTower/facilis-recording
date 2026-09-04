import { WaveformUtils } from '../utils/WaveformUtils';
import { HarmonyTheme, ThemeMode } from '../utils/HarmonyTheme';

@Component
export struct LiveWaveform {
  @Prop values: number[] = [];
  @Prop active: boolean = false;
  @Prop themeMode: number = ThemeMode.LIGHT;
  @Prop renderHeight: number = 88;

  build() {
    Row({ space: 10 }) {
      Row() {
        ForEach(this.valuesForRender(), (value: number, index: number) => {
          Column()
            .width(2)
            .height(this.barHeight(value))
            .borderRadius(2)
            .backgroundColor(this.active ? HarmonyTheme.palette(this.themeMode).recording :
              HarmonyTheme.palette(this.themeMode).waveformIdle)
            .opacity(this.active ? 1 : 0.55)
        }, (value: number, index: number): string => `${index}_${value}`)
      }
      .layoutWeight(1)
      .height(this.renderHeight)
      .justifyContent(FlexAlign.SpaceBetween)
      .alignItems(VerticalAlign.Bottom)

      this.levelScale()
    }
    .width('100%')
    .height(this.renderHeight)
    .alignItems(VerticalAlign.Bottom)
  }

  private valuesForRender(): number[] {
    const result: number[] = [];
    const targetCount = 84;
    const start = Math.max(0, this.values.length - targetCount);
    for (let index = start; index < this.values.length; index++) {
      result.push(this.values[index]);
    }
    while (result.length < targetCount) {
      result.unshift(0);
    }
    return result;
  }

  private barHeight(value: number): number {
    return Math.max(4, Math.round(WaveformUtils.displayHeight(value) * this.renderHeight));
  }

  @Builder
  private levelScale() {
    Column({ space: 0 }) {
      this.levelMark('0')
      Blank().layoutWeight(1)
      this.levelMark('-12')
      Blank().layoutWeight(1)
      this.levelMark('-24')
      Blank().layoutWeight(1)
      this.levelMark('-36')
      Blank().layoutWeight(1)
      this.levelMark('-48 dB')
    }
    .width(40)
    .height(this.renderHeight)
    .alignItems(HorizontalAlign.End)
  }

  @Builder
  private levelMark(label: string) {
    Text(label)
      .fontSize(10)
      .fontColor(HarmonyTheme.palette(this.themeMode).textTertiary)
  }
}
