import recordingConfigTest from './RecordingConfig.test';
import fileSizeUtilsTest from './FileSizeUtils.test';
import recordingRepositoryTest from './RecordingRepository.test';
import timeUtilsTest from './TimeUtils.test';
import waveFileUtilsTest from './WaveFileUtils.test';
import waveformUtilsTest from './WaveformUtils.test';
import harmonyThemeTest from './HarmonyTheme.test';
import uiMaterialTest from './UiMaterial.test';
import waveformCurveTest from './WaveformCurve.test';

export default function testsuite() {
  recordingConfigTest();
  fileSizeUtilsTest();
  recordingRepositoryTest();
  timeUtilsTest();
  waveFileUtilsTest();
  waveformUtilsTest();
  harmonyThemeTest();
  uiMaterialTest();
  waveformCurveTest();
}
