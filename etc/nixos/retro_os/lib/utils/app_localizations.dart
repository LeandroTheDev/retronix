import 'package:flutter/widgets.dart';

class AppLocalizations {
  const AppLocalizations(this.locale);

  final String locale;

  static AppLocalizations of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppLocalizationsScope>()!.localizations;

  String _pick(String enUs, String ptBr) => locale == 'pt_br' ? ptBr : enUs;

  // ── General ───────────────────────────────────────────────────────────────

  String get yes => _pick('Yes', 'Sim');
  String get no  => _pick('No', 'Não');
  String get off => _pick('Off', 'Desligado');
  String get on  => _pick('On', 'Ligado');

  // ── Language ──────────────────────────────────────────────────────────────

  String get language            => _pick('Language', 'Idioma');
  String get languageEnglish     => 'English';
  String get languagePortuguese  => 'Português';
  String get currentLanguageName => locale == 'pt_br' ? languagePortuguese : languageEnglish;

  // ── System Settings Page ─────────────────────────────────────────────────

  String get systemSettingsTitle => _pick('System Settings', 'Configurações do Sistema');
  String get screenResolution    => _pick('Screen Resolution', 'Resolução da Tela');
  String get noResolutionsFound  => _pick('No resolutions found', 'Nenhuma resolução encontrada');
  String get volume              => _pick('Volume', 'Volume');
  String get audioDevice         => _pick('Audio Device', 'Dispositivo de Áudio');
  String get restartSystem       => _pick('Restart System', 'Reiniciar Sistema');
  String get restartConfirm      => _pick('Restart the system?', 'Deseja reiniciar o sistema?');
  String get clearCache               => _pick('Clear Cache', 'Limpar Cache');
  String get clearCacheConfirm        => _pick('Clear Nix cache? This may take a while.', 'Limpar cache do Nix? Isso pode demorar.');
  String get clearCacheSuccess        => _pick('Cache cleared successfully', 'Cache limpo com sucesso');
  String get clearCacheError          => _pick('Failed to clear cache', 'Falha ao limpar cache');
  String get deleteConsoles           => _pick('Delete Consoles', 'Excluir Consoles');
  String get deleteConsolesConfirm    => _pick('Delete all consoles and games from this device?', 'Excluir todos os consoles e jogos deste dispositivo?');
  String get deleteConsolesSuccess    => _pick('Consoles deleted successfully', 'Consoles excluídos com sucesso');
  String get deleteConsolesError      => _pick('Failed to delete consoles', 'Falha ao excluir consoles');

  // ── Update System Page ────────────────────────────────────────────────────

  String get updateSystem      => _pick('Update System', 'Atualizar Sistema');
  String get updateTitle       => _pick('System Update', 'Atualização do Sistema');
  String get updateIdle        => _pick('Press confirm to start the update', 'Pressione confirmar para iniciar a atualização');
  String get updateRunning     => _pick('Updating...', 'Atualizando...');
  String get updateSuccess     => _pick('Update complete. Restart recommended.', 'Atualização concluída. Reinicialização recomendada.');
  String get updateError       => _pick('Update failed.', 'Falha na atualização.');
  String get updateBackHint      => _pick('Back to cancel / return', 'Voltar para cancelar / retornar');
  String get updateRebootQuestion => _pick('Update complete. Restart the system?', 'Atualização concluída, deseja reiniciar o sistema?');

  String get updateStepCleanTmp   => _pick('Cleaning temporary files', 'Limpando arquivos temporários');
  String get updateStepClone      => _pick('Cloning repository', 'Clonando repositório');
  String get updateStepRemoveOld  => _pick('Removing old configuration', 'Removendo configuração antiga');
  String get updateStepCopyNew    => _pick('Applying new configuration', 'Aplicando nova configuração');
  String get updateStepRebuild    => _pick('Rebuilding system (nixos-rebuild)', 'Recompilando sistema (nixos-rebuild)');

  // ── Splash Page ───────────────────────────────────────────────────────────

  String get welcomeSystem => _pick('Welcome', 'Bem Vindo');

  // ── Console Selector ──────────────────────────────────────────────────────

  String get selectConsole  => _pick('SELECT CONSOLE', 'SELECIONAR CONSOLE');
  String get noConsoleFound => _pick('No console found.', 'Nenhum console encontrado.');

