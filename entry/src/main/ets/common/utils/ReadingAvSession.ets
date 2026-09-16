import { avSession } from '@kit.AVSessionKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { Context, wantAgent } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';

export type SimpleCallback = () => void;

export class ReadingAvSession {
  private session: avSession.AVSession | null = null;
  private context: Context | null = null;
  private assetId: string = 'reading_tts';
  private playCallback: SimpleCallback = (): void => {
  };
  private pauseCallback: SimpleCallback = (): void => {
  };
  private nextCallback: SimpleCallback = (): void => {
  };
  private prevCallback: SimpleCallback = (): void => {
  };

  isActive(): boolean {
    return this.session !== null;
  }

  async start(context: Context, title: string,
    onPlay: SimpleCallback, onPause: SimpleCallback,
    onNext: SimpleCallback, onPrev: SimpleCallback): Promise<void> {
    this.playCallback = onPlay;
    this.pauseCallback = onPause;
    this.nextCallback = onNext;
    this.prevCallback = onPrev;
    if (this.session) {
      await this.updateTitle(title);
      return;
    }
    this.context = context;
    this.assetId = 'reading_' + Date.now().toString();
    try {
      let session: avSession.AVSession = await avSession.createAVSession(context, 'ReadingTTS', 'audio');
      this.session = session;
      session.on('play', (): void => {
        this.playCallback();
      });
      session.on('pause', (): void => {
        this.pauseCallback();
      });
      session.on('stop', (): void => {
        this.pauseCallback();
      });
      session.on('playNext', (): void => {
        this.nextCallback();
      });
      session.on('playPrevious', (): void => {
        this.prevCallback();
      });
      await session.setAVMetadata({
        assetId: this.assetId,
        title: title,
        artist: '解语珠玑 · 朗读清单'
      });
      await session.activate();
      console.info('[ReadingAvSession] session started');
    } catch (e) {
      let err: BusinessError = e as BusinessError;
      console.error('[ReadingAvSession] create session failed: ' + err.code.toString() + ' ' + err.message);
      this.session = null;
      return;
    }
    try {
      let agent = await wantAgent.getWantAgent({
        wants: [{
          bundleName: 'com.ddabb.toolbox',
          abilityName: 'EntryAbility'
        }],
        operationType: wantAgent.OperationType.START_ABILITIES,
        requestCode: 0
      });
      await backgroundTaskManager.startBackgroundRunning(context,
        backgroundTaskManager.BackgroundMode.AUDIO_PLAYBACK, agent);
      console.info('[ReadingAvSession] background running started');
    } catch (e) {
      let err: BusinessError = e as BusinessError;
      console.error('[ReadingAvSession] startBackgroundRunning failed: ' + err.code.toString() + ' ' + err.message);
    }
  }

  async updateTitle(title: string): Promise<void> {
    if (!this.session) {
      return;
    }
    try {
      await this.session.setAVMetadata({
        assetId: this.assetId,
        title: title,
        artist: '解语珠玑 · 朗读清单'
      });
    } catch (e) {
      console.error('[ReadingAvSession] updateTitle failed: ' + (e as Error).message);
    }
  }

  setPlaying(playing: boolean): void {
    if (!this.session) {
      return;
    }
    let state: avSession.AVPlaybackState = {
      state: playing ? avSession.PlaybackState.PLAYBACK_STATE_PLAY : avSession.PlaybackState.PLAYBACK_STATE_PAUSE
    };
    this.session.setAVPlaybackState(state).catch((err: BusinessError) => {
      console.error('[ReadingAvSession] setAVPlaybackState failed: ' + err.code.toString());
    });
  }

  async stop(): Promise<void> {
    if (this.session) {
      let session: avSession.AVSession = this.session;
      this.session = null;
      try {
        await session.destroy();
      } catch (e) {
        console.warn('[ReadingAvSession] destroy failed: ' + (e as Error).message);
      }
    }
    if (this.context) {
      try {
        await backgroundTaskManager.stopBackgroundRunning(this.context);
      } catch (e) {
        console.warn('[ReadingAvSession] stopBackgroundRunning failed: ' + (e as Error).message);
      }
      this.context = null;
    }
  }
}
