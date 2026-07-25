import { textToSpeech } from '@kit.CoreSpeechKit';
import { BusinessError } from '@kit.BasicServicesKit';

export type TtsState = 'idle' | 'speaking' | 'stopped';

export class TtsController {
  private engine: textToSpeech.TextToSpeechEngine | null = null;
  private stateCallback: ((state: TtsState) => void) | null = null;
  private completeCallback: (() => void) | null = null;
  private currentRequestId: string = '';
  private currentState: TtsState = 'idle';

  onStateChange(callback: (state: TtsState) => void): void {
    this.stateCallback = callback;
  }

  onComplete(callback: () => void): void {
    this.completeCallback = callback;
  }

  getState(): TtsState {
    return this.currentState;
  }

  private updateState(state: TtsState): void {
    this.currentState = state;
    if (this.stateCallback) {
      this.stateCallback(state);
    }
  }

  async init(): Promise<boolean> {
    if (this.engine) {
      return true;
    }
    try {
      let extraParam: Record<string, Object> = {
        'style': 'interaction-broadcast',
        'locate': 'CN',
        'name': 'ReadingList_TTS_' + Date.now().toString()
      };
      let initParams: textToSpeech.CreateEngineParams = {
        language: 'zh-CN',
        person: 0,
        online: 1,
        extraParams: extraParam
      };
      this.engine = await textToSpeech.createEngine(initParams);
      let listener: textToSpeech.SpeakListener = {
        onStart: (requestId: string, response: textToSpeech.StartResponse) => {
          console.info('[TtsController] onStart: ' + requestId);
          this.updateState('speaking');
        },
        onComplete: (requestId: string, response: textToSpeech.CompleteResponse) => {
          console.info('[TtsController] onComplete: ' + requestId + ', type=' + response.type.toString());
          if (response.type === 1) {
            this.updateState('idle');
            if (this.completeCallback) {
              this.completeCallback();
            }
          }
        },
        onStop: (requestId: string, response: textToSpeech.StopResponse) => {
          console.info('[TtsController] onStop: ' + requestId);
          this.updateState('stopped');
        },
        onData: (requestId: string, audio: ArrayBuffer, response: textToSpeech.SynthesisResponse) => {
        },
        onError: (requestId: string, errorCode: number, errorMessage: string) => {
          console.error('[TtsController] onError: ' + requestId + ', code=' + errorCode.toString() + ', msg=' + errorMessage);
          this.updateState('idle');
        }
      };
      this.engine.setListener(listener);
      console.info('[TtsController] init success');
      return true;
    } catch (e) {
      let err: BusinessError = e as BusinessError;
      console.error('[TtsController] init failed: ' + err.code.toString() + ' ' + err.message);
      return false;
    }
  }

  async speak(text: string): Promise<boolean> {
    if (!this.engine) {
      let ok: boolean = await this.init();
      if (!ok) {
        return false;
      }
    }
    try {
      this.currentRequestId = 'req_' + Date.now().toString();
      let speakExtraParam: Record<string, Object> = {
        'queueMode': 0,
        'speed': 1,
        'volume': 2,
        'pitch': 1,
        'languageContext': 'zh-CN',
        'audioType': 'pcm',
        'soundChannel': 3,
        'playType': 1
      };
      let speakParams: textToSpeech.SpeakParams = {
        requestId: this.currentRequestId,
        extraParams: speakExtraParam
      };
      this.engine!.speak(text, speakParams);
      return true;
    } catch (e) {
      let err: BusinessError = e as BusinessError;
      console.error('[TtsController] speak failed: ' + err.code.toString() + ' ' + err.message);
      return false;
    }
  }

  stop(): void {
    if (this.engine) {
      try {
        this.engine.stop();
      } catch (e) {
        console.error('[TtsController] stop failed: ' + (e as Error).message);
      }
      this.updateState('idle');
    }
  }

  shutdown(): void {
    if (this.engine) {
      try {
        this.engine.shutdown();
      } catch (e) {
        console.error('[TtsController] shutdown failed: ' + (e as Error).message);
      }
      this.engine = null;
      this.updateState('idle');
    }
  }
}
