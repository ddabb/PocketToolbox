import { textToSpeech } from '@kit.CoreSpeechKit';
import { BusinessError } from '@kit.BasicServicesKit';

export type TtsState = 'idle' | 'speaking' | 'paused';
export type TtsErrorKind = 'init' | 'speak';

export class TtsController {
  private static readonly INIT_TIMEOUT_MS: number = 5000;
  private engine: textToSpeech.TextToSpeechEngine | null = null;
  private engineTask: Promise<boolean> | null = null;
  private stateCallback: ((state: TtsState) => void) | null = null;
  private completeCallback: (() => void) | null = null;
  private errorCallback: ((code: number, message: string, kind: TtsErrorKind) => void) | null = null;
  private segmentCallback: ((index: number, total: number) => void) | null = null;
  private currentRequestId: string = '';
  private currentState: TtsState = 'idle';
  private initPromise: Promise<boolean> | null = null;
  private initFailed: boolean = false;
  private generation: number = 0;
  private watchdogId: number = -1;
  private segments: string[] = [];
  private segmentIndex: number = 0;
  private segmentedMode: boolean = false;
  private speed: number = 1;

  setSpeed(speed: number): void {
    let clamped: number = speed;
    if (clamped < 0.5) {
      clamped = 0.5;
    }
    if (clamped > 2) {
      clamped = 2;
    }
    this.speed = clamped;
  }

  getSpeed(): number {
    return this.speed;
  }

  startFrom(index: number): boolean {
    if (!this.segmentedMode || index < 0 || index >= this.segments.length || !this.engine) {
      return false;
    }
    if (this.currentState === 'speaking') {
      this.generation++;
      this.currentRequestId = '';
      this.clearWatchdog();
      try {
        this.engine.stop();
      } catch (e) {
        console.error('[TtsController] startFrom stop failed: ' + (e as Error).message);
      }
    }
    this.segmentIndex = index;
    this.updateState('speaking');
    return this.startSpeak(this.segments[index]);
  }

  onStateChange(callback: (state: TtsState) => void): void {
    this.stateCallback = callback;
  }

  onComplete(callback: () => void): void {
    this.completeCallback = callback;
  }

  onTtsError(callback: (code: number, message: string, kind: TtsErrorKind) => void): void {
    this.errorCallback = callback;
  }