  // Settings menu entries
  String get settingsNintendo64   => _pick('Nintendo 64 Settings', 'Configurações: Nintendo 64');
  String get settingsPlaystation2 => _pick('PlayStation 2 Settings', 'Configurações: PlayStation 2');
  String get settingsPlaystation1 => _pick('PlayStation 1 Settings', 'Configurações: PlayStation 1');
  String get settingsPC           => _pick('PC Settings', 'Configurações: PC');
  String get aboutSystem        => _pick('About System', 'Sobre o sistema');
  String get shutdown           => _pick('Shutdown', 'Desligar');

  // Shutdown confirm dialog
  String get shutdownConfirm => _pick('Shut down the system?', 'Deseja desligar o sistema?');

  // ── Download Provider Page ────────────────────────────────────────────────

  String get downloadProvider     => _pick('Download Provider', 'Download Provider');
  String get downloadProviderTitle => _pick('DOWNLOAD PROVIDER', 'DOWNLOAD PROVIDER');
  String get downloadProviderIdle => _pick(
    'Enter a provider URL to download consoles and games.\n\n'
    'Retronix strongly recommends using a local provider for security and copyright reasons.\n'
    'Retronix is not responsible for illegal ROMs. The user bears full responsibility for any content downloaded.',
    'Digite a URL do provider para baixar consoles e jogos.\n\n'
    'O Retronix recomenda fortemente o uso de um provider local por questões de segurança e direitos autorais.\n'
    'O Retronix não se responsabiliza por ROMs ilegais. O usuário tem total responsabilidade pelo conteúdo baixado.',
  );
  String get downloadProviderBackHint       => _pick('Back → return', 'Voltar → retornar');
  String get downloadProviderCancelHint     => _pick('Back → cancel download', 'Voltar → cancelar download');
  String get downloadProviderStartDownload  => _pick('Start Download', 'Iniciar Download');
  String get downloadProviderNoUrl          => _pick('No URL set.', 'Nenhuma URL definida.');
  String get downloadProviderFetching       => _pick('Fetching manifest...', 'Buscando manifesto...');
  String get downloadProviderDone           => _pick('Download complete!', 'Download concluído!');
  String get downloadProviderCancelled      => _pick('Download cancelled.', 'Download cancelado.');
  String downloadProviderDownloading(String name) => _pick('Downloading $name...', 'Baixando $name...');
  String downloadProviderSkipped(String name)     => _pick('$name already exists, skipping.', '$name já existe, pulando.');
  String downloadProviderFileDone(String name)    => _pick('$name ✓', '$name ✓');
  String downloadProviderError(Object e)          => _pick('Error: $e', 'Erro: $e');

  // ── Settings dialog ───────────────────────────────────────────────────────

  String get settingsDialogTitle => _pick('SETTINGS', 'CONFIGURAÇÕES');

  // ── Games Page ────────────────────────────────────────────────────────────

  String get noGameFound => _pick('No games found.', 'Nenhum jogo encontrado.');

  // ── Nintendo 64 Settings Page ─────────────────────────────────────────────

  String get nintendo64SettingsTitle => _pick('NINTENDO 64 — SETTINGS', 'NINTENDO 64 — CONFIGURAÇÕES');
  String get internalResolution      => _pick('Internal Resolution', 'Resolução Interna');
  String get antiAliasing            => 'Anti-Aliasing (MSAA)';
  String get textureFilter           => _pick('Texture Filter', 'Filtro de Textura');
  String get frameDuplication        => 'Frame Duplication (30fps → 60Hz)';
  String get aspectRatio             => _pick('Aspect Ratio', 'Proporção de Tela');
  String get overscanCrop            => _pick('Overscan Crop', 'Corte de Overscan');
  String get overscanAmount          => _pick('Overscan Amount', 'Quantidade de Overscan');
  String get showFps                 => _pick('Show FPS', 'Mostrar FPS');
  String get audioGain               => _pick('Audio Gain', 'Ganho de Áudio');
  String get coreRetroArch           => 'RetroArch Core';
  String get coreFileNotFound        => _pick('File not found — games will not open', 'Arquivo não encontrado — os jogos não abrirão');
  String get restoreDefaults         => _pick('Restore Defaults', 'Restaurar padrões');
  String get openRetroarch           => _pick('Open RetroArch', 'Abrir RetroArch');

