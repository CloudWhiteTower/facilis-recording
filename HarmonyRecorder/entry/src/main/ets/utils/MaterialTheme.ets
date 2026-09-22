import { deviceInfo } from '@kit.BasicServicesKit';
import { hdsMaterial, SystemMaterialParams } from '@kit.UIDesignKit';
import { HarmonyTokens, ThemeMode } from './HarmonyTheme';

export enum MaterialRole {
  NAVIGATION = 'navigation',
  CONTROL = 'control',
  OVERLAY = 'overlay',
  STAGE = 'stage'
}

export class UiCapabilityProfile {
  public readonly apiVersion: number;
  public readonly supportsAdaptiveMaterial: boolean;
  public readonly supportsImmersiveMaterial: boolean;
  public readonly supportsNativeUiMaterial: boolean;

  constructor(apiVersion: number, supportedTypes: hdsMaterial.MaterialType[]) {
    this.apiVersion = apiVersion;
    this.supportsAdaptiveMaterial = supportedTypes.indexOf(hdsMaterial.MaterialType.ADAPTIVE) >= 0 ||
      supportedTypes.indexOf(hdsMaterial.MaterialType.IMMERSIVE) >= 0;
    // HDS material is available since API 23; uiMaterial is a separate API 26 capability.
    this.supportsImmersiveMaterial = supportedTypes.indexOf(hdsMaterial.MaterialType.IMMERSIVE) >= 0;
    this.supportsNativeUiMaterial = apiVersion >= 26 && this.supportsImmersiveMaterial;
  }

  static current(): UiCapabilityProfile {
    let supportedTypes: hdsMaterial.MaterialType[] = [];
    try {
      supportedTypes = hdsMaterial.getSystemMaterialTypes();
    } catch (error) {
      console.warn(`Read HDS material support failed: ${String(error)}`);
    }
    console.info(`FacilisMaterial api=${deviceInfo.sdkApiVersion} types=${supportedTypes.join(',')}`);
    return new UiCapabilityProfile(deviceInfo.sdkApiVersion, supportedTypes);
  }

  materialFor(role: MaterialRole): SystemMaterialParams {
    if (!this.supportsAdaptiveMaterial && !this.supportsImmersiveMaterial) {
      return {
        materialType: hdsMaterial.MaterialType.ADAPTIVE,
        materialLevel: hdsMaterial.MaterialLevel.SMOOTH
      };
    }
    const useImmersive = this.supportsImmersiveMaterial &&
      (role === MaterialRole.CONTROL || role === MaterialRole.STAGE);
    return {
      materialType: useImmersive ? hdsMaterial.MaterialType.IMMERSIVE : hdsMaterial.MaterialType.ADAPTIVE,
      materialLevel: role === MaterialRole.STAGE ? hdsMaterial.MaterialLevel.GENTLE :
        hdsMaterial.MaterialLevel.ADAPTIVE
    };
  }
}

export class MaterialTheme {
  private static capabilities: UiCapabilityProfile | undefined = undefined;

  static resolve(role: MaterialRole): SystemMaterialParams {
    if (MaterialTheme.capabilities === undefined) {
      MaterialTheme.capabilities = UiCapabilityProfile.current();
    }
    return MaterialTheme.capabilities.materialFor(role);
  }

  static surface(role: MaterialRole, themeMode: number): MaterialSurfaceModifier {
    return new MaterialSurfaceModifier(role, themeMode);
  }
}

// Common content is not a supported API 26 uiMaterial container. Use one
// centralized system-blur fallback; never add a second blur or shadow in pages.
export class MaterialSurfaceModifier implements AttributeModifier<CommonAttribute> {
  private role: MaterialRole;
  private themeMode: number;

  constructor(role: MaterialRole, themeMode: number) {
    this.role = role;
    this.themeMode = themeMode;
  }

  applyNormalAttribute(component: CommonAttribute): void {
    component.backgroundColor(Color.Transparent)
      .backgroundEffect({
        radius: this.role === MaterialRole.STAGE ? 28 : 22,
        saturation: 1.12,
        brightness: 1,
        color: HarmonyTokens.glassSurface(),
        policy: BlurStyleActivePolicy.FOLLOWS_WINDOW_ACTIVE_STATE,
        inactiveColor: HarmonyTokens.surface()
      })
      .linearGradient({
        angle: 135,
        colors: [[HarmonyTokens.glassHighlight(), 0], [this.clearHighlight(), 0.38],
          [this.clearHighlight(), 0.72], [HarmonyTokens.primaryGlow(), 1]]
      })
      .border({ width: 0.75, color: {
        top: HarmonyTokens.glassHighlight(),
        left: HarmonyTokens.glassHighlight(),
        bottom: HarmonyTokens.divider(),
        right: HarmonyTokens.divider()
      } });
  }

  private clearHighlight(): string {
    return this.themeMode === ThemeMode.DARK ? '#00FFEAD7' : '#00FFFFFF';
  }
}
