import { describe, it, expect } from '@ohos/hypium';
import {
  OverlayItem,
  overlayColorToArgb,
  clampOverlayFont,
  clampOverlayPos,
  normalizeOverlayRotation,
  overlayFontPx,
  OVERLAY_REF_HEIGHT,
  OVERLAY_KIND_TEXT,
  OVERLAY_KIND_STICKER
} from '../main/ets/core/gif/GifOverlayModel';

export default function gifOverlayModelTest() {
  describe('GifOverlayModelTest', () => {
    it('overlayColorToArgb_supportsRRGGBB', 0, () => {
      expect(overlayColorToArgb('#FF0000')).assertEqual(0xFFFF0000);
      expect(overlayColorToArgb('#00FF00')).assertEqual(0xFF00FF00);
      expect(overlayColorToArgb('#FFFFFF')).assertEqual(0xFFFFFFFF);
      expect(overlayColorToArgb('#000000')).assertEqual(0xFF000000);
    });

    it('overlayColorToArgb_supportsShortRGB', 0, () => {
      expect(overlayColorToArgb('#F00')).assertEqual(0xFFFF0000);
      expect(overlayColorToArgb('#0A0')).assertEqual(0xFF00AA00);
    });

    it('overlayColorToArgb_fallsBackToWhite', 0, () => {
      expect(overlayColorToArgb('red')).assertEqual(0xFFFFFFFF);
      expect(overlayColorToArgb('FF0000')).assertEqual(0xFFFFFFFF);
      expect(overlayColorToArgb('#ZZZZZZ')).assertEqual(0xFFFFFFFF);
      expect(overlayColorToArgb('#12')).assertEqual(0xFFFFFFFF);
      expect(overlayColorToArgb('')).assertEqual(0xFFFFFFFF);
    });

    it('clampOverlayFont_textRange', 0, () => {
      expect(clampOverlayFont(OVERLAY_KIND_TEXT, 5)).assertEqual(12);
      expect(clampOverlayFont(OVERLAY_KIND_TEXT, 100)).assertEqual(72);
      expect(clampOverlayFont(OVERLAY_KIND_TEXT, 40)).assertEqual(40);
      expect(clampOverlayFont(OVERLAY_KIND_TEXT, 32.6)).assertEqual(33);
    });

    it('clampOverlayFont_stickerRange', 0, () => {
      expect(clampOverlayFont(OVERLAY_KIND_STICKER, 5)).assertEqual(12);
      expect(clampOverlayFont(OVERLAY_KIND_STICKER, 300)).assertEqual(160);
      expect(clampOverlayFont(OVERLAY_KIND_STICKER, 100)).assertEqual(100);
    });

    it('clampOverlayPos_clampsToUnitRange', 0, () => {
      expect(clampOverlayPos(-0.5)).assertEqual(0);
      expect(clampOverlayPos(1.5)).assertEqual(1);
      expect(clampOverlayPos(0.3)).assertEqual(0.3);
    });

    it('normalizeOverlayRotation_wrapsTo360', 0, () => {
      expect(normalizeOverlayRotation(-15)).assertEqual(345);
      expect(normalizeOverlayRotation(375)).assertEqual(15);
      expect(normalizeOverlayRotation(720)).assertEqual(0);
      expect(normalizeOverlayRotation(90)).assertEqual(90);
    });

    it('overlayFontPx_scalesByRefHeight', 0, () => {
      expect(OVERLAY_REF_HEIGHT).assertEqual(480);
      expect(overlayFontPx(48, 480)).assertEqual(48);
      expect(overlayFontPx(48, 960)).assertEqual(96);
      expect(overlayFontPx(48, 240)).assertEqual(24);
      expect(overlayFontPx(1, 10)).assertEqual(1);
    });

    it('OverlayItem_fields', 0, () => {
      let item: OverlayItem = new OverlayItem(OVERLAY_KIND_TEXT, '你好', '#FFFFFF', 32, 0.5, 0.5, -30);
      expect(item.kind).assertEqual(OVERLAY_KIND_TEXT);
      expect(item.text).assertEqual('你好');
      expect(item.color).assertEqual('#FFFFFF');
      expect(item.fontPx).assertEqual(32);
      expect(item.x).assertEqual(0.5);
      expect(item.y).assertEqual(0.5);
      expect(item.rotation).assertEqual(-30);
    });
  });
}
