{{flutter_js}}
{{flutter_build_config}}

// Avisa a tela inicial (index.html) em que etapa a abertura esta, para a
// barra de porcentagem que aparece quando o aparelho esta sem internet.
function vmacStage(name) {
  try {
    if (window.vmacSetStage) window.vmacSetStage(name);
  } catch (e) {}
}

var vmacConfig = {
  canvasKitBaseUrl: '/canvaskit/',
};

_flutter.loader.load({
  config: vmacConfig,
  onEntrypointLoaded: async function (engineInitializer) {
    vmacStage('entrypoint');
    var appRunner = await engineInitializer.initializeEngine(vmacConfig);
    vmacStage('engine');
    await appRunner.runApp();
  },
});
