/**
 * 文案海报 T12 聊天头像存取（1.4.8 M2）：
 * PhotoViewPicker 选图 → 立即拷贝沙箱 filesDir/poster_avatar（picker URI 短授权不可依赖）；
 * 拷贝四路径兜底：临时授权直读（真机标准）→ URI→沙箱直拷（官方 FAQ 推荐）→ 媒体库按 URI 查资产请求数据（binder 管道，file-manager 挂载失效环境兜底）→ 图片框架解码重落盘；
 * content.avatarUri 存沙箱纯路径（渲染处加 file:// 前缀）。
 * 头像文件不做自动清理（docs/1.4.8开发计划 §8-4）；更换/移除时由页面同步删旧文件。
 */
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { dataSharePredicates } from '@kit.ArkData';
import { fileIo as fs } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { common } from '@kit.AbilityKit';

/** 媒体资源数据回调（requestImageData 就绪时由系统回调，转写沙箱目标文件；箭头属性防 this 丢失） */
class AvatarAssetHandler implements photoAccessHelper.MediaAssetDataHandler<ArrayBuffer> {
  private readonly dest: string;
  private readonly finish: (ok: boolean) => void;

  constructor(dest: string, finish: (ok: boolean) => void) {
    this.dest = dest;
    this.finish = finish;
  }

  onDataPrepared = (data: ArrayBuffer): void => {
    let dst: fs.File | undefined = undefined;
    try {
      dst = fs.openSync(this.dest, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.writeSync(dst.fd, data);
    } catch (e) {
      console.warn('[CopyPoster] avatar asset write failed: ' + (e as Error).message);
      this.finish(false);
      return;
    } finally {
      if (dst !== undefined) {
        fs.closeSync(dst.fd);
      }
    }
    this.finish(true);
  };
}

export class PosterAvatarStore {
  private static readonly DIR_NAME: string = 'poster_avatar';

  private static dir(context: common.UIAbilityContext): string {
    return context.filesDir + '/' + PosterAvatarStore.DIR_NAME;
  }

  /** 文件是否可达（accessSync 返回 boolean 不抛缺失异常；restore 历史时校验，失联回退首字渲染） */
  static exists(path: string): boolean {
    try {
      return fs.accessSync(path);
    } catch (e) {
      return false;
    }
  }

  /** 删除沙箱头像文件（不存在/失联静默，调用方语义即「确保不再引用」） */
  static remove(path: string): void {
    try {
      fs.unlinkSync(path);
    } catch (e) {
      console.error('[CopyPoster] remove avatar failed: ' + (e as Error).message);
    }
  }

  /** 唤起系统相册选图并拷贝入沙箱；取消或失败返回 ''（页面据此保持原头像不变） */
  static async pick(context: common.UIAbilityContext): Promise<string> {
    let dest: string = '';
    try {
      let picker: photoAccessHelper.PhotoViewPicker = new photoAccessHelper.PhotoViewPicker();
      let result: photoAccessHelper.PhotoSelectResult = await picker.select({
        MIMEType: photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE,
        maxSelectNumber: 1,
      });
      if (result.photoUris.length === 0) {
        return '';
      }
      let uri: string = result.photoUris[0];
      let dir: string = PosterAvatarStore.dir(context);
      if (!PosterAvatarStore.exists(dir)) {
        fs.mkdirSync(dir, true);
      }
      let dot: number = uri.lastIndexOf('.');
      let slash: number = uri.lastIndexOf('/');
      let ext: string = dot > slash ? uri.substring(dot).toLowerCase() : '.jpg';
      if (ext.length < 2 || ext.length > 5) {
        ext = '.jpg';
      }
      dest = dir + '/avatar_' + Date.now().toString(36) + ext;
      let ok: boolean = PosterAvatarStore.copyByFd(uri, dest) && PosterAvatarStore.copied(dest);
      if (!ok) {
        ok = PosterAvatarStore.copyByUri(uri, dest) && PosterAvatarStore.copied(dest);
      }
      if (!ok) {
        ok = await PosterAvatarStore.copyByAsset(context, uri, dest) && PosterAvatarStore.copied(dest);
      }
      if (!ok) {
        ok = await PosterAvatarStore.copyByDecode(uri, dest) && PosterAvatarStore.copied(dest);
      }
      if (!ok) {
        throw new Error('copy avatar failed on all paths');
      }
      let size: number = 0;
      try {
        size = fs.statSync(dest).size;
      } catch (e) {
        console.warn('[CopyPoster] avatar stat failed: ' + (e as Error).message);
      }
      console.info('[CopyPoster] avatar ready: ' + dest + ' size=' + size.toString());
      return dest;
    } catch (e) {
      if (dest !== '') {
        PosterAvatarStore.remove(dest);
      }
      console.error('[CopyPoster] pick avatar failed: ' + (e as Error).message);
      return '';
    }
  }

