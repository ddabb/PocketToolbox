import { textToSpeech } from '@kit.CoreSpeechKit';
import { BusinessError } from '@kit.BasicServicesKit';

export type TtsState = 'idle' | 'speaking' | 'stopped';

export class TtsController {
  private engine: textToSpeech.TextToSpeechEngine | null = null;
  private stateCallback: ((state: TtsState) => void) | null = null;
  private completeCallback: (() => void) | null = null;
  private errorCallback: ((code: number, message: string) => void) | null = null;
  private currentRequestId: string = '';
  private currentState: TtsState = 'idle';
  private initPromise: Promise<boolean> | null = null;
  private generation: number = 0;
  private watchdogId: number = -1;

  onStateChange(callback: (state: TtsState) => void): void {
    this.stateCallback = callback;
  }

  onComplete(callback: () => void): void {
    this.completeCallback = callback;
  }

  onTtsError(callback: (code: number, message: string) => void): void {
    this.errorCallback = callback;
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

  private isCurrentRequest(requestId: string): boolean {
    return this.currentRequestId !== '' && requestId === this.currentRequestId;
  }

  private clearWatchdog(): void {
    if (this.watchdogId >= 0) {
      clearTimeout(this.watchdogId);
      this.watchdogId = -1;
    }
  }

  private failSpeak(code: number, message: string): void {
    this.clearWatchdog();
    this.currentRequestId = '';
    if (this.currentState === 'speaking') {
      this.updateState('idle');
    }
    if (this.errorCallback) {
      this.errorCallback(code, message);
    }
  }

  init(): Promise<boolean> {
    if (this.engine) {
      return Promise.resolve(true);
    }
    if (this.initPromise === null) {
      this.initPromise = this.doInit();
    }
    return this.initPromise;
  }

  private async doInit(): Promise<boolean> {
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
      let engine: textToSpeech.TextToSpeechEngine = await textToSpeech.createEngine(initParams);
      let listener: textToSpeech.SpeakListener = {
        onStart: (requestId: string, response: textToSpeech.StartResponse) => {
          console.info('[TtsController] onStart: ' + requestId);
          if (this.isCurrentRequest(requestId)) {
            this.clearWatchdog();
            this.updateState('speaking');
          }
        },
        onComplete: (requestId: string, response: textToSpeech.CompleteResponse) => {
          console.info('[TtsController] onComplete: ' + requestId + ', type=' + response.type.toString());
          if (!this.isCurrentRequest(requestId)) {
            return;
          }
          this.clearWatchdog();
          this.currentRequestId = '';
          this.updateState('idle');
          if (response.type === 1 && this.completeCallback) {
            this.completeCallback();
          }
        },
        onStop: (requestId: string, response: textToSpeech.StopResponse) => {
          console.info('[TtsController] onStop: ' + requestId);
          if (this.isCurrentRequest(requestId)) {
            this.clearWatchdog();
            this.currentRequestId = '';
            this.updateState('idle');
          }
        },
        onData: (requestId: string, audio: ArrayBuffer, response: textToSpeech.SynthesisResponse) => {
        },
        onError: (requestId: string, errorCode: number, errorMessage: string) => {
          console.error('[TtsController] onError: ' + requestId + ', code=' + errorCode.toString() + ', msg=' + errorMessage);
          if (this.isCurrentRequest(requestId) || this.currentState === 'speaking') {
            this.failSpeak(errorCode, errorMessage);
          }
        }
      };
      engine.setListener(listener);
      this.engine = engine;
      console.info('[TtsController] init success');
      return true;
    } catch (e) {
      let err: BusinessError = e as BusinessError;
      console.error('[TtsController] init failed: ' + err.code.toString() + ' ' + err.message);
      this.initPromise = null;
      return false;
    }
  }

  async speak(text: string): Promise<boolean> {
    let gen: number = this.generation;
    this.updateState('speaking');
    if (!this.engine) {
      let ok: boolean = await this.init();
      if (!ok) {
        this.failSpeak(-1, 'engine init failed');
        return false;
      }
      if (gen !== this.generation) {
        this.updateState('idle');
        return true;
      }
    }
    try {
      this.currentRequestId = 'req_' + Date.now().toString() + '_' +
        Math.floor(Math.random() * 1000000).toString();
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
      this.clearWatchdog();
      this.watchdogId = setTimeout(() => {
        this.watchdogId = -1;
        if (this.currentState === 'speaking' && gen === this.generation) {
          console.error('[TtsController] watchdog: no onStart within 6s');
          this.failSpeak(0, 'TTS no response timeout');
        }
      }, 6000);
      return true;
    } catch (e) {
      let err: BusinessError = e as BusinessError;
      console.error('[TtsController] speak failed: ' + err.code.toString() + ' ' + err.message);
      this.failSpeak(err.code, err.message);
      return false;
    }
  }

  stop(): void {
    this.generation++;
    this.currentRequestId = '';
    this.clearWatchdog();
    if (this.engine) {
      try {
        this.engine.stop();
      } catch (e) {
        console.error('[TtsController] stop failed: ' + (e as Error).message);
      }
    }
    this.updateState('idle');
  }

  shutdown(): void {
    this.generation++;
    this.currentRequestId = '';
    this.clearWatchdog();
    if (this.engine) {
      try {
        this.engine.shutdown();
      } catch (e) {
        console.error('[TtsController] shutdown failed: ' + (e as Error).message);
      }
      this.engine = null;
    }
    this.initPromise = null;
    this.updateState('idle');
  }
}
