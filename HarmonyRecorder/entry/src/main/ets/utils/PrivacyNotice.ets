export class PrivacySection {
  public readonly title: string;
  public readonly content: string;

  constructor(title: string, content: string) {
    this.title = title;
    this.content = content;
  }
}

// Available offline; store privacy hosting will supply the formal publisher
// identity and consent flow after the publisher has registered the application.
export class PrivacyNotice {
  static readonly SECTIONS: PrivacySection[] = [
    new PrivacySection('录音与权限',
      '点击录音并允许麦克风权限后，应用才采集声音。拒绝权限仍可使用已有录音。可在本页“麦克风权限”中开启，或在系统设置的“应用和元服务 > Facilis Recording > 权限”中关闭。'),
    new PrivacySection('后台录音',
      '主动录音时申请系统持续录音任务并显示通知，支持切换应用和锁屏后录音。暂停或结束时释放任务；系统取消任务时停止采集并尝试保存已有内容。应用不会在后台自行开始录音。'),
    new PrivacySection('本地处理',
      '录音、名称和格式等资料保存在应用私有目录；播放和格式转换均在本地完成。应用不要求账号，不含广告、统计或第三方运行时 SDK，不申请网络权限，也不主动上传音频或资料。已关闭应用备份恢复。'),
    new PrivacySection('保存与分享',
      '只有你主动分享时才调用系统分享面板，由你选择接收方。接收方的后续处理由其自身规则决定。保存到设备的副本独立于应用内原件，删除原件不会删除外部副本；格式转换生成新文件并保留原件。'),
    new PrivacySection('PCM 分享副本',
      '导出 PCM 会生成本地工作副本。应用不会主动删除生成 24 小时内的完整副本，避免中断分享接收方读取；之后可在设置中清理。超过 7 天后，在下次启动或导出 PCM 时自动清理。旧版本留下的 PCM 副本仅手动清理。清理不会删除资料库、最近删除或保存到设备的文件；取消分享不会立即删除完整工作副本。'),
    new PrivacySection('删除与撤回',
      '录音可移入最近删除、恢复或永久删除。永久删除后应用不提供恢复；卸载或清除应用数据可能清除全部应用内录音及工作副本。请先导出重要文件。撤回麦克风权限后不能新增录音，已有录音仍可使用。'),
    new PrivacySection('问题反馈',
      '项目反馈：github.com/CloudWhiteTower/facilis-recording/issues\n请勿公开上传私人录音；反馈时仅提供最小必要信息。')
  ];
}