  /** 拷贝门校验：目标存在且非 0 字节（防 fileIo 假成功产出空文件导致 Image 解码失败） */
  private static copied(dest: string): boolean {
    try {
      return fs.statSync(dest).size > 0;
    } catch (e) {
      return false;
    }
  }

  /** 路径1：picker 临时授权下直读 URI 拷贝（真机已验证的标准模式） */
  private static copyByFd(uri: string, dest: string): boolean {
    try {
      let src: fs.File = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      try {
        let dst: fs.File = fs.openSync(dest, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
        try {
          fs.copyFileSync(src.fd, dst.fd);
        } finally {
          fs.closeSync(dst.fd);
        }
      } finally {
        fs.closeSync(src.fd);
      }
      return true;
    } catch (e) {
      console.warn('[CopyPoster] avatar copyByFd failed: ' + (e as Error).message);
      return false;
    }
  }

  /** 路径2：URI→沙箱直拷（官方 FAQ 推荐的相册 URI 转沙箱方式，与 openSync 解析通道不同） */
  private static copyByUri(uri: string, dest: string): boolean {
    try {
      fs.copyFileSync(uri, dest);
      return true;
    } catch (e) {
      console.warn('[CopyPoster] avatar copyByUri failed: ' + (e as Error).message);
      return false;
    }
  }

  /** 路径3：媒体库按 URI 查资产后请求数据落盘（binder 管道，不依赖 file-manager 挂载；10s 超时保护） */
  private static async copyByAsset(context: common.UIAbilityContext, uri: string, dest: string): Promise<boolean> {
    return new Promise<boolean>((resolve) => {
      let done: boolean = false;
      let timerId: number = setTimeout(() => {
        if (!done) {
          done = true;
          console.warn('[CopyPoster] avatar copyByAsset timeout');
          resolve(false);
        }
      }, 10000);
      let finish = (ok: boolean): void => {
        if (!done) {
          done = true;
          clearTimeout(timerId);
          resolve(ok);
        }
      };
      let run = async (): Promise<void> => {
        let fetchResult: photoAccessHelper.FetchResult<photoAccessHelper.PhotoAsset> | undefined = undefined;
        try {
          let helper: photoAccessHelper.PhotoAccessHelper = photoAccessHelper.getPhotoAccessHelper(context);
          let predicates: dataSharePredicates.DataSharePredicates = new dataSharePredicates.DataSharePredicates();
          predicates.equalTo(photoAccessHelper.PhotoKeys.URI, uri);
          let fetchOptions: photoAccessHelper.FetchOptions = {
            fetchColumns: [],
            predicates: predicates,
          };
          let fr: photoAccessHelper.FetchResult<photoAccessHelper.PhotoAsset> = await helper.getAssets(fetchOptions);
          fetchResult = fr;
          let asset: photoAccessHelper.PhotoAsset = await fr.getFirstObject();
          let options: photoAccessHelper.RequestOptions = {
            deliveryMode: photoAccessHelper.DeliveryMode.HIGH_QUALITY_MODE,
          };
          let handler: AvatarAssetHandler = new AvatarAssetHandler(dest, finish);
          await photoAccessHelper.MediaAssetManager.requestImageData(context, asset, options, handler);
        } catch (e) {
          console.warn('[CopyPoster] avatar copyByAsset failed: ' + (e as Error).message);
          finish(false);
        } finally {
          if (fetchResult !== undefined) {
            fetchResult.close();
          }
        }
      };
      run();
    });
  }

  /** 路径4：直读失败时由图片框架按 URI 解码后重新落盘（授权异常环境兜底，输出统一为 png） */
  private static async copyByDecode(uri: string, dest: string): Promise<boolean> {
    let source: image.ImageSource | undefined = undefined;
    let pm: image.PixelMap | undefined = undefined;
    let packer: image.ImagePacker | undefined = undefined;
    try {
      source = image.createImageSource(uri);
      pm = await source.createPixelMap();
      packer = image.createImagePacker();
      let packOpts: image.PackingOption = { format: 'image/png', quality: 100 };
      let data: ArrayBuffer = await packer.packToData(pm, packOpts);
      let dst: fs.File = fs.openSync(dest, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      try {
        fs.writeSync(dst.fd, data);
      } finally {
        fs.closeSync(dst.fd);
      }
      return true;
    } catch (e) {
      console.warn('[CopyPoster] avatar copyByDecode failed: ' + (e as Error).message);
      return false;
    } finally {
      if (packer !== undefined) {
        packer.release();
      }
      if (pm !== undefined) {
        pm.release();
      }
      if (source !== undefined) {
        source.release();
      }
    }
  }
}