  List<String> get resolutionLabels =>
      [_pick('Native (240p)', 'Nativo (240p)'), 'HD (720p)', 'Full HD (1080p)', '4K (2160p)'];
  List<String> get msaaLabels       => [off, '2x', '4x', '8x'];
  List<String> get filterLabels     => [_pick('Nearest (pixelated)', 'Nearest (pixelado)'), _pick('Linear (smoothed)', 'Linear (suavizado)')];
  List<String> get frameDupesLabels => [off, on];
  List<String> get aspectLabels     =>
      ['4:3', '16:9', _pick('16:9 (adjusted)', '16:9 (ajustado)'), _pick('Fill Screen', 'Preencher Tela')];
  List<String> get overscanEnabledLabels => [off, on];
  List<String> get fpsShowLabels    => [off, on];

  // ── About System Page ─────────────────────────────────────────────────────

  String get aboutSystemTitle    => _pick('ABOUT SYSTEM', 'SOBRE O SISTEMA');
  String get aboutDevice         => _pick('Device', 'Dispositivo');
  String get aboutArchitecture   => _pick('CPU Architecture', 'Arquitetura da CPU');
  String get aboutDisplay        => _pick('Display', 'Tela');
  String get aboutOpenGl         => 'OpenGL Version';
  String get aboutRenderer       => _pick('GPU Renderer', 'Renderizador GPU');

  // ── Bluetooth Page ────────────────────────────────────────────────────────

  String get bluetooth               => 'Bluetooth';
  String get bluetoothTitle          => _pick('BLUETOOTH', 'BLUETOOTH');
  String get bluetoothScanning       => _pick('Scanning for devices...', 'Procurando dispositivos...');
  String get bluetoothNoDevicesFound => _pick('No devices found yet', 'Nenhum dispositivo encontrado ainda');
  String get bluetoothConnected      => _pick('Connected', 'Conectado');
  String get bluetoothPaired         => _pick('Paired', 'Pareado');
  String get bluetoothConnecting     => _pick('Connecting...', 'Conectando...');
  String get bluetoothDisconnecting  => _pick('Disconnecting...', 'Desconectando...');

  String bluetoothConnectFailed(String name) =>
      _pick('Failed to connect to $name', 'Falha ao conectar a $name');
  String bluetoothDisconnectFailed(String name) =>
      _pick('Failed to disconnect from $name', 'Falha ao desconectar de $name');

  // ── Game Details Page ─────────────────────────────────────────────────────

  String get play                => _pick('PLAY', 'JOGAR');
  String get achievementsTitle   => _pick('Achievements', 'Conquistas');
  String get noAchievementsFound => _pick('No achievements yet', 'Nenhuma conquista ainda');
  String achievementPoints(int points)     => _pick('$points pts', '$points pts');
  String achievementPointsGain(int points) => _pick('+$points pts', '+$points pts');
  String achievementsSummary(int count, int points) =>
      _pick('$count achievements • $points pts', '$count conquistas • $points pts');
  String achievementsUnlockedSummary(int unlocked, int total) =>
      _pick('$unlocked / $total unlocked', '$unlocked / $total desbloqueadas');

  // ── Game Details Page (extra) ─────────────────────────────────────────────

  String get cancel                    => _pick('Cancel', 'Cancelar');
  String get totalPlaytime             => _pick('Total Playtime', 'Tempo Total');
  String get neverPlayed               => _pick('Never played', 'Nunca jogado');
  String get resetAchievements         => _pick('Reset Achievements', 'Resetar Conquistas');
  String get resetAchievementsConfirm  => _pick('Reset all achievement progress for this game?', 'Resetar todo o progresso de conquistas deste jogo?');
  String get resetAchievementsButton   => _pick('Reset', 'Resetar');

  // ── Games Page ── (title) ─────────────────────────────────────────────────

  String get nintendo64Title    => 'NINTENDO 64';
  String get playstation2Title  => 'PLAYSTATION 2';
  String get playstation1Title  => 'PLAYSTATION 1';
  String get pcTitle            => 'PC';

  // ── PC Settings Page ──────────────────────────────────────────────────────

  String get pcSettingsTitle      => _pick('PC — SETTINGS', 'PC — CONFIGURAÇÕES');
  String pcGameInfoNotFound(String name) => _pick('game_info.json not found for: $name', 'game_info.json não encontrado para: $name');
  String pcLaunchError(Object e)  => _pick('Failed to launch: $e', 'Falha ao iniciar: $e');
  String pcExitError(int code)    => _pick('Process exited with error (code $code)', 'Processo encerrou com erro (código $code)');

