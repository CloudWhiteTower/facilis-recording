import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';

export enum ThemeMode {
  LIGHT = 0,
  DARK = 1
}

export class HarmonyPalette {
  public readonly pageBackground: string;
  public readonly surface: string;
  public readonly onPrimary: string;
  public readonly surfaceSubtle: string;
  public readonly primary: string;
  public readonly primarySubtle: string;
  public readonly primaryBorder: string;
  public readonly recording: string;
  public readonly danger: string;
  public readonly dangerSubtle: string;
  public readonly textPrimary: string;
  public readonly textSecondary: string;
  public readonly textTertiary: string;
  public readonly divider: string;
  public readonly waveformIdle: string;
  public readonly success: string;
  public readonly warning: string;
  public readonly shadow: string;

  constructor(
    pageBackground: string,
    surface: string,
    onPrimary: string,
    surfaceSubtle: string,
    primary: string,
    primarySubtle: string,
    primaryBorder: string,
    recording: string,
    danger: string,
    dangerSubtle: string,
    textPrimary: string,
    textSecondary: string,
    textTertiary: string,
    divider: string,
    waveformIdle: string,
    success: string,
    warning: string,
    shadow: string
  ) {
    this.pageBackground = pageBackground;
    this.surface = surface;
    this.onPrimary = onPrimary;
    this.surfaceSubtle = surfaceSubtle;
    this.primary = primary;
    this.primarySubtle = primarySubtle;
    this.primaryBorder = primaryBorder;
    this.recording = recording;
    this.danger = danger;
    this.dangerSubtle = dangerSubtle;
    this.textPrimary = textPrimary;
    this.textSecondary = textSecondary;
    this.textTertiary = textTertiary;
    this.divider = divider;
    this.waveformIdle = waveformIdle;
    this.success = success;
    this.warning = warning;
    this.shadow = shadow;
  }
}

export class ThemeStore {
  static readonly MODE_KEY: string = 'harmony_recorder_theme_mode';
  private static initialized: boolean = false;

  static initialize(): void {
    if (!ThemeStore.initialized) {
      PersistentStorage.persistProp(ThemeStore.MODE_KEY, ThemeMode.LIGHT);
      ThemeStore.initialized = true;
    }
  }

  static toggle(mode: number): void {
    const nextMode = mode === ThemeMode.DARK ? ThemeMode.LIGHT : ThemeMode.DARK;
    AppStorage.setOrCreate(ThemeStore.MODE_KEY, nextMode);
  }

  static setMode(mode: ThemeMode): void {
    AppStorage.setOrCreate(ThemeStore.MODE_KEY, mode);
  }

  static applySystemMode(context: common.UIAbilityContext, mode: number): void {
    try {
      const colorMode = mode === ThemeMode.DARK ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK :
        ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
      context.getApplicationContext().setColorMode(colorMode);
      window.getLastWindow(context).then((mainWindow: window.Window): void => {
        ThemeStore.applyWindowMode(mainWindow, mode);
      }).catch((error: Error): void => {
        console.warn(`Window not ready for theme: ${error.message}`);
      });
    } catch (error) {
      console.error(`Apply application color mode failed: ${String(error)}`);
    }
  }

  static applyWindowMode(mainWindow: window.Window, mode: number): void {
    const dark = mode === ThemeMode.DARK;
    try {
      mainWindow.setWindowBackgroundColor(dark ? '#15110E' : '#FFF9F3');
    } catch (error) {
      console.warn(`Window background update failed: ${String(error)}`);
    }
    mainWindow.setWindowSystemBarProperties({
      statusBarColor: '#00000000', navigationBarColor: '#00000000',
      statusBarContentColor: dark ? '#F7EEE7' : '#2A1D13',
      navigationBarContentColor: dark ? '#F7EEE7' : '#2A1D13',
      isStatusBarLightIcon: dark, isNavigationBarLightIcon: dark
    }).catch((error: Error): void => {
      console.warn(`System bars update failed: ${error.message}`);
    });
  }
}

export class HarmonyTheme {
  private static readonly lightPalette: HarmonyPalette = new HarmonyPalette(
    '#FFF9F3', '#FFFFFF', '#FFFFFF', '#FFF3E6', '#C85A10', '#FFF0DD', '#F2C18D', '#C85A10',
    '#C54747', '#FFF0F0', '#2A1D13', '#74675D', '#9A8B7E', '#E9DED2', '#A98A6C', '#2E7A56',
    '#9B6700', '#121D3240'
  );
  private static readonly darkPalette: HarmonyPalette = new HarmonyPalette(
    '#15110E', '#211A14', '#2A1708', '#2B211A', '#FFB457', '#4C321A', '#7B5025', '#FFB457',
    '#FF8881', '#4A2727', '#F7EEE7', '#D2C2B4', '#A99889', '#3C3026', '#C5A17C', '#82C99A',
    '#FFD178', '#00000066'
  );

  static palette(mode: number): HarmonyPalette {
    return mode === ThemeMode.DARK ? HarmonyTheme.darkPalette : HarmonyTheme.lightPalette;
  }

}

export class HarmonyTokens {
  static glassHighlight(): Resource {
    return $r('app.color.glass_highlight');
  }

  static controlLight(): Resource {
    return $r('app.color.control_light');
  }

  static pageBackground(): Resource {
    return $r('app.color.page_background');
  }

  static surface(): Resource {
    return $r('app.color.surface');
  }

  static glassSurface(): Resource {
    return $r('app.color.surface_glass');
  }

  static surfaceSubtle(): Resource {
    return $r('app.color.surface_subtle');
  }

  static primary(): Resource {
    return $r('app.color.primary');
  }

  static onPrimary(): Resource {
    return $r('app.color.on_primary');
  }

  static primarySubtle(): Resource {
    return $r('app.color.primary_subtle');
  }

  static primaryBorder(): Resource {
    return $r('app.color.primary_border');
  }

  static primaryGlow(): Resource {
    return $r('app.color.primary_glow');
  }

  static danger(): Resource {
    return $r('app.color.danger');
  }

  static dangerSubtle(): Resource {
    return $r('app.color.danger_subtle');
  }

  static textPrimary(): Resource {
    return $r('app.color.text_primary');
  }

  static textSecondary(): Resource {
    return $r('app.color.text_secondary');
  }

  static textTertiary(): Resource {
    return $r('app.color.text_tertiary');
  }

  static divider(): Resource {
    return $r('app.color.divider');
  }

  static waveformIdle(): Resource {
    return $r('app.color.waveform_idle');
  }

  static shadow(): Resource {
    return $r('app.color.shadow');
  }
}
