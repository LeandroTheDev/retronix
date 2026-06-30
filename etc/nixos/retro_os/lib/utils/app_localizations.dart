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

  // ── Update System Page ────────────────────────────────────────────────────

  String get updateSystem      => _pick('Update System', 'Atualizar Sistema');
  String get updateTitle       => _pick('System Update', 'Atualização do Sistema');
  String get updateIdle        => _pick('Press confirm to start the update', 'Pressione confirmar para iniciar a atualização');
  String get updateRunning     => _pick('Updating...', 'Atualizando...');
  String get updateSuccess     => _pick('Update complete. Restart recommended.', 'Atualização concluída. Reinicialização recomendada.');
  String get updateError       => _pick('Update failed.', 'Falha na atualização.');
  String get updateBackHint      => _pick('Back to cancel / return', 'Voltar para cancelar / retornar');
  String get updateRebootQuestion => _pick('Update complete. Restart the system?', 'Atualização concluída, deseja reiniciar o sistema?');

  // ── Console Selector ──────────────────────────────────────────────────────

  String get selectConsole  => _pick('SELECT CONSOLE', 'SELECIONAR CONSOLE');
  String get noConsoleFound => _pick('No console found.', 'Nenhum console encontrado.');

  // Settings menu entries
  String get settingsNintendo64 => _pick('Nintendo 64 Settings', 'Configurações: Nintendo 64');
  String get aboutSystem        => _pick('About System', 'Sobre o sistema');
  String get shutdown           => _pick('Shutdown', 'Desligar');

  // Shutdown confirm dialog
  String get shutdownConfirm => _pick('Shut down the system?', 'Deseja desligar o sistema?');

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
  String get coreRetroArch           => 'RetroArch Core';
  String get coreFileNotFound        => _pick('File not found — games will not open', 'Arquivo não encontrado — os jogos não abrirão');
  String get restoreDefaults         => _pick('Restore Defaults', 'Restaurar padrões');

  List<String> get resolutionLabels =>
      [_pick('Native (240p)', 'Nativo (240p)'), 'HD (720p)', 'Full HD (1080p)', '4K (2160p)'];
  List<String> get msaaLabels       => [off, '2x', '4x', '8x'];
  List<String> get filterLabels     => [_pick('Nearest (pixelated)', 'Nearest (pixelado)'), _pick('Linear (smoothed)', 'Linear (suavizado)')];
  List<String> get frameDupesLabels => [off, on];

  // ── Game Open ─────────────────────────────────────────────────────────────

  String get startSelectToExit => _pick('Start + Select to exit', 'Start + Select para sair');

  String openingGame(String name)      => _pick('Opening $name', 'Abrindo $name');
  String romNotFound(String name)      => _pick('ROM not found for: $name', 'ROM não encontrada para: $name');
  String coreNotFoundPath(String path) => _pick('Core not found: $path', 'Core não encontrado: $path');
  String retroarchExitError(int code)  => _pick('RetroArch exited with error (code $code)', 'RetroArch encerrou com erro (código $code)');
  String retroarchLaunchError(Object e) => _pick('Failed to launch RetroArch: $e', 'Falha ao iniciar RetroArch: $e');

  // ── Shutdown Page ─────────────────────────────────────────────────────────

  String get shuttingDown => _pick('Shutting Down...', 'Desligando Sistema...');
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
