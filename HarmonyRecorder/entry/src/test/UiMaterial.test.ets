import { describe, expect, it } from '@ohos/hypium';
import { hdsMaterial } from '@kit.UIDesignKit';
import { MaterialRole, UiCapabilityProfile } from '../main/ets/utils/MaterialTheme';
import { WaveformMotion } from '../main/ets/utils/WaveformMotion';
import { RecordingState } from '../main/ets/models/RecordingTypes';
import { ResponsiveLayout } from '../main/ets/utils/ResponsiveLayout';

export default function uiMaterialTest() {
  describe('uiMaterialTest', () => {
    it('separates API24 HDS support from API26 uiMaterial support', 0, () => {
      const profile = new UiCapabilityProfile(24, [hdsMaterial.MaterialType.IMMERSIVE]);
      expect(profile.supportsImmersiveMaterial).assertTrue();
      expect(profile.supportsNativeUiMaterial).assertFalse();
      expect(profile.materialFor(MaterialRole.CONTROL).materialType).assertEqual(hdsMaterial.MaterialType.IMMERSIVE);
      expect(profile.materialFor(MaterialRole.NAVIGATION).materialType).assertEqual(hdsMaterial.MaterialType.ADAPTIVE);
    });
    it('does not infer material support from the API version alone', 0, () => {
      const profile = new UiCapabilityProfile(26, []);
      expect(profile.materialFor(MaterialRole.STAGE).materialType).assertEqual(hdsMaterial.MaterialType.ADAPTIVE);
      expect(profile.materialFor(MaterialRole.STAGE).materialLevel).assertEqual(hdsMaterial.MaterialLevel.SMOOTH);
      expect(profile.supportsImmersiveMaterial).assertFalse();
      expect(profile.supportsNativeUiMaterial).assertFalse();
    });
    it('enables native material capability only on supported API26 devices', 0, () => {
      const profile = new UiCapabilityProfile(26, [hdsMaterial.MaterialType.IMMERSIVE]);
      expect(profile.supportsNativeUiMaterial).assertTrue();
      expect(profile.materialFor(MaterialRole.CONTROL).materialType).assertEqual(hdsMaterial.MaterialType.IMMERSIVE);
      const adaptive = new UiCapabilityProfile(26, [hdsMaterial.MaterialType.ADAPTIVE]);
      expect(adaptive.materialFor(MaterialRole.CONTROL).materialType).assertEqual(hdsMaterial.MaterialType.ADAPTIVE);
    });
    it('runs waveform motion only during visible foreground recording', 0, () => {
      expect(WaveformMotion.shouldAnimate(RecordingState.RECORDING, true, true)).assertTrue();
      expect(WaveformMotion.shouldAnimate(RecordingState.RECORDING, false, true)).assertFalse();
      expect(WaveformMotion.shouldAnimate(RecordingState.RECORDING, true, false)).assertFalse();
      expect(WaveformMotion.shouldAnimate(RecordingState.PAUSED, true, true)).assertFalse();
      expect(WaveformMotion.shouldAnimate(RecordingState.STOPPED, true, true)).assertFalse();
      expect(WaveformMotion.shouldAnimate(RecordingState.IDLE, true, true)).assertFalse();
      expect(WaveformMotion.shouldAnimate(RecordingState.RECORDING, true, true, true)).assertFalse();
      expect(WaveformMotion.showsHistory(RecordingState.PAUSED)).assertTrue();
      expect(WaveformMotion.showsHistory(RecordingState.STOPPED)).assertFalse();
    });
    it('caps the visual cadence and scrolling interpolation', 0, () => {
      expect(WaveformMotion.EXPECTED_FRAME_RATE).assertEqual(60);
      expect(WaveformMotion.MIN_FRAME_RATE < WaveformMotion.EXPECTED_FRAME_RATE).assertTrue();
      expect(WaveformMotion.scrollPhase(-1)).assertEqual(0);
      expect(WaveformMotion.scrollPhase(45)).assertEqual(0.5);
      expect(WaveformMotion.scrollPhase(200)).assertEqual(1);
    });
    it('keeps tablet containers relative to their available viewport', 0, () => {
      expect(ResponsiveLayout.contentWidth(true)).assertEqual('100%');
      expect(ResponsiveLayout.horizontalPadding(true)).assertEqual(24);
      expect(ResponsiveLayout.horizontalPadding(false)).assertEqual(16);
    });
  });
}