  onSegmentChange(callback: (index: number, total: number) => void): void {
    this.segmentCallback = callback;
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

  private failSpeak(code: number, message: string, kind: TtsErrorKind): void {
    this.clearWatchdog();
    this.currentRequestId = '';
    this.updateState('idle');
    if (this.errorCallback) {
      this.errorCallback(code, message, kind);
    }
  }

  private notifySegmentChange(): void {
    if (this.segmentCallback && this.segmentedMode) {
      this.segmentCallback(this.segmentIndex, this.segments.length);
    }
  }

  init(): Promise<boolean> {
    if (this.engine) {
      return Promise.resolve(true);
    }
    if (this.initFailed) {
      return Promise.resolve(false);
    }
    if (this.initPromise === null) {
      console.info('[TtsController] init: creating doInit');
      this.initPromise = this.doInit();
    }
    return this.initPromise;
  }

  private async doInit(): Promise<boolean> {
    console.info('[TtsController] doInit enter');
    let task: Promise<boolean> | null = this.engineTask;
    if (task === null) {
      this.engineTask = this.createEngineWithListener();
      task = this.engineTask;
    }
    if (task === null) {
      this.initPromise = null;
      return false;
    }
    let finalTask: Promise<boolean> = task;
    return new Promise<boolean>((resolve: (value: boolean) => void) => {
      let settled: boolean = false;
      let timerId: number = setTimeout(() => {
        if (settled) {
          return;
        }
        settled = true;
        console.error('[TtsController] init timed out after ' + TtsController.INIT_TIMEOUT_MS.toString() + 'ms');
        this.initPromise = null;
        this.initFailed = true;
        resolve(false);
      }, TtsController.INIT_TIMEOUT_MS);
      finalTask.then((ok: boolean) => {
        if (settled) {
          return;
        }
        settled = true;
        clearTimeout(timerId);
        console.info('[TtsController] engine task settled: ' + ok.toString());
        if (!ok) {
          this.initPromise = null;
        }
        resolve(ok);
      });
    });
  }

  private async createEngineWithListener(): Promise<boolean> {
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
          if (response.type === 0) {
            return;
          }
          this.clearWatchdog();
          this.currentRequestId = '';
          if (this.segmentedMode) {
            this.segmentIndex++;
            if (this.segmentIndex < this.segments.length) {
              this.startSpeak(this.segments[this.segmentIndex]);
              return;
            }
          }
          this.updateState('idle');
          if (this.completeCallback) {
            this.completeCallback();
          }
        },
        onStop: (requestId: string, response: textToSpeech.StopResponse) => {
          console.info('[TtsController] onStop: ' + requestId);
          if (this.isCurrentRequest(requestId)) {
            this.clearWatchdog();
            this.currentRequestId = '';
          }
        },
        onData: (requestId: string, audio: ArrayBuffer, response: textToSpeech.SynthesisResponse) => {
        },
        onError: (requestId: string, errorCode: number, errorMessage: string) => {
          console.error('[TtsController] onError: ' + requestId + ', code=' + errorCode.toString() + ', msg=' + errorMessage);
          if (this.isCurrentRequest(requestId) || this.currentState === 'speaking') {
            this.failSpeak(errorCode, errorMessage, 'speak');
          }
        }
      };
      engine.setListener(listener);
      this.engine = engine;
      this.initFailed = false;
      console.info('[TtsController] init success');
      return true;
    } catch (e) {
      let err: BusinessError = e as BusinessError;
      console.error('[TtsController] init failed: ' + err.code.toString() + ' ' + err.message);
      this.engineTask = null;
      this.initPromise = null;
      return false;
    }
  }

  async speakSegmented(segments: string[]): Promise<boolean> {
    console.info('[TtsController] speakSegmented called, segments=' + segments.length.toString());
    if (segments.length === 0) {
      return false;
    }
    let gen: number = this.generation;
    if (!this.engine) {
      let ok: boolean = await this.init();
      if (!ok) {
        this.failSpeak(-1, 'engine init failed', 'init');
        return false;
      }
      if (gen !== this.generation) {
        return true;
      }
    }
    this.segmentedMode = true;
    this.segments = segments;
    this.segmentIndex = 0;
    return this.startSpeak(segments[0]);
  }

  private startSpeak(text: string): boolean {
    try {
      this.currentRequestId = 'req_' + Date.now().toString() + '_' +
        Math.floor(Math.random() * 1000000).toString();
      let speakExtraParam: Record<string, Object> = {
        'queueMode': 1,
        'speed': this.speed,
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
      this.notifySegmentChange();
      let gen: number = this.generation;
      this.watchdogId = setTimeout(() => {
        this.watchdogId = -1;
        if (this.currentRequestId !== '' && gen === this.generation) {
          console.error('[TtsController] watchdog: no onStart within 6s');
          this.failSpeak(0, 'TTS no response timeout', 'speak');
        }
      }, 6000);
      return true;
    } catch (e) {
      let err: BusinessError = e as BusinessError;
      console.error('[TtsController] speak failed: ' + err.code.toString() + ' ' + err.message);
      this.failSpeak(err.code, err.message, 'speak');
      return false;
    }
  }

  pause(): void {
    if (this.currentState !== 'speaking') {
      return;
    }
    this.generation++;
    this.currentRequestId = '';
    this.clearWatchdog();
    if (this.engine) {
      try {
        this.engine.stop();
      } catch (e) {
        console.error('[TtsController] pause stop failed: ' + (e as Error).message);
      }
    }
    this.updateState('paused');
  }

  async resume(): Promise<boolean> {
    if (this.currentState !== 'paused') {
      return false;
    }
    if (!this.segmentedMode || this.segmentIndex >= this.segments.length) {
      return false;
    }
    if (!this.engine) {
      let ok: boolean = await this.init();
      if (!ok) {
        this.failSpeak(-1, 'engine init failed', 'init');
        return false;
      }
    }
    return this.startSpeak(this.segments[this.segmentIndex]);
  }

  stop(): void {
    this.generation++;
    this.currentRequestId = '';
    this.clearWatchdog();
    this.segmentedMode = false;
    this.segments = [];
    this.segmentIndex = 0;
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
    this.segmentedMode = false;
    this.segments = [];
    this.segmentIndex = 0;
    if (this.engine) {
      try {
        this.engine.shutdown();
      } catch (e) {
        console.error('[TtsController] shutdown failed: ' + (e as Error).message);
      }
      this.engine = null;
    }
    this.engineTask = null;
    this.initPromise = null;
    this.initFailed = false;
    this.updateState('idle');
  }
}

const SEGMENT_SUB_SPLIT_THRESHOLD: number = 15;

function splitLongSegment(segment: string): string[] {
  if (segment.length <= SEGMENT_SUB_SPLIT_THRESHOLD) {
    return [segment];
  }
  let subs: string[] = [];
  let current: string = '';
  for (let i: number = 0; i < segment.length; i++) {
    let ch: string = segment[i];
    current += ch;
    if (ch === '\uFF0C') {
      subs.push(current);
      current = '';
    }
  }
  let tail: string = current.trim();
  if (tail.length > 0) {
    if (subs.length > 0 && tail.length <= 3) {
      let last: number = subs.length - 1;
      subs[last] = subs[last] + tail;
    } else {
      subs.push(tail);
    }
  }
  return subs;
}

export function splitToSegments(text: string): string[] {
  let result: string[] = [];
  let current: string = '';
  for (let i: number = 0; i < text.length; i++) {
    let ch: string = text[i];
    current += ch;
    if (ch === '\n' || ch === '\u3002' || ch === '\uFF01' || ch === '\uFF1F' || ch === '\uFF1B') {
      let trimmed: string = current.trim();
      if (trimmed.length > 0) {
        let subs: string[] = splitLongSegment(trimmed);
        for (let j: number = 0; j < subs.length; j++) {
          result.push(subs[j]);
        }
      }
      current = '';
    }
  }
  let remaining: string = current.trim();
  if (remaining.length > 0) {
    let subs: string[] = splitLongSegment(remaining);
    for (let j: number = 0; j < subs.length; j++) {
      result.push(subs[j]);
    }
  }
  return result;
}