  // ── Playstation 2 Settings Page ───────────────────────────────────────────

  String get playstation2SettingsTitle  => _pick('PLAYSTATION 2 — SETTINGS', 'PLAYSTATION 2 — CONFIGURAÇÕES');
  String get ps2UpscaleMultiplier       => _pick('Upscale Multiplier', 'Multiplicador de Escala');
  String get ps2PresentationMode        => _pick('Presentation Mode', 'Modo de Apresentação');
  String get ps2BilinearFilter          => _pick('Bilinear Filtering', 'Filtro Bilinear');

  List<String> get ps2UpscaleLabels       => ['1x', '2x', '4x', '8x'];
  List<String> get ps2PresentationLabels  =>
      [_pick('Fit Screen', 'Ajustar Tela'), _pick('Fill Screen', 'Preencher Tela'), _pick('Original Size', 'Tamanho Original')];
  List<String> get ps2BilinearLabels      => [off, on];

  // ── Playstation 1 Settings Page ───────────────────────────────────────────
  String get playstation1SettingsTitle => _pick('PLAYSTATION 1 — SETTINGS', 'PLAYSTATION 1 — CONFIGURAÇÕES');
  String get ps1Dithering              => 'Dithering';
  String get ps1SmoothSprites          => _pick('Smooth Sprites', 'Sprites Suavizados');
  String get ps1HiResSprites           => _pick('Hi-Res Sprites', 'Sprites em Alta Resolução');
  String get ps1Frameskip              => 'Frameskip';
  List<String> get ps1DitheringLabels  => [on, off];
  List<String> get ps1SmoothLabels     => [off, on];
  List<String> get ps1HiResLabels      => [off, on];
  List<String> get ps1FrameskipLabels  => [_pick('Disabled', 'Desativado'), 'Auto'];
  List<String> get ps1AspectLabels     => ['4:3', _pick('Fill Screen', 'Preencher Tela')];

  // ── Game Open ─────────────────────────────────────────────────────────────

  String get gameRunning     => _pick('Game is running!', 'Jogo está rodando!');
  String get holdStartToExit => _pick('Hold Start for 5 seconds to exit', 'Segure Start por 5 segundos para sair');

  String get hudSession          => _pick('SESSION', 'SESSÃO');
  String get hudTotal            => _pick('TOTAL', 'TOTAL');
  String get hudNoneThisSession  => _pick('None unlocked this session', 'Nenhuma conquistada nesta sessão');
  String hudMoreThisSession(int n) => _pick('+$n more this session', '+$n nesta sessão');

  String openingGame(String name)      => _pick('Opening $name', 'Abrindo $name');
  String romNotFound(String name)      => _pick('ROM not found for: $name', 'ROM não encontrada para: $name');
  String coreNotFoundPath(String path) => _pick('Core not found: $path', 'Core não encontrado: $path');
  String retroarchExitError(int code)  => _pick('RetroArch exited with error (code $code)', 'RetroArch encerrou com erro (código $code)');
  String retroarchLaunchError(Object e) => _pick('Failed to launch RetroArch: $e', 'Falha ao iniciar RetroArch: $e');

  // ── Shutdown Page ─────────────────────────────────────────────────────────

  String get shuttingDown => _pick('Shutting Down...', 'Desligando Sistema...');

  // ── Restart Page ──────────────────────────────────────────────────────────

  String get restarting => _pick('Restarting System...', 'Reiniciando Sistema...');

  // ── Gamepad ───────────────────────────────────────────────────────────────

  String get controllerFallbackName => _pick('Controller', 'Controle');
  String controllerConnected(int player, String name) =>
      _pick('Player $player connected: $name', 'Jogador $player conectado: $name');

  // ── Achievement Notification ──────────────────────────────────────────────

  String get achievementUnlocked => _pick('ACHIEVEMENT UNLOCKED', 'CONQUISTA DESBLOQUEADA');

  // ── Settings value suffixes ───────────────────────────────────────────────

  String overscanAmountValue(String px) => '${px}px';
  String audioGainValue(String db)      => '+$db dB';
}

class AppLocalizationsScope extends InheritedWidget {
  const AppLocalizationsScope({
    super.key,
    required this.localizations,
    required super.child,
  });

  final AppLocalizations localizations;

  @override
  bool updateShouldNotify(AppLocalizationsScope old) =>
      localizations.locale != old.localizations.locale;
}
